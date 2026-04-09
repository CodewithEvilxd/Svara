import 'package:flutter_test/flutter_test.dart';
import 'package:svara/models/datamodel.dart';
import 'package:svara/services/sharelinks.dart';

SongDetail _song() => SongDetail(
  id: 'aRZbUYD7',
  title: 'Tum Hi Ho',
  type: 'song',
  url: 'https://www.jiosaavn.com/song/tum-hi-ho/EToxUyFpcwQ',
  images: const [],
  album: 'Aashiqui 2',
);

void main() {
  test('normalizes relative JioSaavn URLs', () {
    expect(
      normalizeShareableUrl('/song/tum-hi-ho/EToxUyFpcwQ'),
      'https://www.jiosaavn.com/song/tum-hi-ho/EToxUyFpcwQ',
    );
  });

  test('builds app share uri for songs', () {
    final uri = buildContentShareUri(_song());

    expect(uri.scheme, 'svara');
    expect(uri.host, 'share');
    expect(uri.queryParameters['type'], 'song');
    expect(uri.queryParameters['id'], 'aRZbUYD7');
  });

  test('parses jiosaavn song links as shared content', () {
    final payload = parseSharedContentUri(
      Uri.parse('https://www.jiosaavn.com/song/tum-hi-ho/EToxUyFpcwQ'),
    );

    expect(payload, isNotNull);
    expect(payload!.type, SharedContentType.song);
    expect(payload.url, 'https://www.jiosaavn.com/song/tum-hi-ho/EToxUyFpcwQ');
  });
}
