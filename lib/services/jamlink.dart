import 'dart:math' as math;

import '../models/datamodel.dart';
import '../shared/constants.dart';

class JamLinkPayload {
  final String songId;
  final List<String> queueIds;
  final int startIndex;
  final int positionMs;
  final String sourceName;
  final String hostName;

  const JamLinkPayload({
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
    if (uri.scheme != appDeepLinkScheme || uri.host != _host) return null;

    final songId = (uri.queryParameters['songId'] ?? '').trim();
    final queueIds =
        (uri.queryParameters['queue'] ?? '')
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();

    if (songId.isEmpty && queueIds.isEmpty) return null;

    return JamLinkPayload(
      songId: songId,
      queueIds: queueIds,
      startIndex: int.tryParse(uri.queryParameters['index'] ?? '') ?? 0,
      positionMs: int.tryParse(uri.queryParameters['positionMs'] ?? '') ?? 0,
      sourceName: (uri.queryParameters['source'] ?? '').trim(),
      hostName: (uri.queryParameters['hostName'] ?? '').trim(),
    );
  }
}
