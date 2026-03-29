import 'package:flutter_test/flutter_test.dart';
import 'package:svara/models/datamodel.dart';
import 'package:svara/services/jamlink.dart';

SongDetail _song({
  required String id,
  required String title,
  String artist = 'Artist',
}) {
  return SongDetail(
    id: id,
    title: title,
    album: 'Album',
    url: 'https://example.com/$id',
    type: 'song',
    primaryArtists: artist,
    singers: artist,
    language: 'hindi',
    year: '2024',
    duration: '180',
    images: const [],
    downloadUrls: const [],
    contributors: Contributors(
      primary: [
        Artist(
          id: 'artist-$id',
          title: artist,
          type: 'artist',
          url: 'https://example.com/artist/$id',
          images: const [],
        ),
      ],
      all: [
        Artist(
          id: 'artist-$id',
          title: artist,
          type: 'artist',
          url: 'https://example.com/artist/$id',
          images: const [],
        ),
      ],
    ),
  );
}

void main() {
  group('JamLinkService', () {
    test('builds and parses a jam link round-trip', () {
      final service = JamLinkService();
      final queue = [
        _song(id: '1', title: 'First'),
        _song(id: '2', title: 'Second'),
        _song(id: '3', title: 'Third'),
      ];

      final uri = service.buildJamUri(
        queue: queue,
        currentIndex: 1,
        position: const Duration(seconds: 42),
        sourceName: 'Test Mix',
      );

      final parsed = service.parse(uri);

      expect(parsed, isNotNull);
      expect(parsed!.songId, '2');
      expect(parsed.queueIds, ['1', '2', '3']);
      expect(parsed.startIndex, 1);
      expect(parsed.positionMs, 42000);
      expect(parsed.sourceName, 'Test Mix');
    });

    test('returns null for non-jam deep links', () {
      final service = JamLinkService();

      expect(service.parse(Uri.parse('https://example.com')), isNull);
      expect(service.parse(Uri.parse('svara://search?query=dil')), isNull);
    });
  });
}
