import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/datamodel.dart';

class LyricsLine {
  final Duration timestamp;
  final String text;

  const LyricsLine({required this.timestamp, required this.text});
}

class LyricsResult {
  final String plainLyrics;
  final List<LyricsLine> syncedLyrics;
  final bool instrumental;

  const LyricsResult({
    required this.plainLyrics,
    this.syncedLyrics = const [],
    this.instrumental = false,
  });

  bool get hasSyncedLyrics => syncedLyrics.isNotEmpty;
  bool get hasPlainLyrics => plainLyrics.trim().isNotEmpty;
}

class LyricsService {
  static const _host = 'lrclib.net';
  static const _path = '/api/get';
  static final _lyricsLinePattern = RegExp(
    r'^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$',
  );

  Future<LyricsResult?> fetchLyrics(SongDetail song) async {
    final artistName = _resolveArtistName(song);
    if (song.title.trim().isEmpty || artistName.isEmpty) return null;

    final durationSeconds = int.tryParse(song.duration ?? '');
    final albumName = (song.albumName ?? song.album).trim();

    final titleCandidates = <String>{
      song.title.trim(),
      _normalizeSongTitle(song.title),
    }.where((value) => value.isNotEmpty);

    for (final title in titleCandidates) {
      final uri = Uri.https(_host, _path, {
        'track_name': title,
        'artist_name': artistName,
        'album_name': albumName,
        if (durationSeconds != null && durationSeconds > 0)
          'duration': durationSeconds.toString(),
      });

      try {
        final response = await http.get(
          uri,
          headers: const {'Accept': 'application/json'},
        );

        if (response.statusCode == 404) {
          continue;
        }

        if (response.statusCode != 200) {
          return null;
        }

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final plainLyrics = (body['plainLyrics'] ?? '').toString().trim();
        final syncedLyricsRaw = (body['syncedLyrics'] ?? '').toString().trim();
        final instrumental = body['instrumental'] == true;

        return LyricsResult(
          plainLyrics: plainLyrics,
          syncedLyrics: _parseSyncedLyrics(syncedLyricsRaw),
          instrumental: instrumental,
        );
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  List<LyricsLine> _parseSyncedLyrics(String rawLyrics) {
    if (rawLyrics.isEmpty) return const [];

    final lines = <LyricsLine>[];
    for (final line in rawLyrics.split('\n')) {
      final match = _lyricsLinePattern.firstMatch(line.trim());
      if (match == null) continue;

      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = double.tryParse(match.group(2) ?? '') ?? 0;
      final lyricText = (match.group(3) ?? '').trim();
      if (lyricText.isEmpty) continue;

      final totalMilliseconds = ((minutes * 60) + seconds) * 1000;
      lines.add(
        LyricsLine(
          timestamp: Duration(milliseconds: totalMilliseconds.round()),
          text: lyricText,
        ),
      );
    }
    return lines;
  }

  String _resolveArtistName(SongDetail song) {
    if (song.contributors.primary.isNotEmpty) {
      return song.contributors.primary.first.title.trim();
    }
    if (song.contributors.all.isNotEmpty) {
      return song.contributors.all.first.title.trim();
    }
    return song.primaryArtists
        .split(',')
        .map((part) => part.trim())
        .firstWhere((part) => part.isNotEmpty, orElse: () => '');
  }

  String _normalizeSongTitle(String title) {
    final withoutParens = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
    return withoutParens.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
