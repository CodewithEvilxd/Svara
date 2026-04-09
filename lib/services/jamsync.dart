import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/datamodel.dart';
import '../shared/constants.dart';

final jamSessionProvider = StateProvider<JamSessionState>(
  (ref) => const JamSessionState(),
);

final jamServiceProvider = Provider<JamSyncService>((ref) {
  final service = JamSyncService(ref);
  ref.onDispose(service.dispose);
  return service;
});

class JamParticipant {
  final String memberId;
  final String displayName;
  final bool isHost;

  const JamParticipant({
    required this.memberId,
    required this.displayName,
    this.isHost = false,
  });
}

class JamSessionState {
  final bool isActive;
  final bool isHost;
  final String sessionId;
  final String shareCode;
  final String sourceName;
  final String hostName;
  final String errorMessage;
  final List<JamParticipant> participants;

  const JamSessionState({
    this.isActive = false,
    this.isHost = false,
    this.sessionId = '',
    this.shareCode = '',
    this.sourceName = '',
    this.hostName = '',
    this.errorMessage = '',
    this.participants = const [],
  });

  int get participantCount => participants.length;

  JamSessionState copyWith({
    bool? isActive,
    bool? isHost,
    String? sessionId,
    String? shareCode,
    String? sourceName,
    String? hostName,
    String? errorMessage,
    List<JamParticipant>? participants,
  }) {
    return JamSessionState(
      isActive: isActive ?? this.isActive,
      isHost: isHost ?? this.isHost,
      sessionId: sessionId ?? this.sessionId,
      shareCode: shareCode ?? this.shareCode,
      sourceName: sourceName ?? this.sourceName,
      hostName: hostName ?? this.hostName,
      errorMessage: errorMessage ?? this.errorMessage,
      participants: participants ?? this.participants,
    );
  }
}

class JamSyncSnapshot {
  final String sessionId;
  final String senderId;
  final String sourceName;
  final String hostName;
  final List<SongDetail> queue;
  final int currentIndex;
  final int positionMs;
  final bool isPlaying;
  final int sentAtMs;

  const JamSyncSnapshot({
    this.sessionId = '',
    this.senderId = '',
    this.sourceName = '',
    this.hostName = '',
    this.queue = const [],
    this.currentIndex = 0,
    this.positionMs = 0,
    this.isPlaying = false,
    this.sentAtMs = 0,
  });

  JamSyncSnapshot copyWith({
    String? sessionId,
    String? senderId,
    String? sourceName,
    String? hostName,
    List<SongDetail>? queue,
    int? currentIndex,
    int? positionMs,
    bool? isPlaying,
    int? sentAtMs,
  }) {
    return JamSyncSnapshot(
      sessionId: sessionId ?? this.sessionId,
      senderId: senderId ?? this.senderId,
      sourceName: sourceName ?? this.sourceName,
      hostName: hostName ?? this.hostName,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      positionMs: positionMs ?? this.positionMs,
      isPlaying: isPlaying ?? this.isPlaying,
      sentAtMs: sentAtMs ?? this.sentAtMs,
    );
  }

  int get effectivePositionMs {
    if (!isPlaying) return math.max(0, positionMs);
    final delta = DateTime.now().millisecondsSinceEpoch - sentAtMs;
    return math.max(0, positionMs + delta);
  }

  Map<String, dynamic> toMap({String? targetMemberId}) {
    return {
      'sessionId': sessionId,
      'senderId': senderId,
      'sourceName': sourceName,
      'hostName': hostName,
      'currentIndex': currentIndex,
      'positionMs': positionMs,
      'isPlaying': isPlaying,
      'sentAtMs': sentAtMs,
      'queue': queue.map(SongDetail.songDetailToJson).toList(),
      if ((targetMemberId ?? '').isNotEmpty) 'targetMemberId': targetMemberId,
    };
  }

