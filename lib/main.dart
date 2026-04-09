import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:page_transition/page_transition.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toastification/toastification.dart';

import 'screens/home.dart';
import 'screens/library.dart';
import 'screens/search.dart';
import 'services/jiosaavn.dart';
import 'services/jamlink.dart';
import 'services/jamsync.dart';
import 'services/sharelinks.dart';
import 'services/systemconfig.dart';
import 'services/audiohandler.dart';
import 'services/localnotification.dart';
import 'shared/constants.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.init();
  packageInfo = await PackageInfo.fromPlatform();

  await initNotifications();
  await SystemUiConfigurator.configure();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabasePublishableKey,
  );

  runApp(ToastificationWrapper(child: ProviderScope(child: const MyApp())));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  final AppLinks _appLinks = AppLinks();
  final JamLinkService _jamLinkService = JamLinkService();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final initialUri = await _appLinks.getInitialLink();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('onAppLink: $uri');
      unawaited(_handleIncomingUri(uri));
    });

    await ref.read(audioHandlerProvider.future);
    ref.read(jamServiceProvider);
    await saavn.initBaseUrl();

    if (initialUri != null) {
      unawaited(_handleIncomingUri(initialUri));
    }
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    final jamPayload = _jamLinkService.parse(uri);
    if (jamPayload != null && jamPayload.sessionId.isNotEmpty) {
      await ref.read(jamServiceProvider).joinSession(jamPayload.sessionId);
      return;
    }

    final audioHandler = await ref.read(audioHandlerProvider.future);

    if (jamPayload != null && jamPayload.queueIds.isNotEmpty) {
      final queueSongs = await saavn.getSongDetails(ids: jamPayload.queueIds);
      if (queueSongs.isNotEmpty) {
        final safeIndex = jamPayload.startIndex.clamp(0, queueSongs.length - 1);
        await audioHandler.loadQueue(
          queueSongs,
          startIndex: safeIndex,
          sourceId:
              'jam:${jamPayload.songId.isNotEmpty ? jamPayload.songId : queueSongs[safeIndex].id}',
          sourceName:
              jamPayload.sourceName.isNotEmpty
                  ? '${jamPayload.sourceName} Jam'
                  : 'Jam Session',
        );
        if (jamPayload.positionMs > 0) {
          await audioHandler.seek(
            Duration(milliseconds: jamPayload.positionMs),
          );
        }
        return;
      }
    }

    if (jamPayload != null && jamPayload.songId.isNotEmpty) {
      final songs = await saavn.getSongDetails(ids: [jamPayload.songId]);
      if (songs.isEmpty) return;

      await audioHandler.playFromSeedSong(
        songs.first,
        sourceId: 'jam:${songs.first.id}',
        sourceName:
            jamPayload.sourceName.isNotEmpty
                ? '${jamPayload.sourceName} Jam'
                : 'Jam Session',
      );

      if (jamPayload.positionMs > 0) {
        await audioHandler.seek(Duration(milliseconds: jamPayload.positionMs));
      }
      return;
    }

    final sharedContent = parseSharedContentUri(uri);
    if (sharedContent == null) return;

    switch (sharedContent.type) {
      case SharedContentType.song:
        final songs = await saavn.getSongDetails(
          ids: sharedContent.id.isNotEmpty ? [sharedContent.id] : null,
          link: sharedContent.url,
        );
        if (songs.isEmpty) return;
        await audioHandler.playFromSeedSong(
          songs.first,
          sourceId: 'share:song:${songs.first.id}',
          sourceName: 'Shared Song',
        );
        return;
      case SharedContentType.album:
        final album = await saavn.fetchAlbumById(
          albumId: sharedContent.id.isNotEmpty ? sharedContent.id : null,
          link: sharedContent.url.isNotEmpty ? sharedContent.url : null,
        );
        if (album == null || album.songs.isEmpty) return;
        final songs = await saavn.getSongDetails(
          ids: album.songs.map((song) => song.id).toList(),
        );
        if (songs.isEmpty) return;
        await audioHandler.loadQueue(
          songs,
          sourceId: 'share:album:${album.id}',
          sourceName: album.title,
        );
        return;
      case SharedContentType.playlist:
        final playlist = await saavn.fetchPlaylistById(
          playlistId: sharedContent.id.isNotEmpty ? sharedContent.id : null,
          link: sharedContent.url.isNotEmpty ? sharedContent.url : null,
        );
        if (playlist == null || playlist.songs.isEmpty) return;
        final songs = await saavn.getSongDetails(
          ids: playlist.songs.map((song) => song.id).toList(),
        );
        if (songs.isEmpty) return;
        await audioHandler.loadQueue(
          songs,
          sourceId: 'share:playlist:${playlist.id}',
          sourceName: playlist.title,
        );
        return;
      case SharedContentType.artist:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(audioHandlerProvider);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeNotifier,
      builder: (context, mode, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final ColorScheme lightScheme =
                lightDynamic ?? ColorScheme.fromSeed(seedColor: spotifyGreen);
            final ColorScheme darkScheme =
                darkDynamic ??
                ColorScheme.fromSeed(
                  seedColor: spotifyGreen,
                  brightness: Brightness.dark,
                );

            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: lightScheme,
                useMaterial3: true,
                fontFamily: brandFontFamily,
                textTheme: ThemeController().spotifyTextTheme,
              ),
              darkTheme: ThemeData(
                colorScheme: darkScheme,
                useMaterial3: true,
                fontFamily: brandFontFamily,
                textTheme: ThemeController().spotifyTextTheme,
              ),
              themeMode: mode,
              onGenerateRoute: (settings) {
                Widget page;
                switch (settings.name) {
                  case '/search':
                    page = const Search();
                    break;
                  case '/library':
                    page = const LibraryPage();
                    break;
                  default:
                    page = const Home();
                }
                return PageTransition(
                  type: PageTransitionType.rightToLeft,
                  child: page,
                  settings: settings,
                  duration: const Duration(milliseconds: 300),
                  reverseDuration: const Duration(milliseconds: 300),
                );
              },
            );
          },
        );
      },
    );
  }
}
