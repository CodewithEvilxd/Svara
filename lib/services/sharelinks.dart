import '../models/datamodel.dart';
import '../shared/constants.dart';

enum SharedContentType { song, album, playlist, artist }

class SharedContentPayload {
  final SharedContentType type;
  final String id;
  final String url;

  const SharedContentPayload({
    required this.type,
    this.id = '',
    this.url = '',
  });
}

String normalizeShareableUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) {
    return 'https://www.jiosaavn.com$trimmed';
  }
  return 'https://www.jiosaavn.com/$trimmed';
}

Uri buildContentShareUri(SongMediaItem item) {
  return Uri(
    scheme: appDeepLinkScheme,
    host: 'share',
    queryParameters: {
      'type': _typeForItem(item).name,
      'id': item.id,
      if (item.url.trim().isNotEmpty) 'url': normalizeShareableUrl(item.url),
    },
  );
}

SharedContentPayload? parseSharedContentUri(Uri uri) {
  if (uri.scheme == appDeepLinkScheme && uri.host == 'share') {
    final type = _parseType(uri.queryParameters['type']);
    if (type == null) return null;
    return SharedContentPayload(
      type: type,
      id: (uri.queryParameters['id'] ?? '').trim(),
      url: normalizeShareableUrl(uri.queryParameters['url'] ?? ''),
    );
  }

  if ((uri.scheme == 'http' || uri.scheme == 'https') &&
      (uri.host == 'www.jiosaavn.com' || uri.host == 'jiosaavn.com')) {
    final type = _typeFromPath(uri.pathSegments);
    if (type == null) return null;
    return SharedContentPayload(type: type, url: normalizeShareableUrl(uri.toString()));
  }

  return null;
}

SharedContentType _typeForItem(SongMediaItem item) {
  if (item is SongDetail || item is Song) return SharedContentType.song;
  if (item is Album) return SharedContentType.album;
  if (item is Playlist) return SharedContentType.playlist;
  return SharedContentType.artist;
}

SharedContentType? _parseType(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'song':
      return SharedContentType.song;
    case 'album':
      return SharedContentType.album;
    case 'playlist':
      return SharedContentType.playlist;
    case 'artist':
      return SharedContentType.artist;
    default:
      return null;
  }
}

SharedContentType? _typeFromPath(List<String> segments) {
  for (final segment in segments) {
    final normalized = segment.trim().toLowerCase();
    switch (normalized) {
      case 'song':
        return SharedContentType.song;
      case 'album':
        return SharedContentType.album;
      case 'playlist':
      case 'featured':
        return SharedContentType.playlist;
      case 'artist':
        return SharedContentType.artist;
    }
  }
  return null;
}
