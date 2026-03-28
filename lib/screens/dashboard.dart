import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/generalcards.dart';
import '../components/shimmers.dart';
import '../services/defaultfetcher.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import '../services/jiosaavn.dart';
import '../services/offlinemanager.dart';
import '../services/latestsaavnfetcher.dart';

import '../services/localnotification.dart';
import '../services/systemconfig.dart';
import '../shared/constants.dart';
import '../utils/theme.dart';
import 'features/language.dart';
import 'features/profile.dart';
import 'views/albumviewer.dart';
import 'views/artistviewer.dart';
import 'views/playlistviewer.dart';
import 'views/songsviewer.dart';

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({super.key});

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  bool loading = true;
  List<Playlist> playlists = [];
  List<Playlist> freqplaylists = [];
  List<ArtistDetails> artists = [];
  List<Album> albums = [];
  List<Playlist> freqRecentPlaylists = [];

  // cached shuffled lists
  List<Playlist> topLatest = [];
  List<Album> topLatestAlbum = [];
  List<Playlist> fresh = [];
  List<Album> freshAlbum = [];
  List<Playlist> partyShuffled = [];
  List<Playlist> loveShuffled = [];
  List<Playlist> trendingBollywood = [];
  List<Playlist> trendingGlobal = [];
  List<Playlist> trendingRegional = [];
  bool _showWaitingCard = true;
  bool _showUpdateAvailable = true;

  List<T> _uniqueById<T>(
    Iterable<T> items,
    String Function(T item) getId,
  ) {
    final unique = <String, T>{};
    for (final item in items) {
      final id = getId(item).trim();
      if (id.isEmpty || unique.containsKey(id)) continue;
      unique[id] = item;
    }
    return unique.values.toList();
  }

  Set<String> _tokenize(String value) {
    return RegExp(r'[a-z0-9]+')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .where((token) => token.length > 2)
        .toSet();
  }

  Set<String> _buildInterestTokens({
    required List<String> recentSearches,
    required List<SongDetail> recentSongs,
    required List<Album> recentAlbums,
    required List<Playlist> frequentPlaylists,
    required List<Album> frequentAlbums,
    required List<ArtistDetails> frequentArtists,
  }) {
    final tokens = <String>{};

    void add(String value) {
      tokens.addAll(_tokenize(value));
    }

    for (final term in recentSearches.take(5)) {
      add(term);
    }
    for (final song in recentSongs.take(5)) {
      add(song.title);
      add(song.album);
      add(song.primaryArtists);
    }
    for (final album in recentAlbums.take(5)) {
      add(album.title);
      add(album.artist);
    }
    for (final playlist in frequentPlaylists.take(8)) {
      add(playlist.title);
      add(playlist.description);
      add(playlist.artists.map((artist) => artist.title).join(' '));
    }
    for (final album in frequentAlbums.take(8)) {
      add(album.title);
      add(album.artist);
    }
    for (final artist in frequentArtists.take(8)) {
      add(artist.title);
      add(artist.dominantLanguage);
    }

    return tokens;
  }

  bool _matchesInterest(String content, Set<String> interestTokens) {
    if (interestTokens.isEmpty) return false;
    final normalized = content.toLowerCase();
    return interestTokens.any(normalized.contains);
  }

  List<Playlist> _buildPlaylistFeed({
    required List<Playlist> frequent,
    required List<Playlist> latest,
    required List<Playlist> curated,
    required Set<String> interestTokens,
    int limit = 30,
  }) {
    final matchingLatest = latest.where(
      (playlist) => _matchesInterest(
        [
          playlist.title,
          playlist.description,
          playlist.language,
          playlist.artists.map((artist) => artist.title).join(' '),
        ].join(' '),
        interestTokens,
      ),
    );

    final matchingCurated = curated.where(
      (playlist) => _matchesInterest(
        [
          playlist.title,
          playlist.description,
          playlist.language,
          playlist.artists.map((artist) => artist.title).join(' '),
        ].join(' '),
        interestTokens,
      ),
    );

    return _uniqueById<Playlist>(
      [
        ...frequent,
        ...matchingLatest,
        ...latest,
        ...matchingCurated,
        ...curated,
      ],
      (playlist) => playlist.id,
    ).take(limit).toList();
  }

  Future<List<Playlist>> _searchPlaylistsForQueries(
    List<String> queries, {
    int limit = 8,
  }) async {
    final responses = await Future.wait(
      queries.map((query) => saavn.searchPlaylists(query: query, limit: limit)),
    );

    return _uniqueById<Playlist>(
      responses.expand((response) => response?.results ?? const <Playlist>[]),
      (playlist) => playlist.id,
    );
  }

  List<Album> _buildAlbumFeed({
    required List<Album> frequent,
    required List<Album> recent,
    required List<Album> latest,
    required Set<String> interestTokens,
    int limit = 24,
  }) {
    final matchingLatest = latest.where(
      (album) => _matchesInterest(
        '${album.title} ${album.artist} ${album.language}',
        interestTokens,
      ),
    );

    return _uniqueById<Album>(
      [...frequent, ...recent, ...matchingLatest, ...latest],
      (album) => album.id,
    ).take(limit).toList();
  }

  List<ArtistDetails> _buildArtistFeed({
    required List<ArtistDetails> frequent,
    required List<ArtistDetails> fallback,
    required Set<String> interestTokens,
    int limit = 12,
  }) {
    final matchingFallback = fallback.where(
      (artist) => _matchesInterest(
        '${artist.title} ${artist.dominantLanguage} ${artist.bio.join(' ')}',
        interestTokens,
      ),
    );

    return _uniqueById<ArtistDetails>(
      [...frequent, ...matchingFallback, ...fallback],
      (artist) => artist.id,
    ).take(limit).toList();
  }

  @override
  void initState() {
    super.initState();
    _initInternetChecker();
    _init();
  }

  bool _isInitRunning = false;

  Future<void> _init() async {
    if (_isInitRunning) return;
    _isInitRunning = true;
    if (!mounted) return;
    setState(() => loading = true);

    try {
      await saavn.initBaseUrl();
      await initLanguage(ref);
      final prefs = await SharedPreferences.getInstance();

      final savedLang =
          prefs.getString('app_language') ?? defaultAppLanguages.join(',');
      debugPrint('[_init] Saved language string: $savedLang');

      final langs = savedLang.split(',').where((e) => e.isNotEmpty).toList();
      if (langs.isEmpty) langs.addAll(defaultAppLanguages);
      final playlistFutures = langs.map(
        (l) => LatestSaavnFetcher.getLatestPlaylists(l),
      );
      final albumFutures = langs.map(
        (l) => LatestSaavnFetcher.getLatestAlbums(l),
      );
      final results = await Future.wait([
        DailyFetches.refreshAllDaily(),
        DailyFetches.getPlaylistsFromCache(),
        DailyFetches.getArtistsAsListFromCache(),
        offlineManager.init(),
        Future.wait(playlistFutures),
        Future.wait(albumFutures),
        AppDatabase.getMonthlyListeningHours(),
        loadSearchHistory(),
        loadLastSongs(),
        loadLastAlbums(),
      ]);

      final curatedPlaylists = results[1] as List<Playlist>;
      final cachedArtists = results[2] as List<ArtistDetails>;

      final allPlaylists =
          (results[4] as List<List<Playlist>>).expand((x) => x).toList();
      final allAlbums =
          (results[5] as List<List<Album>>).expand((x) => x).toList();
      final recentSongs = results[8] as List<SongDetail>;
      final recentAlbums = results[9] as List<Album>;

      debugPrint('[_init] Latest playlists fetched: ${allPlaylists.length}');
      debugPrint('[_init] Latest albums fetched: ${allAlbums.length}');

      latestTamilPlayList = allPlaylists;
      latestTamilAlbums = allAlbums;

      final frequentArtists = (ref.read(frequentArtistsProvider)).take(10).toList();
      freqplaylists = (ref.read(frequentPlaylistsProvider)).take(10).toList();
      final frequentAlbums = (ref.read(frequentAlbumsProvider)).take(10).toList();

      final interestTokens = _buildInterestTokens(
        recentSearches: searchHistory,
        recentSongs: recentSongs,
        recentAlbums: recentAlbums,
        frequentPlaylists: freqplaylists,
        frequentAlbums: frequentAlbums,
        frequentArtists: frequentArtists,
      );

      final loveFutures = langs.map(
        (l) => searchPlaylistcache.searchPlaylistCache(query: 'love $l'),
      );
      final partyFutures = langs.map(
        (l) => searchPlaylistcache.searchPlaylistCache(query: 'party $l'),
      );

      final secondary = await Future.wait([
        Future.wait(loveFutures),
        Future.wait(partyFutures),
        _searchPlaylistsForQueries([
          'trending bollywood',
          'trending songs india',
          'now trending hindi',
        ]),
        _searchPlaylistsForQueries([
          'trending hollywood',
          'english viral hits',
          'trending today',
        ]),
        _searchPlaylistsForQueries([
          'trending punjabi',
          'trending telugu',
          'trending tamil',
        ]),
      ]);

      final loveResults = secondary[0] as List<List<Playlist>>;
      final partyResults = secondary[1] as List<List<Playlist>>;
      final allLove = loveResults.expand<Playlist>((items) => items).toList();
      final allParty = partyResults.expand<Playlist>((items) => items).toList();
      trendingBollywood = List<Playlist>.from(secondary[2] as List);
      trendingGlobal = List<Playlist>.from(secondary[3] as List);
      trendingRegional = List<Playlist>.from(secondary[4] as List);

      debugPrint(
        '[_init] Love playlists: ${allLove.length}, Party playlists: ${allParty.length}',
      );

      lovePlaylists = allLove;
      partyPlaylists = allParty;

      final personalizedPlaylists = _buildPlaylistFeed(
        frequent: freqplaylists,
        latest: allPlaylists,
        curated: curatedPlaylists,
        interestTokens: interestTokens,
      );
      final discoveryPlaylists = _uniqueById<Playlist>(
        [
          ...personalizedPlaylists,
          ...trendingBollywood,
          ...trendingGlobal,
          ...trendingRegional,
        ],
        (playlist) => playlist.id,
      );
      final personalizedAlbums = _buildAlbumFeed(
        frequent: frequentAlbums,
        recent: recentAlbums,
        latest: allAlbums,
        interestTokens: interestTokens,
      );

      playlists = discoveryPlaylists.take(30).toList();
      artists = _buildArtistFeed(
        frequent: frequentArtists,
        fallback: cachedArtists,
        interestTokens: interestTokens,
      );
      albums = _uniqueById<Album>(
        [...frequentAlbums, ...recentAlbums, ...personalizedAlbums],
        (album) => album.id,
      ).take(10).toList();

      topLatest = discoveryPlaylists.take(12).toList();
      fresh = discoveryPlaylists.skip(12).take(12).toList();

      topLatestAlbum = personalizedAlbums.take(12).toList();
      freshAlbum = personalizedAlbums.skip(12).take(12).toList();

      partyShuffled = _buildPlaylistFeed(
        frequent: freqplaylists,
        latest: partyPlaylists,
        curated: const [],
        interestTokens: interestTokens,
        limit: 15,
      );
      loveShuffled = _buildPlaylistFeed(
        frequent: freqplaylists,
        latest: lovePlaylists,
        curated: const [],
        interestTokens: interestTokens,
        limit: 15,
      );

      _buildFreqRecent(discoveryPlaylists);

      loading = false;
      if (mounted) setState(() {});
      await Future.delayed(const Duration(seconds: 3));
      await requestNotificationPermission();

      await checkForUpdate();

      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('[_init] Error occurred: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      _isInitRunning = false;
    }
  }

  void _buildFreqRecent(List<Playlist> personalizedFeed) {
    freqRecentPlaylists = _uniqueById<Playlist>(
      [
        ...freqplaylists.take(4),
        ...personalizedFeed,
        ...trendingBollywood,
        ...trendingGlobal,
      ],
      (playlist) => playlist.id,
    ).take(8).toList();
  }

  Future<void> _initInternetChecker() async {
    InternetConnection().onStatusChange.listen((status) {
      if (status == InternetStatus.disconnected) {
        hasInternet.value = false;
      } else {
        hasInternet.value = true;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch language listener
    ref.watch(languageNotifierProvider);

    return Scaffold(
      backgroundColor: spotifyBgColor,
      appBar: AppBar(
        backgroundColor: spotifyBgColor,
        elevation: 0,
        title: _buildHeader(),
      ),
      body:
          loading
              ? ListView(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                children: [
                  if (_showWaitingCard)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: GeneralCards(
                          onClose: () {
                            _showWaitingCard = false;
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                  heroGridShimmer(),
                  const SizedBox(height: 16),
                  buildPlaylistSectionShimmer(),
                  const SizedBox(height: 16),
                  buildPlaylistSectionShimmer(),
                  const SizedBox(height: 70),
                ],
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionGrid(freqRecentPlaylists),
                    _sectionList("Made for you", topLatest),
                    if (isAppUpdateAvailable && _showUpdateAvailable)
                      if (isAppUpdateAvailable && _showUpdateAvailable)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: GeneralCards(
                              iconPath: 'assets/icons/alert.png',
                              title: 'Update Available!',
                              content:
                                  'Please update the app to enjoy the best experience and latest features.',
                              downloadUrl: latestReleaseUrl,
                              onClose: () {
                                _showUpdateAvailable = false;
                                setState(() {});
                              },
                            ),
                          ),
                        ),
                    _sectionList("Bollywood Trending", trendingBollywood),
                    _sectionList("Global Trending", trendingGlobal),
                    _sectionList("Regional Heat", trendingRegional),
                    _sectionAlbumList("Albums for you", topLatestAlbum),
                    _sectionList("Fresh discoveries", fresh),
                    _sectionList("Party Mix", partyShuffled),
                    _sectionArtistList("Your Artists", artists),
                    _sectionAlbumList("Recent Albums", albums),
                    _sectionAlbumList("Because you listened", freshAlbum),
                    _sectionList("Love Mix", loveShuffled),
                    _sectionList("Trending across genres", playlists),
                    const SizedBox(height: 60),
                    makeItHappenCard(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
    );
  }

  Widget _buildHeader() {
    return ValueListenableBuilder(
      valueListenable: profileRefreshNotifier,
      builder: (context, value, child) {
        return Row(
          children: [
            GestureDetector(
              onTap: () => scaffoldKey.currentState?.openDrawer(),
              behavior: HitTestBehavior.opaque,
              child: CircleAvatar(
                radius: 18,
                backgroundImage:
                    (profileFile != null && profileFile!.existsSync())
                        ? FileImage(profileFile!)
                        : const AssetImage('assets/icons/logo.png')
                            as ImageProvider,
              ),
            ),
            const SizedBox(width: 15),
            const Text(
              appDisplayName,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionGrid(List<Playlist> playlists) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (playlists.isEmpty) return const SizedBox.shrink();

    final combined = [
      Playlist(
        id: 'liked',
        title: 'Liked Songs',
        type: 'custom',
        url: '',
        images: [],
      ),
      // Playlist(
      //   id: 'all',
      //   title: 'All Songs',
      //   type: 'custom',
      //   url: '',
      //   images: [],
      // ),
      ...playlists,
    ];

    // Only take first 10 for the grid
    final displayList = combined.take(12).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio:
                  MediaQuery.of(context).size.width > 600 ? 3 : 3.5,
            ),
            itemBuilder: (context, index) {
              final playlist = displayList[index];
              return _gridCard(playlist);
            },
          ),
        ],
      ),
    );
  }

  Widget _gridCard(Playlist p) {
    final isSpecial = p.id == 'liked' || p.id == 'all';
    final img = p.images.isNotEmpty ? p.images.first.url : '';
    final subtitle =
        (p.artists.isNotEmpty
            ? p.artists.first.title
            : (p.songCount != null ? '${p.songCount} songs' : ''));

    return GestureDetector(
      onTap: () {
        if (p.id == 'liked') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: true),
            ),
          );
        }
        // else if (p.id == 'all') {
        //   Navigator.of(context).push(
        //     PageTransition(
        //       type: PageTransitionType.rightToLeft,
        //       duration: const Duration(milliseconds: 300),
        //       child: SongsViewer(showLikedSongs: false),
        //     ),
        //   );
        // }
        else {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: PlaylistViewer(playlistId: p.id),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(70),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
              child:
                  isSpecial
                      ? Container(
                        height: double.infinity,
                        width: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors:
                                p.id == 'liked'
                                    ? [Colors.purpleAccent, Colors.deepPurple]
                                    : [spotifyGreen, Colors.teal],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          p.id == 'liked'
                              ? Icons.favorite
                              : Icons.library_music,
                          color: Colors.white,
                        ),
                      )
                      : (img.isNotEmpty
                          ? CacheNetWorkImg(
                            url: img,
                            width: 50,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          )
                          : Container(
                            width: 60,
                            color: Colors.grey[800],
                            child: const Icon(Icons.album, color: Colors.white),
                          )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- LIST SECTION (refined)
  Widget _sectionList(String title, List<Playlist> list) {
    if (loading) return buildPlaylistSectionShimmer();
    if (list.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: PageController(
                viewportFraction:
                    MediaQuery.of(context).size.width > 600 ? 0.22 : 0.45,
              ),
              padEnds: false,
              physics: const BouncingScrollPhysics(),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final playlist = list[index];
                return Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: _playlistCard(playlist),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistCard(Playlist playlist) {
    final imageUrl =
        playlist.images.isNotEmpty ? playlist.images.first.url : '';
    final subtitle =
        playlist.artists.isNotEmpty
            ? playlist.artists.first.title
            : (playlist.songCount != null ? '${playlist.songCount} songs' : '');
    final description = playlist.description;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (playlist.id == 'liked') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: true),
            ),
          );
        } else if (playlist.id == 'all') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: false),
            ),
          );
        } else {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: PlaylistViewer(playlistId: playlist.id),
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child:
                  imageUrl.isNotEmpty
                      ? CacheNetWorkImg(url: imageUrl, fit: BoxFit.cover)
                      : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.album,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              playlist.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (subtitle.isNotEmpty)
            Flexible(
              child: Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          if (description.isNotEmpty)
            Flexible(
              child: Text(
                description,
                style: TextStyle(color: Colors.white38, fontSize: 10),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionArtistList(String title, List<ArtistDetails> artists) {
    if (artists.isEmpty) return const SizedBox.shrink();

    final PageController controller = PageController(
      viewportFraction: MediaQuery.of(context).size.width > 600 ? 0.18 : 0.35,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: controller,
            padEnds: false,
            physics: const BouncingScrollPhysics(),
            itemCount: artists.length,
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  double scale = 1.0;
                  if (controller.position.haveDimensions) {
                    double page =
                        controller.page ?? controller.initialPage.toDouble();
                    scale = (1 - ((page - index).abs() * 0.3)).clamp(0.95, 1.0);
                  }
                  return Transform.scale(scale: scale, child: child);
                },
                child: _artistCard(artists[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _artistCard(ArtistDetails artist) {
    final imageUrl = artist.images.isNotEmpty ? artist.images.last.url : '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageTransition(
            type: PageTransitionType.rightToLeft,
            duration: const Duration(milliseconds: 300),
            child: ArtistViewer(artistId: artist.id),
          ),
        );
      },
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage:
                imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
            backgroundColor: Colors.grey.shade800,
            child:
                imageUrl.isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 30)
                    : null,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 100,
            child: Column(
              children: [
                Text(
                  artist.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
                Text(
                  artist.dominantLanguage,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionAlbumList(String title, List<Album> albums) {
    if (albums.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(title),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: PageController(
                viewportFraction:
                    MediaQuery.of(context).size.width > 600 ? 0.22 : 0.45,
              ),
              padEnds: false,
              physics: const BouncingScrollPhysics(),
              itemCount: albums.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: _albumCard(albums[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _albumCard(Album album) {
    final imageUrl = album.images.isNotEmpty ? album.images.last.url : '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageTransition(
            type: PageTransitionType.rightToLeft,
            duration: const Duration(milliseconds: 300),
            child: AlbumViewer(albumId: album.id),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child:
                  imageUrl.isNotEmpty
                      ? CacheNetWorkImg(url: imageUrl, fit: BoxFit.cover)
                      : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.album,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
            ),
          ),

          const SizedBox(height: 6),
          Text(
            album.title,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Text(
            album.artist,
            style: TextStyle(
              color: Colors.white38,
              fontWeight: FontWeight.w300,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
