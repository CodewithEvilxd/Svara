import 'dart:math' as math;

import '../models/datamodel.dart';
import '../shared/constants.dart';

class JamLinkPayload {
  final String sessionId;
  final String songId;
  final List<String> queueIds;
  final int startIndex;
  final int positionMs;
  final String sourceName;
  final String hostName;

  const JamLinkPayload({
    this.sessionId = '',
    required this.songId,
    this.queueIds = const [],
    this.startIndex = 0,
    this.positionMs = 0,
    this.sourceName = '',
    this.hostName = '',
  });
}

class JamLinkService {
  static const _host = 'jam';
  static const _inviteHosts = {jamInviteHost, 'www.nishantdev.space'};

  Uri buildSessionUri({
    required String sessionId,
    String? shareCode,
    String? sourceName,
    String? hostName,
  }) {
    return Uri(
      scheme: appDeepLinkScheme,
      host: _host,
      queryParameters: {
        'session': sessionId,
        if ((shareCode ?? '').trim().isNotEmpty) 'code': shareCode!.trim(),
        if ((sourceName ?? '').trim().isNotEmpty) 'source': sourceName!.trim(),
        if ((hostName ?? '').trim().isNotEmpty) 'hostName': hostName!.trim(),
      },
    );
  }

  Uri buildInviteUrl({
    required String sessionId,
    required String shareCode,
    String? sourceName,
    String? hostName,
  }) {
    return Uri.https(jamInviteHost, '$jamInvitePathPrefix/${shareCode.trim()}', {
      'session': sessionId,
      'code': shareCode.trim(),
      if ((sourceName ?? '').trim().isNotEmpty) 'source': sourceName!.trim(),
      if ((hostName ?? '').trim().isNotEmpty) 'hostName': hostName!.trim(),
    });
  }

  Uri buildJamUri({
    required List<SongDetail> queue,
    required int currentIndex,
    required Duration position,
    String? sourceName,
  }) {
    final maxIndex = math.max(queue.length - 1, 0).toInt();
    final normalizedIndex = currentIndex.clamp(0, maxIndex).toInt();
    final windowStart = math.max(0, normalizedIndex - 4).toInt();
    final windowEnd = math.min(queue.length, normalizedIndex + 12).toInt();
    final sharedQueue = queue.sublist(windowStart, windowEnd);
    final sharedIndex = normalizedIndex - windowStart;
    final currentSong = queue.isNotEmpty ? queue[normalizedIndex] : null;

    return Uri(
      scheme: appDeepLinkScheme,
      host: _host,
      queryParameters: {
        'songId': currentSong?.id ?? '',
        if (sharedQueue.isNotEmpty)
          'queue': sharedQueue.map((song) => song.id).join(','),
        'index': sharedIndex.toString(),
        'positionMs': position.inMilliseconds.toString(),
        if ((sourceName ?? '').trim().isNotEmpty) 'source': sourceName!.trim(),
        if (username.trim().isNotEmpty) 'hostName': username.trim(),
      },
    );
  }

  JamLinkPayload? parse(Uri uri) {
    if (!_isSupportedJamUri(uri)) return null;

    final sessionId = _resolveSessionId(uri);
    final songId = (uri.queryParameters['songId'] ?? '').trim();
    final queueIds =
        (uri.queryParameters['queue'] ?? '')
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();

    if (sessionId.isEmpty && songId.isEmpty && queueIds.isEmpty) return null;

    return JamLinkPayload(
      sessionId: sessionId,
      songId: songId,
      queueIds: queueIds,
      startIndex: int.tryParse(uri.queryParameters['index'] ?? '') ?? 0,
      positionMs: int.tryParse(uri.queryParameters['positionMs'] ?? '') ?? 0,
      sourceName: (uri.queryParameters['source'] ?? '').trim(),
      hostName: (uri.queryParameters['hostName'] ?? '').trim(),
    );
  }

  bool _isSupportedJamUri(Uri uri) {
    if (uri.scheme == appDeepLinkScheme && uri.host == _host) {
      return true;
    }

    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        _inviteHosts.contains(uri.host.toLowerCase())) {
      final segments =
          uri.pathSegments
              .map((segment) => segment.trim().toLowerCase())
              .where((segment) => segment.isNotEmpty)
              .toList();
      return segments.length >= 2 &&
          segments[0] == 'svara' &&
          segments[1] == 'jam';
    }

    return false;
  }

  String _resolveSessionId(Uri uri) {
    final sessionId = (uri.queryParameters['session'] ?? '').trim();
    if (sessionId.isNotEmpty) {
      return sessionId;
    }

    final code =
        (uri.queryParameters['code'] ?? _pathCode(uri)).trim().toUpperCase();
    if (code.isEmpty) {
      return '';
    }
    return 'jam-${code.toLowerCase()}';
  }

  String _pathCode(Uri uri) {
    final segments =
        uri.pathSegments
            .map((segment) => segment.trim())
            .where((segment) => segment.isNotEmpty)
            .toList();
    if (segments.length < 3) {
      return '';
    }
    return segments.last;
  }
}
