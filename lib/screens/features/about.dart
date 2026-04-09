import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/generalcards.dart';
import '../../components/snackbar.dart';
import '../../services/jamlink.dart';
import '../../services/jamsync.dart';
import '../../services/systemconfig.dart';
import '../../shared/constants.dart';
import '../../utils/theme.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  late ScrollController _scrollController;
  final TextEditingController _jamConnectController = TextEditingController();
  final JamLinkService _jamLinkService = JamLinkService();
  bool _isTitleCollapsed = false;
  bool _showUpdateAvailable = true;
  bool _isJoiningJam = false;

  @override
  void initState() {
    super.initState();

    _scrollController =
        ScrollController()..addListener(() {
          final offset = _scrollController.offset;
          if (offset > 120 && !_isTitleCollapsed) {
            setState(() => _isTitleCollapsed = true);
          } else if (offset <= 120 && _isTitleCollapsed) {
            setState(() => _isTitleCollapsed = false);
          }
        });

    checkForUpdate();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _jamConnectController.dispose();
    super.dispose();
  }

  Future<void> _joinJamFromInput() async {
    final sessionTarget = _extractJamSessionTarget(_jamConnectController.text);
    if (sessionTarget.isEmpty) {
      await info(
        'Paste a Jam invite link or enter a session code like FED94D.',
        Severity.warning,
      );
      return;
    }

    setState(() => _isJoiningJam = true);
    try {
      await ref.read(jamServiceProvider).joinSession(sessionTarget);
      if (!mounted) return;
      _jamConnectController.clear();
      FocusScope.of(context).unfocus();
      await info('Jam connected.', Severity.success);
    } catch (_) {
      if (!mounted) return;
      await info('Could not join this Jam invite.', Severity.error);
    } finally {
      if (mounted) {
        setState(() => _isJoiningJam = false);
      }
    }
  }

  String _extractJamSessionTarget(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final sessionMatch = RegExp(
      r'(jam-[a-zA-Z0-9-]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (sessionMatch != null) {
      return sessionMatch.group(1) ?? '';
    }

    final uriMatch = RegExp(
      r'((?:https?|svara):\/\/[^\s]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (uriMatch != null) {
      final candidate = Uri.tryParse(uriMatch.group(1) ?? '');
      if (candidate != null) {
        final payload = _jamLinkService.parse(candidate);
        if (payload != null && payload.sessionId.isNotEmpty) {
          return payload.sessionId;
        }
      }
    }

    final codeMatch = RegExp(
      r'(?:session\s*code\s*[:\-]?\s*)?([a-zA-Z0-9]{6})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (codeMatch != null) {
      return codeMatch.group(1) ?? '';
    }

    return trimmed;
  }

  Widget _buildJamConnectCard(JamSessionState jamState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Jam Connect',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            jamState.isActive
                ? 'Connected to ${jamState.hostName.isNotEmpty ? jamState.hostName : 'live Jam'} • code ${jamState.shareCode}'
                : 'Paste a Jam invite link or enter a 6-character session code to join instantly.',
            style: const TextStyle(
              color: Colors.white70,
              height: 1.5,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _jamConnectController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Invite link or code like FED94D',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.black.withAlpha(70),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withAlpha(12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withAlpha(12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: spotifyGreen),
              ),
            ),
            onSubmitted: (_) => _joinJamFromInput(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isJoiningJam ? null : _joinJamFromInput,
                  style: FilledButton.styleFrom(
                    backgroundColor: spotifyGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child:
                      _isJoiningJam
                          ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                          : const Text(
                            'Join Jam',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                ),
              ),
              if (jamState.shareCode.isNotEmpty) ...[
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: jamState.shareCode),
                    );
                    await info('Session code copied.', Severity.success);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withAlpha(24)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Copy Code'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String body,
    String? eyebrow,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow,
              style: TextStyle(
                color: getDominantDarker(spotifyGreen),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              height: 1.5,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureTile({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: spotifyGreen.withAlpha(28),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: spotifyGreen, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white60,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildCreditsSection() {
    final credits = [
      {
        'icon': 'assets/icons/github.png',
        'title': 'GitHub',
        'username': 'codewithevilxd',
        'url': developerGithubProfile,
      },
      {
        'icon': 'assets/icons/atsign.png',
        'title': 'Email',
        'username': developerEmailAddress,
        'url': developerEmailUrl,
      },
      {
        'icon': 'assets/icons/case.png',
        'title': 'Portfolio',
        'username': 'nishantdev.space',
        'url': developerPortfolioUrl,
      },
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Credits",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Developer links',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...credits.map(
              (c) => GestureDetector(
                onTap: () async {
                  final uri = Uri.parse(c['url']!);
                  try {
                    // Use launchUrl with universal links fallback
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    // Fallback: open in webview if external fails
                    debugPrint('--> URL launch failed: $e');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.inAppWebView);
                    } else {
                      info('Cannot open link: ${c['url']}', Severity.error);
                    }
                  }
                },

                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Image.asset(
                        c['icon']!,
                        height: 28,
                        width: 28,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c['title']!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c['username']!,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.open_in_new,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jamState = ref.watch(jamSessionProvider);

    return Scaffold(
      backgroundColor: spotifyBgColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // --- Collapsible Sliver AppBar ---
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            backgroundColor: getDominantDarker(spotifyGreen),
            leading: const BackButton(color: Colors.white),
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final minHeight = kToolbarHeight;
                final maxHeight = 160.0;
                final collapsePercent = ((constraints.maxHeight - minHeight) /
                        (maxHeight - minHeight))
                    .clamp(0.0, 1.0);

                return FlexibleSpaceBar(
                  centerTitle: false,
                  titlePadding: EdgeInsets.only(
                    left: _isTitleCollapsed ? 72 : 16,
                    bottom: 16,
                    right: 16,
                  ),
                  title: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isTitleCollapsed ? 1.0 : 0.0,
                    child: const Text(
                      "About",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  background: Container(
                    color: spotifyBgColor,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 32),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Opacity(
                          opacity: collapsePercent,
                          child: const Text(
                            "About",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              spotifyGreen.withAlpha(210),
                              Colors.blueAccent.withAlpha(170),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const CircleAvatar(
                          radius: 54,
                          backgroundImage:
                              AssetImage('assets/icons/nishant_profile.jpg'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        appDisplayName,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Music that adapts to your taste',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _sectionCard(
                    eyebrow: 'ABOUT THE APP',
                    title: 'Svara keeps discovery personal.',
                    body:
                        'Svara is built for people who want one clean place to search, play, and rediscover music without getting stuck in one language or one mood. It brings songs, artists, playlists, and albums together in a fast flow so listening feels instant.',
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _sectionCard(
                    title: 'What makes it different',
                    body:
                        'Your home feed is shaped by what you search, replay, and save. Instead of showing the same narrow set of tracks every time, Svara balances your listening habits with trending picks across Bollywood, global pop, regional hits, and fresh finds.',
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _featureTile(
                        icon: Icons.auto_awesome,
                        title: 'Personalized dashboard',
                        body:
                            'The feed learns from your recent plays, searches, and favorites so recommendations feel closer to your real taste.',
                      ),
                      const SizedBox(height: 12),
                      _featureTile(
                        icon: Icons.trending_up,
                        title: 'Trending across scenes',
                        body:
                            'Browse shelves that surface Bollywood, global, and regional momentum instead of staying locked to a single category.',
                      ),
                      const SizedBox(height: 12),
                      _featureTile(
                        icon: Icons.library_music,
                        title: 'Search built for playback',
                        body:
                            'Look up songs, artists, playlists, and albums from one place, then jump into playback with less friction.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildJamConnectCard(jamState),
                ),
                const SizedBox(height: 20),
                if (isAppUpdateAvailable && _showUpdateAvailable) ...[
                  const SizedBox(height: 20),
                  GeneralCards(
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
                ],
                Divider(color: Colors.grey.shade800),

                const SizedBox(height: 20),
              ],
            ),
          ),
          _buildCreditsSection(),
        ],
      ),
    );
  }
}