  factory JamSyncSnapshot.fromMap(Map<String, dynamic> map) {
    final rawQueue = (map['queue'] as List<dynamic>? ?? const []);
    final parsedQueue =
        rawQueue
            .whereType<Map>()
            .map(
              (item) => SongDetail.fromJson(
                Map<String, dynamic>.from(item.cast<String, dynamic>()),
              ),
            )
            .toList();

    return JamSyncSnapshot(
      sessionId: (map['sessionId'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      sourceName: (map['sourceName'] ?? '').toString(),
      hostName: (map['hostName'] ?? '').toString(),
      currentIndex: int.tryParse('${map['currentIndex'] ?? 0}') ?? 0,
      positionMs: int.tryParse('${map['positionMs'] ?? 0}') ?? 0,
      isPlaying: map['isPlaying'] == true,
      sentAtMs: int.tryParse('${map['sentAtMs'] ?? 0}') ?? 0,
      queue: parsedQueue,
    );
  }
}

class JamControlRequest {
  final String sessionId;
  final String senderId;
  final String action;
  final int? positionMs;
  final int? queueIndex;
  final int sentAtMs;

  const JamControlRequest({
    this.sessionId = '',
    this.senderId = '',
    this.action = '',
    this.positionMs,
    this.queueIndex,
    this.sentAtMs = 0,
  });

  factory JamControlRequest.fromMap(Map<String, dynamic> map) {
    final rawPosition = map['positionMs'];
    final rawQueueIndex = map['queueIndex'];
    return JamControlRequest(
      sessionId: (map['sessionId'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      action: (map['action'] ?? '').toString().trim().toLowerCase(),
      positionMs:
          rawPosition == null ? null : int.tryParse(rawPosition.toString()),
      queueIndex:
          rawQueueIndex == null
              ? null
              : int.tryParse(rawQueueIndex.toString()),
      sentAtMs: int.tryParse('${map['sentAtMs'] ?? 0}') ?? 0,
    );
  }
}

class JamSyncService {
  static const _memberIdKey = 'jam_member_id';

  JamSyncService(this._ref);

  final Ref _ref;
  final math.Random _random = math.Random();

  RealtimeChannel? _channel;
  Timer? _syncDebounce;
  String _memberId = '';
  String _sessionId = '';
  String _sourceName = '';
  bool _isHost = false;
  bool _initialSnapshotReceived = false;
  Future<JamSyncSnapshot?> Function()? _snapshotBuilder;
  Future<void> Function(JamSyncSnapshot snapshot)? _remoteApplier;
  Future<void> Function(JamControlRequest request)? _controlRequestHandler;

  bool get isActive => _sessionId.isNotEmpty && _channel != null;
  bool get isHostSession => _isHost;

  void attachPlaybackBridge({
    required Future<JamSyncSnapshot?> Function() snapshotBuilder,
    required Future<void> Function(JamSyncSnapshot snapshot) remoteApplier,
    required Future<void> Function(JamControlRequest request) controlRequestHandler,
  }) {
    _snapshotBuilder = snapshotBuilder;
    _remoteApplier = remoteApplier;
    _controlRequestHandler = controlRequestHandler;
  }

  Future<void> ensureMemberId() async {
    if (_memberId.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_memberIdKey);
    if (cached != null && cached.trim().isNotEmpty) {
      _memberId = cached.trim();
      return;
    }

    final generated =
        '${DateTime.now().millisecondsSinceEpoch}${_random.nextInt(999999).toString().padLeft(6, '0')}';
    _memberId = generated;
    await prefs.setString(_memberIdKey, generated);
  }

  Future<String> startSession({String? sourceName}) async {
    await ensureMemberId();
    if (isActive && _isHost) {
      _sourceName = sourceName ?? _sourceName;
      await syncFromPlayback(force: true);
      return _sessionId;
    }

    await leaveSession();

    final sessionId = _generateSessionId();
    _sessionId = sessionId;
    _sourceName = sourceName ?? 'Jam Session';
    _isHost = true;
    _initialSnapshotReceived = true;

    await _subscribeToSession(sessionId);
    await syncFromPlayback(force: true);
    return sessionId;
  }

  Future<void> joinSession(String sessionIdOrCode) async {
    final normalizedSessionId = _normalizeSessionId(sessionIdOrCode);
    if (normalizedSessionId.isEmpty) return;

    await ensureMemberId();
    if (isActive && _sessionId == normalizedSessionId) return;

    await leaveSession();

    _sessionId = normalizedSessionId;
    _sourceName = 'Jam Session';
    _isHost = false;
    _initialSnapshotReceived = false;

    await _subscribeToSession(_sessionId);
  }

  Future<void> leaveSession() async {
    _syncDebounce?.cancel();
    _syncDebounce = null;

    final channel = _channel;
    _channel = null;

    if (channel != null) {
      try {
        await channel.untrack();
      } catch (_) {}
      await Supabase.instance.client.removeChannel(channel);
    }

    _sessionId = '';
    _sourceName = '';
    _isHost = false;
    _initialSnapshotReceived = false;

    _setState(const JamSessionState());
  }

  void dispose() {
    unawaited(leaveSession());
  }

  Future<void> syncFromPlayback({bool force = false}) async {
    if (!isActive) return;
    if (!_isHost) return;
    if (force) {
      await _broadcastCurrentSnapshot();
      return;
    }

    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_broadcastCurrentSnapshot());
    });
  }

  Future<void> sendControlRequest(
    String action, {
    int? positionMs,
    int? queueIndex,
  }) async {
    final channel = _channel;
    final normalizedAction = action.trim().toLowerCase();
    if (channel == null || normalizedAction.isEmpty || !isActive) return;

    await channel.sendBroadcastMessage(
      event: 'control_request',
      payload: {
        'sessionId': _sessionId,
        'senderId': _memberId,
        'action': normalizedAction,
        if (positionMs != null) 'positionMs': positionMs,
        if (queueIndex != null) 'queueIndex': queueIndex,
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> _subscribeToSession(String sessionId) async {
    final channel = Supabase.instance.client.channel('jam:$sessionId');

    channel.onBroadcast(
      event: 'request_state',
      callback: (payload) {
        unawaited(_handleStateRequest(_toMap(payload)));
      },
    );
    channel.onBroadcast(
      event: 'session_state',
      callback: (payload) {
        unawaited(_handleSessionState(_toMap(payload)));
      },
    );
    channel.onBroadcast(
      event: 'control_request',
      callback: (payload) {
        unawaited(_handleControlRequest(_toMap(payload)));
      },
    );
    channel.onPresenceSync((_) => _refreshParticipants());
    channel.onPresenceJoin((_) => _refreshParticipants());
    channel.onPresenceLeave((_) => _refreshParticipants());

    _channel = channel;

    final subscribed = Completer<void>();
    channel.subscribe((status, error) async {
      debugPrint('[Jam] subscribe status: $status error: $error');

      if (status == RealtimeSubscribeStatus.subscribed &&
          !subscribed.isCompleted) {
        await channel.track(_presencePayload());
        _refreshParticipants();
        subscribed.complete();

        if (_isHost) {
          await _broadcastCurrentSnapshot();
        } else {
          await _requestCurrentSnapshot();
        }
        return;
      }

      if ((status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) &&
          !subscribed.isCompleted) {
        subscribed.completeError(
          StateError((error ?? 'Unable to connect to Jam channel').toString()),
        );
      }
    });

    await subscribed.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _requestCurrentSnapshot() async {
    final channel = _channel;
    if (channel == null) return;

    await channel.sendBroadcastMessage(
      event: 'request_state',
      payload: {'targetMemberId': _memberId},
    );
  }

  Future<void> _handleStateRequest(Map<String, dynamic> payload) async {
    final targetMemberId = (payload['targetMemberId'] ?? '').toString();
    if (targetMemberId.isEmpty || targetMemberId == _memberId) return;
    if (!_shouldReplyWithSnapshot) return;

    await _broadcastCurrentSnapshot(targetMemberId: targetMemberId);
  }

  Future<void> _handleSessionState(Map<String, dynamic> payload) async {
    final targetMemberId = (payload['targetMemberId'] ?? '').toString();
    if (targetMemberId.isNotEmpty && targetMemberId != _memberId) return;

    final snapshot = JamSyncSnapshot.fromMap(payload);
    if (snapshot.senderId == _memberId || snapshot.queue.isEmpty) return;

    _initialSnapshotReceived = true;
    _sourceName = snapshot.sourceName;
    _setState(
      _ref.read(jamSessionProvider).copyWith(
        isActive: true,
        isHost: _isHost,
        sessionId: _sessionId,
        shareCode: _shareCodeFor(_sessionId),
        sourceName: snapshot.sourceName,
        hostName: snapshot.hostName,
        errorMessage: '',
      ),
    );

    final applier = _remoteApplier;
    if (applier != null) {
      await applier(snapshot);
    }
  }

  Future<void> _handleControlRequest(Map<String, dynamic> payload) async {
    final request = JamControlRequest.fromMap(payload);
    final handler = _controlRequestHandler;
    if (!_isHost ||
        handler == null ||
        request.senderId == _memberId ||
        request.action.isEmpty) {
      return;
    }

    await handler(request);
  }

  Future<void> _broadcastCurrentSnapshot({String? targetMemberId}) async {
    final channel = _channel;
    final builder = _snapshotBuilder;
    if (channel == null || builder == null) return;

    final snapshot = await builder();
    if (snapshot == null || snapshot.queue.isEmpty) return;

    final outgoing = snapshot.copyWith(
      sessionId: _sessionId,
      senderId: _memberId,
      sourceName: snapshot.sourceName.isNotEmpty ? snapshot.sourceName : _sourceName,
      hostName: username.trim().isNotEmpty ? username.trim() : defaultUsername,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    _sourceName = outgoing.sourceName;
    _setState(
      _ref.read(jamSessionProvider).copyWith(
        isActive: true,
        isHost: _isHost,
        sessionId: _sessionId,
        shareCode: _shareCodeFor(_sessionId),
        sourceName: outgoing.sourceName,
        hostName: outgoing.hostName,
        errorMessage: '',
      ),
    );

    await channel.sendBroadcastMessage(
      event: 'session_state',
      payload: outgoing.toMap(targetMemberId: targetMemberId),
    );
  }

  void _refreshParticipants() {
    final channel = _channel;
    if (channel == null) return;

    final state = channel.presenceState();
    final participants = <JamParticipant>[];

    for (final entry in state) {
      for (final presence in entry.presences) {
        final payload = _presencePayloadMap(presence);
        participants.add(
          JamParticipant(
            memberId:
                (payload['memberId'] ?? entry.key).toString().trim().isEmpty
                    ? entry.key
                    : (payload['memberId'] ?? entry.key).toString(),
            displayName:
                (payload['name'] ?? defaultUsername).toString().trim().isEmpty
                    ? defaultUsername
                    : (payload['name'] ?? defaultUsername).toString(),
            isHost: payload['isHost'] == true,
          ),
        );
      }
    }

    participants.sort((a, b) {
      if (a.isHost == b.isHost) {
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      }
      return a.isHost ? -1 : 1;
    });

    _setState(
      _ref.read(jamSessionProvider).copyWith(
        isActive: isActive,
        isHost: _isHost,
        sessionId: _sessionId,
        shareCode: _shareCodeFor(_sessionId),
        sourceName: _sourceName,
        hostName: _hostDisplayName(participants),
        participants: participants,
        errorMessage: '',
      ),
    );

    if (!_initialSnapshotReceived && !_isHost && participants.isNotEmpty) {
      unawaited(_requestCurrentSnapshot());
    }
  }

  bool get _shouldReplyWithSnapshot {
    final state = _ref.read(jamSessionProvider);
    final hasHost = state.participants.any((participant) => participant.isHost);
    return _isHost || !hasHost;
  }

  Map<String, dynamic> _presencePayload() => {
    'memberId': _memberId,
    'name': username.trim().isNotEmpty ? username.trim() : defaultUsername,
    'isHost': _isHost,
    'joinedAt': DateTime.now().toIso8601String(),
  };

  Map<String, dynamic> _presencePayloadMap(Presence presence) {
    return Map<String, dynamic>.from(presence.payload);
  }

  Map<String, dynamic> _toMap(Map payload) {
    return Map<String, dynamic>.from(payload.cast<String, dynamic>());
  }

  String _generateSessionId() {
    final code = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'jam-$code';
  }

  String _normalizeSessionId(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return '';

    final lowerTrimmed = trimmed.toLowerCase();
    if (lowerTrimmed.startsWith('jam-')) {
      final remainder =
          trimmed.substring(4).replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
      if (remainder.isEmpty) return '';
      return 'jam-${remainder.toLowerCase()}';
    }

    final shareCode = _normalizeShareCode(trimmed);
    if (shareCode.isEmpty) return '';
    return 'jam-${shareCode.toLowerCase()}';
  }

  String _normalizeShareCode(String rawValue) {
    final compact =
        rawValue.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    if (compact.isEmpty) return '';
    if (compact.length <= 6) return compact;
    return compact.substring(compact.length - 6);
  }

  String _shareCodeFor(String sessionId) {
    if (sessionId.trim().isEmpty) return '';
    final normalizedSessionId = _normalizeSessionId(sessionId);
    if (normalizedSessionId.startsWith('jam-')) {
      final remainder = normalizedSessionId.substring(4);
      if (RegExp(r'^[a-z0-9]{1,6}$').hasMatch(remainder)) {
        return remainder.toUpperCase();
      }
      final lastSegment = remainder.split('-').last;
      if (lastSegment.isNotEmpty) {
        return _normalizeShareCode(lastSegment);
      }
    }

    return _normalizeShareCode(sessionId);
  }

  String _hostDisplayName(List<JamParticipant> participants) {
    for (final participant in participants) {
      if (participant.isHost) {
        return participant.displayName;
      }
    }
    return '';
  }

  void _setState(JamSessionState state) {
    _ref.read(jamSessionProvider.notifier).state = state;
  }
}
