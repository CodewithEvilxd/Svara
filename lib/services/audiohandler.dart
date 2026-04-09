// lib/shared/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/snackbar.dart';
import '../shared/player.dart';
import '../utils/theme.dart';
import 'defaultfetcher.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import 'jamsync.dart';
import 'offlinemanager.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import 'shufflemanager.dart';

enum RepeatMode { none, one, all }

/// One provider to rule them all 🚀
final audioHandlerProvider = FutureProvider<MyAudioHandler>((ref) async {
  final handler = await AudioService.init(
    builder: () => MyAudioHandler(ref),
    config: AudioServiceConfig(
      androidNotificationChannelId: '$appPackageName.channel.audio',
      androidNotificationChannelName: '$appDisplayName Audio Player',
      androidNotificationIcon: 'drawable/ic_launcher_foreground',
      androidShowNotificationBadge: true,
      androidResumeOnClick: true,
      // androidStopForegroundOnPause: false,
    ),
  );
  return handler;
});

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final Ref ref;
  final AudioPlayer _player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 20),
        maxBufferDuration: Duration(seconds: 60),
        bufferForPlaybackDuration: Duration(milliseconds: 1200),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
        prioritizeTimeOverSizeThresholds: true,
      ),
      darwinLoadControl: DarwinLoadControl(
        automaticallyWaitsToMinimizeStalling: true,
        preferredForwardBufferDuration: Duration(seconds: 30),
      ),
    ),
    useLazyPreparation: false,
    maxSkipsOnError: 6,
  );

  // shuffle manager
  final ShuffleManager _shuffleManager = ShuffleManager();
  ShuffleManager get shuffleManager => _shuffleManager;

  List<SongDetail> _queue = [];
  int _currentIndex = -1;

  MyAudioHandler(this.ref) {
    // keep system playbackState in sync
    _player.playerStateStream.listen(_updatePlaybackState);

    _player.positionStream.listen((pos) {
      final old = playbackState.value;
      playbackState.add(
        old.copyWith(
          updatePosition: pos,
          bufferedPosition: _player.bufferedPosition,
        ),
      );
      _maybeSyncJamHeartbeat();
    });

    _player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        await _onSongEnded();
      }
    });

    _player.bufferedPositionStream.listen((buf) {
      final old = playbackState.value;
      playbackState.add(old.copyWith(bufferedPosition: buf));
    });

    _player.durationStream.listen((dur) {
      final current = mediaItem.value;
      if (current != null && dur != null && current.duration != dur) {
        mediaItem.add(current.copyWith(duration: dur));
      }
    });

    // duration watch
    Duration lastPosition = Duration.zero;
    Timer? playbackTimer;

    _player.positionStream.listen((pos) async {
      final current = currentSong;
      if (current == null) return;

      final delta = pos - lastPosition;
      if (delta.inSeconds >= 5) {
        // only update every 5 seconds
        lastPosition = pos;

        playbackTimer?.cancel();
        playbackTimer = Timer(const Duration(seconds: 1), () async {
          await AppDatabase.addPlayedDuration(current.id, delta);
        });
      }
    });

    // resume last played song if exists
    _initLastPlayed();
    ref.read(jamServiceProvider).attachPlaybackBridge(
      snapshotBuilder: buildJamSyncSnapshot,
      remoteApplier: applyJamSnapshot,
      controlRequestHandler: handleJamControlRequest,
    );
  }

  // --- Public getters
  SongDetail? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  // Spotify-like controls: previous should restart or go back, and next can
  // continue into autoplay recommendations when the queue ends.
  bool get hasNext =>
      _queue.isNotEmpty &&
      (_currentIndex + 1 < _queue.length ||
          _repeat == RepeatMode.all ||
          hasInternet.value);

  bool get hasPrevious => _queue.isNotEmpty;

  RepeatMode _repeat = RepeatMode.none;
  RepeatMode get repeatMode => _repeat;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  int get queueLength => _queue.length;
  List<SongDetail> get queueSongs => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  static const int _autoplayTriggerRemaining = 2;
  static const int _autoplayBatchSize = 10;
  bool _isAutoplayLoading = false;
  bool _isApplyingRemoteJamState = false;
  int _lastJamProgressSyncAtMs = 0;

  // --- Shuffle & repeat

  bool isShuffleChanging = false;
  bool get isShuffle => _shuffleManager.isShuffling;

  Future<void> toggleShuffle() async {
    if (_queue.isEmpty) return;

    isShuffleChanging = true;

    final current = currentSong;

    // Ensure ShuffleManager has the latest queue
    _shuffleManager.loadQueue(List.from(_queue), currentIndex: _currentIndex);

    // Toggle shuffle state
    _shuffleManager.toggleShuffle(currentSong: current);

    // Sync handler queue and index
    _queue = List.from(_shuffleManager.currentQueue);
    _currentIndex = _shuffleManager.currentIndex;

    // Notify listeners
    queue.add(_queue.map(songToMediaItem).toList());
    ref.read(shuffleProvider.notifier).state = _shuffleManager.isShuffling;

    isShuffleChanging = false;
    unawaited(_syncJamSession(force: true));
  }

  /// Explicitly turn shuffle OFF safely
  Future<void> disableShuffle() async {
    if (_shuffleManager.isShuffling) {
      final current = currentSong;

      // Toggle shuffle off without touching original playlist order
      _shuffleManager.toggleShuffle(currentSong: current);

      // Sync handler queue/index with original queue
      _queue = List.from(_shuffleManager.currentQueue);
      _currentIndex = _shuffleManager.currentIndex;

      // Notify listeners
      queue.add(_queue.map(songToMediaItem).toList());
      ref.read(shuffleProvider.notifier).state = false;
      unawaited(_syncJamSession(force: true));
    }
  }

  void _enforceQueueLimit() async {
    if (_queue.length > 50) {
      final cutoff = _queue.length - 50;
      if (_currentIndex >= cutoff) {
        _currentIndex -= cutoff;
      } else {
        _currentIndex = 0;
      }
      _queue = _queue.sublist(cutoff);

      // Sync with ShuffleManager (reloads queue to handle truncation safely)
      _shuffleManager.loadQueue(_queue, currentIndex: _currentIndex);

      await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    }
  }

  void updateQueueFromShuffle() {
    _queue = _shuffleManager.currentQueue;
    _currentIndex = _shuffleManager.currentIndex;
  }

  void toggleRepeatMode() {
    switch (_repeat) {
      case RepeatMode.none:
        _repeat = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeat = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeat = RepeatMode.none;
        break;
    }
    ref.read(repeatModeProvider.notifier).state = _repeat;
  }

  // --- AudioHandler API
  bool _isPausedManually = false;

  @override
  Future<void> pause() async {
    if (await _sendJamControlRequestIfGuest(
      'pause',
      position: _player.position,
    )) {
      return;
    }
    _isPausedManually = true;
    playbackState.add(playbackState.value.copyWith(playing: false));
    await _player.pause();
    await _player.pause(); // temporary bug need to fix later
    unawaited(_syncJamSession(force: true));
  }

  @override
  Future<void> play() async {
    if (await _sendJamControlRequestIfGuest(
      'play',
      position: _player.position,
    )) {
      return;
    }
    _isPausedManually = false;
    if (_currentIndex < 0 && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _playCurrent();
    } else {
      await _player.play();
      unawaited(_syncJamSession(force: true));
    }
  }

  Future<void> _onSongEnded() async {
    if (_isPausedManually) return;
    if (_shouldInterceptJamControls) {
      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.completed,
        ),
      );
      return;
    }

    if (_repeat == RepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    int? nextIndex;

    // 🔹 use shuffle logic
    if (_shuffleManager.isShuffling) {
      nextIndex = _shuffleManager.getNextIndex();
    } else {
      nextIndex = await _getNextPlayableIndex();
    }

    if (nextIndex == null && _repeat == RepeatMode.all && _queue.isNotEmpty) {
      nextIndex =
          _shuffleManager.isShuffling
              ? _shuffleManager.getNextIndex(wrap: true)
              : await _getFirstPlayableIndex();
    }

    if (nextIndex == null &&
        _repeat == RepeatMode.none &&
        await _appendAutoplaySongs(seed: currentSong, force: true)) {
      nextIndex =
          _shuffleManager.isShuffling
              ? _shuffleManager.getNextIndex()
              : await _getNextPlayableIndex();
    }

    if (nextIndex != null) {
      _currentIndex = nextIndex;
      await _playCurrent(skipCompletedCheck: true);
      return;
    }

    await stop();
    _currentIndex = -1;
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: -1,
      ),
    );
  }

  Future<int?> _getNextPlayableIndex({int? start}) async {
    if (_queue.isEmpty) return null;

    final begin = (start ?? _currentIndex) + 1;
    for (int idx = begin; idx < _queue.length; idx++) {
      if (_isPlayable(_queue[idx])) return idx;
    }

    return null;
  }

  Future<int?> _getPreviousPlayableIndex({int? start}) async {
    if (_queue.isEmpty) return null;

    final begin = (start ?? _currentIndex) - 1;
    for (int idx = begin; idx >= 0; idx--) {
      if (_isPlayable(_queue[idx])) return idx;
    }

    return null;
  }

  Future<int?> _getFirstPlayableIndex() async {
    for (int idx = 0; idx < _queue.length; idx++) {
      if (_isPlayable(_queue[idx])) return idx;
    }
    return null;
  }

  Future<int?> _getLastPlayableIndex() async {
    for (int idx = _queue.length - 1; idx >= 0; idx--) {
      if (_isPlayable(_queue[idx])) return idx;
    }
    return null;
  }

  bool _isPlayable(SongDetail song) =>
      offlineManager.isAvailableOffline(songId: song.id) || hasInternet.value;

  @override
  Future<void> skipToNext() async {
    if (await _sendJamControlRequestIfGuest('next')) {
      return;
    }
    if (_queue.isEmpty) return;

    if (_repeat == RepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    int? nextIndex;

    // 🔹 Handle shuffle via ShuffleManager
    if (_shuffleManager.isShuffling) {
      nextIndex = _shuffleManager.getNextIndex();
    } else {
      nextIndex = await _getNextPlayableIndex();
    }

    if (nextIndex == null && _repeat == RepeatMode.all && _queue.isNotEmpty) {
      nextIndex =
          _shuffleManager.isShuffling
              ? _shuffleManager.getNextIndex(wrap: true)
              : await _getFirstPlayableIndex();
    }

    if (nextIndex == null &&
        await _appendAutoplaySongs(seed: currentSong, force: true)) {
      nextIndex =
          _shuffleManager.isShuffling
              ? _shuffleManager.getNextIndex()
              : await _getNextPlayableIndex();
    }

    if (nextIndex == null) {
      await stop();
      return;
    }

    _currentIndex = nextIndex;
    await _playCurrent();
  }

  Future<void> addSongNext(SongDetail song) async {
    if (_queue.any((s) => s.id == song.id)) return;

    final insertIndex = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(insertIndex, song);

    // Sync with ShuffleManager
    _shuffleManager.insertSong(insertIndex, song);

    final updated = List<MediaItem>.from(queue.value);
    updated.insert(insertIndex, songToMediaItem(song));
    queue.add(updated);
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    unawaited(_syncJamSession(force: true));
  }

  Future<void> addSongToQueue(SongDetail song) async {
    if (_queue.any((s) => s.id == song.id)) return;

    _queue.add(song);

    // Sync with ShuffleManager
    _shuffleManager.addSong(song);

    _enforceQueueLimit();

    final updated = List<MediaItem>.from(queue.value)
      ..add(songToMediaItem(song));
    queue.add(updated);
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    unawaited(_syncJamSession(force: true));
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (await _sendJamControlRequestIfGuest('jump', queueIndex: index)) {
      return;
    }
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      _shuffleManager.updateCurrentIndex(index);
      await _playCurrent();
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    return super.onTaskRemoved();
  }

  @override
  Future<void> seek(Duration position) async {
    if (await _sendJamControlRequestIfGuest('seek', position: position)) {
      return;
    }
    await _player.seek(position);
    final old = playbackState.value;
    playbackState.add(old.copyWith(updatePosition: position));
    unawaited(_syncJamSession(force: true));
  }

  @override
  Future<void> skipToPrevious() async {
    if (await _sendJamControlRequestIfGuest('previous')) {
      return;
    }
    if (_queue.isEmpty) return;

    if (_player.position >= const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    if (_repeat == RepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    int? prevIndex;

    // 🔹 Use shuffle manager for back navigation
    if (_shuffleManager.isShuffling) {
      prevIndex = _shuffleManager.getPreviousIndex();
    } else {
      prevIndex = await _getPreviousPlayableIndex();
    }

    if (prevIndex == null && _repeat == RepeatMode.all) {
      prevIndex =
          _shuffleManager.isShuffling
              ? _shuffleManager.getPreviousIndex(wrap: true)
              : await _getLastPlayableIndex();
    }

    if (prevIndex == null || prevIndex < 0) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    _currentIndex = prevIndex;
    await _playCurrent();
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    final idx = _queue.indexWhere((s) => s.id == mediaItem.id);
    if (idx >= 0 &&
        await _sendJamControlRequestIfGuest('jump', queueIndex: idx)) {
      return;
    }
    if (idx >= 0 && idx != _currentIndex) {
      _currentIndex = idx;
      _shuffleManager.updateCurrentIndex(idx);
      await _playCurrent();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final song = await AppDatabase.getSong(mediaItem.id);
    if (song == null) return;

    // Avoid duplicates
    _queue.removeWhere((s) => s.id == song.id);
    _queue.add(song);
    _enforceQueueLimit();

    // 🔹 Update shuffle list without re-toggling shuffle
    _shuffleManager.addSong(song);

    queue.add(_queue.map(songToMediaItem).toList());
    unawaited(_syncJamSession(force: true));
  }

  String? _queueSourceId;
  String? _queueSourceName;

  String? get queueSourceId => _queueSourceId;
  String? get queueSourceName => _queueSourceName;

  Future<JamSyncSnapshot?> buildJamSyncSnapshot() async {
    if (_queue.isEmpty || _currentIndex < 0 || _currentIndex >= _queue.length) {
      return null;
    }

    return JamSyncSnapshot(
      sourceName: _queueSourceName ?? currentSong?.title ?? 'Jam Session',
      hostName: username.trim().isNotEmpty ? username.trim() : defaultUsername,
      queue: List<SongDetail>.from(_queue),
      currentIndex: _currentIndex,
      positionMs: _player.position.inMilliseconds,
      isPlaying: _player.playing,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> applyJamSnapshot(JamSyncSnapshot snapshot) async {
    if (snapshot.queue.isEmpty) return;

    _isApplyingRemoteJamState = true;
    try {
      final incomingQueue = List<SongDetail>.from(snapshot.queue);
      final safeIndex = snapshot.currentIndex.clamp(0, incomingQueue.length - 1);
      final targetSong = incomingQueue[safeIndex];
      final queueChanged = !_queueHasSameIds(_queue, incomingQueue);
      final shouldReloadSource =
          queueChanged ||
          _currentIndex != safeIndex ||
          mediaItem.value?.id != targetSong.id;

      _queue = incomingQueue;
      _currentIndex = safeIndex;
      _queueSourceId = 'jam:${snapshot.sessionId}';
      _queueSourceName =
          snapshot.sourceName.isNotEmpty ? snapshot.sourceName : 'Jam Session';

      _shuffleManager.loadQueue(_queue, currentIndex: _currentIndex);
      queue.add(_queue.map(songToMediaItem).toList());
      ref.read(currentSongProvider.notifier).state = targetSong;
      await LastQueueStorage.save(_queue, currentIndex: _currentIndex);

      if (shouldReloadSource) {
        await _loadCurrentSource(
          autoPlay: snapshot.isPlaying,
          initialPosition: Duration(milliseconds: snapshot.effectivePositionMs),
          skipCompletedCheck: true,
        );
        return;
      }

      final targetPosition = Duration(milliseconds: snapshot.effectivePositionMs);
      final driftMs = (_player.position - targetPosition).inMilliseconds.abs();
      if (driftMs > 1500) {
        await _player.seek(targetPosition);
      }

      if (snapshot.isPlaying) {
        if (!_player.playing) {
          await _player.play();
        }
      } else {
        if (_player.playing) {
          await _player.pause();
        }
        playbackState.add(
          playbackState.value.copyWith(
            playing: false,
            updatePosition: targetPosition,
            queueIndex: _currentIndex,
          ),
        );
      }
    } finally {
      _isApplyingRemoteJamState = false;
    }
  }

  Future<void> handleJamControlRequest(JamControlRequest request) async {
    switch (request.action) {
      case 'play':
        final positionMs = request.positionMs;
        if (positionMs != null) {
          await _player.seek(Duration(milliseconds: positionMs));
        }
        await play();
        return;
      case 'pause':
        final positionMs = request.positionMs;
        if (positionMs != null) {
          final target = Duration(milliseconds: positionMs);
          if ((_player.position - target).inMilliseconds.abs() > 1200) {
            await _player.seek(target);
          }
        }
        await pause();
        return;
      case 'seek':
        final positionMs = request.positionMs;
        if (positionMs != null) {
          await seek(Duration(milliseconds: positionMs));
        }
        return;
      case 'next':
        await skipToNext();
        return;
      case 'previous':
        await skipToPrevious();
        return;
      case 'jump':
        final queueIndex = request.queueIndex;
        if (queueIndex != null) {
          await skipToQueueItem(queueIndex);
        }
        return;
    }
  }

  Future<void> _syncJamSession({bool force = false}) async {
    if (_isApplyingRemoteJamState) return;
    await ref.read(jamServiceProvider).syncFromPlayback(force: force);
  }

  void _maybeSyncJamHeartbeat() {
    final jamState = ref.read(jamSessionProvider);
    if (_isApplyingRemoteJamState ||
        !_player.playing ||
        !jamState.isActive ||
        !jamState.isHost) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastJamProgressSyncAtMs < 1200) {
      return;
    }

    _lastJamProgressSyncAtMs = now;
    unawaited(_syncJamSession());
  }

  bool get _shouldInterceptJamControls {
    final jamState = ref.read(jamSessionProvider);
    return jamState.isActive && !jamState.isHost && !_isApplyingRemoteJamState;
  }

  Future<bool> _sendJamControlRequestIfGuest(
    String action, {
    Duration? position,
    int? queueIndex,
  }) async {
    if (!_shouldInterceptJamControls) {
      return false;
    }

    await ref.read(jamServiceProvider).sendControlRequest(
      action,
      positionMs: position?.inMilliseconds,
      queueIndex: queueIndex,
    );
    return true;
  }

  bool _queueHasSameIds(List<SongDetail> left, List<SongDetail> right) {
    if (left.length != right.length) return false;
    for (int index = 0; index < left.length; index++) {
      if (left[index].id != right[index].id) {
        return false;
      }
    }
    return true;
  }

  Future<void> _prefetchQueueWindow({int lookAhead = 4}) async {
    if (_queue.isEmpty) return;

    final start = _currentIndex < 0 ? 0 : _currentIndex;
    final end = (start + lookAhead).clamp(start, _queue.length).toInt();
    final ids =
        _queue
            .sublist(start, end)
            .where((song) => song.downloadUrls.isEmpty)
            .map((song) => song.id)
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

    if (ids.isEmpty) return;

    final fetched = await saavn.getSongDetails(ids: ids);
    if (fetched.isEmpty) return;

    final fetchedMap = {for (final song in fetched) song.id: song};
    for (int i = 0; i < _queue.length; i++) {
      final updated = fetchedMap[_queue[i].id];
      if (updated != null) {
        _queue[i] = updated;
      }
    }
    queue.add(_queue.map(songToMediaItem).toList());
  }

  SourceUrl _preferredStreamSource(SongDetail song) {
    if (song.downloadUrls.isEmpty) {
      return SourceUrl(quality: 'default', url: song.url);
    }

    const qualityPriority = <String, int>{
      '160kbps': 0,
      '96kbps': 1,
      '48kbps': 2,
      '320kbps': 3,
      '12kbps': 4,
      'default': 5,
    };

    final sorted = List<SourceUrl>.from(song.downloadUrls)
      ..sort((a, b) {
        final aRank = qualityPriority[a.quality.toLowerCase()] ?? 999;
        final bRank = qualityPriority[b.quality.toLowerCase()] ?? 999;
        return aRank.compareTo(bRank);
      });
    return sorted.first;
  }

  Future<void> loadQueue(
    List<SongDetail> songs, {
    int startIndex = 0,
    String? sourceId,
    String? sourceName,
    bool autoPlay = true,
  }) async {
    _queue.clear();
    _currentIndex = -1;
    _queueSourceId = sourceId;
    _queueSourceName = sourceName;
    queue.add([]);

    if (songs.isEmpty) return;
    _queue = List.from(songs);
    _enforceQueueLimit();

    final safeStartIndex = startIndex.clamp(0, _queue.length - 1);

    // 🔹 Always load through shuffle manager for unified state
    _shuffleManager.loadQueue(_queue, currentIndex: safeStartIndex);

    if (_shuffleManager.isShuffling) {
      _queue = _shuffleManager.currentQueue;
      _currentIndex = _shuffleManager.currentIndex;
    } else {
      _currentIndex = safeStartIndex;
    }

    queue.add(_queue.map(songToMediaItem).toList());
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    unawaited(_prefetchQueueWindow(lookAhead: 5));

    if (autoPlay) {
      await _playCurrent();
    } else {
      await _loadCurrentSource(autoPlay: false);
    }
  }

  Future<void> playFromSeedSong(
    SongDetail song, {
    String? sourceId,
    String? sourceName,
  }) async {
    await AppDatabase.saveSongDetail(song);

    final recommendations = await _buildAutoplayRecommendations(
      song,
      limit: _autoplayBatchSize,
    );

    final queueSongs = <SongDetail>[
      song,
      ...recommendations.where((candidate) => candidate.id != song.id),
    ];

    await loadQueue(
      queueSongs,
      startIndex: 0,
      sourceId: sourceId ?? 'radio:${song.id}',
      sourceName: sourceName ?? '${song.title} Radio',
      autoPlay: true,
    );
  }

  Future<void> playSongNow(SongDetail song, {bool insertNext = false}) async {
    final existingIndex = _queue.indexWhere((s) => s.id == song.id);

    if (existingIndex >= 0) {
      _currentIndex = existingIndex;
      _shuffleManager.updateCurrentIndex(existingIndex);
    } else {
      final insertIndex =
          insertNext
              ? (_currentIndex + 1).clamp(0, _queue.length)
              : _currentIndex + 1;

      _queue.insert(insertIndex, song);
      _currentIndex = insertIndex;

      // Sync with ShuffleManager
      _shuffleManager.insertSong(insertIndex, song);
      _shuffleManager.updateCurrentIndex(insertIndex);

      queue.add(_queue.map(songToMediaItem).toList());
      _queueSourceName = song.album;
      _queueSourceId = 'Search';
    }

    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    await _playCurrent();
  }

  // --- Helpers
  Future<void> _playCurrent({bool skipCompletedCheck = false}) async {
    await _loadCurrentSource(
      autoPlay: true,
      skipCompletedCheck: skipCompletedCheck,
    );
  }

  Future<void> _loadCurrentSource({
    bool autoPlay = true,
    Duration initialPosition = Duration.zero,
    bool skipCompletedCheck = false,
  }) async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      await stop();
      return;
    }

    var song = _queue[_currentIndex];
    unawaited(_prefetchQueueWindow(lookAhead: 5));

    // fetch details if missing
    if (song.downloadUrls.isEmpty) {
      final fetched = await saavn.getSongDetails(ids: [song.id]);
      if (fetched.isNotEmpty) {
        song = fetched.first;
        _queue[_currentIndex] = song;
        await AppDatabase.saveSongDetail(song);
      }
    }

    if (song.downloadUrls.isEmpty) {
      info('Playback error, skipping to next song', Severity.warning);
      if (!skipCompletedCheck && autoPlay) await skipToNext();
      return;
    }

    ref.read(currentSongProvider.notifier).state = song;
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    await LastPlayedSongStorage.save(song);

    try {
      final localPath = offlineManager.getLocalPath(song.id);
      final streamSource = _preferredStreamSource(song);

      if (localPath != null && File(localPath).existsSync()) {
        debugPrint("▶ Playing offline: $localPath");
        await _player.setAudioSource(
          AudioSource.uri(Uri.file(localPath), tag: songToMediaItem(song)),
          initialPosition: initialPosition,
        );
      } else {
        debugPrint("▶ Playing online: ${song.downloadUrls.last.url}");
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.parse(streamSource.url),
            tag: songToMediaItem(song),
          ),
          initialPosition: initialPosition,
        );
      }

      mediaItem.add(songToMediaItem(song));
      if (autoPlay) {
        await _player.play();
        Future<void>(() async {
          await _appendAutoplaySongs(seed: song);
        });
      } else {
        playbackState.add(
          playbackState.value.copyWith(
            playing: false,
            processingState: AudioProcessingState.ready,
            updatePosition: initialPosition,
            queueIndex: _currentIndex,
          ),
        );
      }
      unawaited(_syncJamSession(force: true));
    } catch (e, st) {
      debugPrint("Error loading song: $e\n$st");
      if (!skipCompletedCheck && autoPlay) await skipToNext();
    }
  }

  Future<bool> _appendAutoplaySongs({
    SongDetail? seed,
    bool force = false,
  }) async {
    if (_isAutoplayLoading || _queue.isEmpty || !hasInternet.value) {
      return false;
    }

    final remainingSongs = _queue.length - (_currentIndex + 1);
    if (!force && remainingSongs > _autoplayTriggerRemaining) {
      return false;
    }

    final baseSong = seed ?? currentSong;
    if (baseSong == null) return false;

    _isAutoplayLoading = true;
    try {
      final recommendations = await _buildAutoplayRecommendations(
        baseSong,
        limit: _autoplayBatchSize,
      );

      final fresh =
          recommendations
              .where((song) => !_queue.any((queued) => queued.id == song.id))
              .toList();

      if (fresh.isEmpty) return false;

      if (_shuffleManager.isShuffling) {
        for (final song in fresh) {
          _shuffleManager.addSong(song);
        }
        _queue = List.from(_shuffleManager.currentQueue);
        _currentIndex = _shuffleManager.currentIndex;
      } else {
        _queue.addAll(fresh);
      }

      queue.add(_queue.map(songToMediaItem).toList());
      await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
      unawaited(_syncJamSession(force: true));
      return true;
    } catch (e, st) {
      debugPrint('Autoplay append failed: $e\n$st');
      return false;
    } finally {
      _isAutoplayLoading = false;
    }
  }

  Future<List<SongDetail>> _buildAutoplayRecommendations(
    SongDetail seed, {
    int limit = _autoplayBatchSize,
  }) async {
    await loadSearchHistory();
    final recentSongs = await loadLastSongs();

    final tasteArtistIds = <String>{
      ...recentSongs.expand(_extractArtistIds),
      ...ref.read(frequentArtistsProvider).map((artist) => artist.id),
    };

    final languageWeights = <String, int>{};
    void addLanguage(String language, {int weight = 1}) {
      final normalized = _normalizeText(language);
      if (normalized.isEmpty) return;
      languageWeights.update(
        normalized,
        (value) => value + weight,
        ifAbsent: () => weight,
      );
    }

    addLanguage(seed.language, weight: 4);
    for (final song in recentSongs.take(5)) {
      addLanguage(song.language, weight: 2);
    }

    final candidateMap = <String, SongDetail>{};
    final excludedIds = <String>{seed.id, ..._queue.map((song) => song.id)};
    final seedArtistIds = _extractArtistIds(seed).toList();
    final seedArtistNames = _extractArtistNames(seed).toList();

    void addCandidates(Iterable<SongDetail> songs) {
      for (final song in songs) {
        if (song.id.isEmpty || excludedIds.contains(song.id)) continue;
        candidateMap.putIfAbsent(song.id, () => song);
      }
    }

    for (final artistId in seedArtistIds.take(2)) {
      final details = await saavn.fetchArtistDetailsById(
        artistId: artistId,
        songCount: 20,
        albumCount: 5,
      );
      if (details == null) continue;

      addCandidates(details.topSongs);

      for (final similarArtist in details.similarArtists.take(2)) {
        final similarDetails = await saavn.fetchArtistDetailsById(
          artistId: similarArtist.id,
          songCount: 8,
          albumCount: 2,
        );
        if (similarDetails != null) {
          addCandidates(similarDetails.topSongs.take(5));
        }
      }
    }

    final queries = <String>[
      if (seedArtistNames.isNotEmpty)
        '${seed.title} ${seedArtistNames.first}'.trim(),
      if (seedArtistNames.isNotEmpty) seedArtistNames.first,
      if ((seed.albumName ?? seed.album).trim().isNotEmpty)
        '${seed.albumName ?? seed.album} ${seed.language}'.trim(),
      seed.title,
    ];

    for (final query in queries.where((value) => value.trim().isNotEmpty)) {
      final results = await saavn.searchSongs(query: query, limit: 20);
      addCandidates(results);
      if (candidateMap.length >= limit * 3) break;
    }

    final ranked =
        candidateMap.values.toList()..sort(
          (a, b) => _scoreAutoplayCandidate(
            b,
            seed: seed,
            tasteArtistIds: tasteArtistIds,
            languageWeights: languageWeights,
            tasteTerms: searchHistory,
          ).compareTo(
            _scoreAutoplayCandidate(
              a,
              seed: seed,
              tasteArtistIds: tasteArtistIds,
              languageWeights: languageWeights,
              tasteTerms: searchHistory,
            ),
          ),
        );

    final selected = ranked.take(limit).toList();
    for (final song in selected) {
      await AppDatabase.saveSongDetail(song);
    }

    return selected;
  }

  int _scoreAutoplayCandidate(
    SongDetail candidate, {
    required SongDetail seed,
    required Set<String> tasteArtistIds,
    required Map<String, int> languageWeights,
    required List<String> tasteTerms,
  }) {
    final candidateArtistIds = _extractArtistIds(candidate);
    final seedArtistIds = _extractArtistIds(seed);
    final candidateArtists = _extractArtistNames(candidate);
    final seedArtists = _extractArtistNames(seed);
    final candidateLanguage = _normalizeText(candidate.language);
    final seedLanguage = _normalizeText(seed.language);
    final candidateAlbum = _normalizeText(
      candidate.albumName ?? candidate.album,
    );
    final seedAlbum = _normalizeText(seed.albumName ?? seed.album);
    final candidateWords = _normalizedWords(
      '${candidate.title} ${candidate.albumName ?? candidate.album} ${candidate.primaryArtists}',
    );
    final seedWords = _normalizedWords(
      '${seed.title} ${seed.albumName ?? seed.album} ${seed.primaryArtists}',
    );

    int score = 0;

    if (candidateArtistIds.any(seedArtistIds.contains) ||
        candidateArtists.any(seedArtists.contains)) {
      score += 90;
    }

    if (candidateAlbum.isNotEmpty && candidateAlbum == seedAlbum) {
      score += 24;
    }

    if (candidateLanguage.isNotEmpty && candidateLanguage == seedLanguage) {
      score += 18;
    }

    score += (languageWeights[candidateLanguage] ?? 0) * 4;
    score += candidateArtistIds.where(tasteArtistIds.contains).length * 12;
    score += candidateWords.intersection(seedWords).length * 3;

    for (final term in tasteTerms.take(5)) {
      final normalized = _normalizeText(term);
      if (normalized.isEmpty) continue;
      if (candidateWords.contains(normalized) ||
          candidateArtists.any((artist) => artist.contains(normalized)) ||
          _normalizeText(candidate.title).contains(normalized)) {
        score += 3;
      }
    }

    if (candidate.explicitContent == seed.explicitContent) {
      score += 2;
    }

    return score;
  }

  Set<String> _extractArtistIds(SongDetail song) {
    final ids = <String>{};
    for (final artist in [
      ...song.contributors.primary,
      ...song.contributors.all,
    ]) {
      if (artist.id.isNotEmpty) ids.add(artist.id);
    }
    return ids;
  }

  Set<String> _extractArtistNames(SongDetail song) {
    final names = <String>{};
    for (final artist in [
      ...song.contributors.primary,
      ...song.contributors.all,
    ]) {
      final normalized = _normalizeText(artist.title);
      if (normalized.isNotEmpty) names.add(normalized);
    }

    for (final raw in song.primaryArtists.split(',')) {
      final normalized = _normalizeText(raw);
      if (normalized.isNotEmpty) names.add(normalized);
    }

    return names;
  }

  Set<String> _normalizedWords(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .map((token) => token.trim())
        .where((token) => token.length >= 3)
        .toSet();
  }

  String _normalizeText(String value) => value.trim().toLowerCase();

  Future<void> _updatePlaybackState(PlayerState ps) async {
    final hasMedia = mediaItem.value != null;
    final position = _player.position;

    final processingState =
        {
          ProcessingState.idle:
              hasMedia ? AudioProcessingState.ready : AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[ps.processingState]!;

    playbackState.add(
      playbackState.value.copyWith(
        playing: ps.playing,
        processingState: processingState,
        updatePosition: position,
        bufferedPosition: _player.bufferedPosition,
        controls: [
          MediaControl.skipToPrevious,
          ps.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 3],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        queueIndex: _currentIndex,
        speed: _player.speed,
      ),
    );
  }

  Future<void> _initLastPlayed() async {
    debugPrint('--> Initializing last played queue...');
    final lastQueueData = await LastQueueStorage.load();

    // 🔹 Reset shuffle manager properly (instead of _shuffle = false)
    _shuffleManager.loadQueue([]);
    ref.read(shuffleProvider.notifier).state = false;
    debugPrint('--> ShuffleManager reset to non-shuffling mode');

    if (lastQueueData != null) {
      final songs = lastQueueData.songs;
      final startIndex = lastQueueData.currentIndex;
      _queueSourceId = 'Last played';
      _queueSourceName = 'Last Played';

      if (songs.isNotEmpty) {
        debugPrint('--> Restoring queue: $lastQueueData');
        _queue = List.from(songs);
        _currentIndex = startIndex.clamp(0, _queue.length - 1);

        // 🔹 Sync with ShuffleManager (non-shuffling on restore)
        _shuffleManager.loadQueue(_queue, currentIndex: _currentIndex);

        queue.add(_queue.map(songToMediaItem).toList());
        await LastQueueStorage.save(_queue, currentIndex: _currentIndex);

        final current = _queue[_currentIndex];
        ref.read(currentSongProvider.notifier).state = current;

        try {
          final sources =
              _queue.map((s) {
                final local = offlineManager.getLocalPath(s.id);
                final uri =
                    (local != null && File(local).existsSync())
                        ? Uri.file(local)
                        : Uri.parse(_preferredStreamSource(s).url);
                return AudioSource.uri(uri, tag: songToMediaItem(s));
              }).toList();

          await _player.setAudioSources(
            sources,
            initialIndex: _currentIndex,
            initialPosition: Duration.zero,
          );

          mediaItem.add(songToMediaItem(current));

          final dominant = await getDominantColorFromImage(
            current.images.last.url,
          );
          ref.read(playerColourProvider.notifier).state = getDominantDarker(
            dominant,
          );

          debugPrint('--> Last played queue restored (not autoplaying).');
        } catch (e, st) {
          debugPrint('--> initLastPlayed (queue) error: $e\n$st');
        }

        return;
      }
    }

    // 🔹 fallback: restore single last played song if full queue not found
    final last = await LastPlayedSongStorage.load();
    if (last != null) {
      _queue = [last];
      _currentIndex = 0;

      // 🔹 Sync with ShuffleManager
      _shuffleManager.loadQueue(_queue, currentIndex: _currentIndex);

      queue.add([songToMediaItem(last)]);
      _queueSourceName = 'Last Played';
      _queueSourceId = last.id;
      ref.read(currentSongProvider.notifier).state = last;

      try {
        final localPath = offlineManager.getLocalPath(last.id);
        final uri =
            (localPath != null && File(localPath).existsSync())
                ? Uri.file(localPath)
                : Uri.parse(_preferredStreamSource(last).url);

        await _player.setAudioSource(
          AudioSource.uri(uri, tag: songToMediaItem(last)),
        );

        mediaItem.add(songToMediaItem(last));

        final dominant = await getDominantColorFromImage(last.images.last.url);
        ref.read(playerColourProvider.notifier).state = getDominantDarker(
          dominant,
        );

        debugPrint('--> Fallback single last-played loaded (not autoplaying).');
      } catch (e, st) {
        debugPrint('--> initLastPlayed (single) error: $e\n$st');
      }
    }
  }
}

MediaItem songToMediaItem(SongDetail song) {
  return MediaItem(
    id: song.id,
    title: song.title.isNotEmpty ? song.title : 'Unknown',
    album: song.albumName ?? song.album,
    artist:
        song.primaryArtists.isNotEmpty
            ? song.primaryArtists
            : (song.contributors.primary.isNotEmpty
                ? song.contributors.primary.map((a) => a.title).join(", ")
                : 'Unknown'),
    genre: song.albumName ?? song.album,
    duration:
        song.duration != null
            ? Duration(seconds: int.tryParse(song.duration!) ?? 0)
            : null,
    artUri:
        (song.images.isNotEmpty && song.images.last.url.isNotEmpty)
            ? Uri.tryParse(song.images.last.url)
            : null,
    artHeaders: {},
    displayTitle: song.title.isNotEmpty ? song.title : 'Unknown',
    displaySubtitle: song.albumName ?? song.album,
    displayDescription: song.description,
    extras: {
      'explicit': song.explicitContent.toString(),
      'language': song.language,
      'label': song.label ?? '',
      'year': song.year?.toString() ?? '',
      'releaseDate': song.releaseDate ?? '',
      'contributors_primary':
          song.contributors.primary.map((a) => a.title).toList(),
      'contributors_featured':
          song.contributors.featured.map((a) => a.title).toList(),
      'contributors_all': song.contributors.all.map((a) => a.title).toList(),
      'downloadUrls':
          song.downloadUrls
              .map((d) => {'url': d.url, 'quality': d.quality})
              .toList(),
    },
  );
}
