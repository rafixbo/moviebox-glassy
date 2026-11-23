import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/models.dart';
import '../api/moviebox_api.dart';
import '../services/storage.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import 'details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Subject> _hero = [];
  List<Subject> _all = [];
  List<ContinueItem> _cw = [];
  Map<String, double> _progress = {};
  bool _loading = true;
  String? _error;
  int _heroPage = 0;
  late final PageController _heroController;
  Timer? _heroTimer;

  @override
  void initState() {
    super.initState();
    _heroController = PageController();
    _load();
    _heroTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_hero.length < 2 || !_heroController.hasClients) return;
      final next = (_heroPage + 1) % _hero.length;
      _heroController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final feed = await MovieBoxApi.instance.homeFeed();
      final cw = await LocalStore.instance.continueWatching();
      final progress = {for (final c in cw) c.subject.id: c.progress};
      if (!mounted) return;
      setState(() {
        _hero = feed.hero;
        _all = feed.all;
        _cw = cw;
        _progress = progress;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Never show raw network errors (SocketException, ClientException…)
      // to the user; the API layer already logged the technical detail.
      setState(() {
        _loading = false;
        _error =
            "Couldn't reach the server. Check your connection and tap Retry.";
      });
    }
  }

  List<Subject> _moreLike(Subject s) {
    final out = <Subject>[];
    for (final c in _all) {
      if (c.id == s.id || out.length >= 9) continue;
      final sharedGenre = c.genres.any(
        (g) => s.genres.map((e) => e.toLowerCase()).contains(g.toLowerCase()),
      );
      if (sharedGenre || c.type == s.type) out.add(c);
    }
    return out;
  }

  void _open(Subject s) {
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder: (_, _, _) =>
                DetailsScreen(subject: s, moreLikeThis: _moreLike(s)),
            transitionsBuilder: (_, a, _, child) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.04, 0), end: Offset.zero)
                    .animate(
                      CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
                    ),
                child: child,
              ),
            ),
            transitionDuration: const Duration(milliseconds: 280),
          ),
        )
        .then((_) => _refreshProgress());
  }

  Future<void> _refreshProgress() async {
    final cw = await LocalStore.instance.continueWatching();
    if (mounted) {
      setState(() {
        _cw = cw;
        _progress = {for (final c in cw) c.subject.id: c.progress};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Column(
        children: [
          SizedBox(height: 16),
          _HeroSkeleton(),
          Expanded(child: PosterGridSkeleton()),
        ],
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 40,
                  color: AppTheme.muted,
                ),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (_hero.isNotEmpty) _heroCarousel(width),
          if (_hero.length > 1) _pageDots(),
          if (_cw.isNotEmpty) _continueWatching(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text(
                  'Trending now',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${_all.length} titles',
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: PosterGrid(
              items: _all,
              progressById: _progress,
              onTap: _open,
            ),
          ),
        ],
      ),
    );
  }

  /// Big rounded hero card: backdrop image, genre line, big title,
  /// year + type, white pill Play button — like the reference.
  Widget _heroCarousel(double width) {
    final height = width >= 800 ? 380.0 : 300.0;
    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: _heroController,
        onPageChanged: (i) => setState(() => _heroPage = i),
        itemCount: _hero.length,
        itemBuilder: (context, i) {
          final s = _hero[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () => _open(s),
              child: Hero(
                tag: 'hero-${s.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (s.posterUrl != null)
                        CachedNetworkImage(
                          imageUrl: s.posterUrl!,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          memCacheWidth: 1000,
                          placeholder: (_, _) =>
                              Container(color: AppTheme.surface),
                          errorWidget: (_, _, _) =>
                              Container(color: AppTheme.surface),
                        )
                      else
                        Container(color: AppTheme.surface),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (s.genres.isNotEmpty)
                              Text(
                                s.genres.take(3).join('  •  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              s.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (s.year != null) s.year!,
                                s.isSeries ? 'SERIES' : 'MOVIE',
                              ].join('   '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => _open(s),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.black,
                              ),
                              label: const Text(
                                'Play',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pageDots() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _hero.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: i == _heroPage ? 18 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == _heroPage ? Colors.white : Colors.white38,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }

  /// Continue watching rail: poster thumbs with progress + count badge.
  Widget _continueWatching() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Continue watching',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_cw.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 178,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollCacheExtent: const ScrollCacheExtent.pixels(600),
              itemCount: _cw.length,
              itemBuilder: (_, i) {
                final c = _cw[i];
                final s = c.subject;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => _open(s),
                    child: SizedBox(
                      width: 108,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (s.posterUrl != null)
                                    CachedNetworkImage(
                                      imageUrl: s.posterUrl!,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 400,
                                      placeholder: (_, _) =>
                                          Container(color: AppTheme.surface),
                                      errorWidget: (_, _, _) => Container(
                                        color: AppTheme.surface,
                                        child: const Icon(
                                          Icons.movie_outlined,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      color: AppTheme.surface,
                                      child: const Icon(
                                        Icons.movie_outlined,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: LinearProgressIndicator(
                                      value: c.progress,
                                      minHeight: 3,
                                      backgroundColor: Colors.white24,
                                      valueColor: const AlwaysStoppedAnimation(
                                        AppTheme.accent2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            c.label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(height: 300, color: const Color(0xFF1A1A24)),
    ),
  );
}
