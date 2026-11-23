import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../api/moviebox_api.dart';
import '../services/storage.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Subject> _hero = [];
  List<Subject> _all = [];
  Map<String, double> _progress = {};
  bool _loading = true;
  String? _error;
  int _heroPage = 0;
  late final PageController _heroController;
  Timer? _heroTimer;

  @override
  void initState() {
    super.initState();
    _heroController = PageController(viewportFraction: 0.92);
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
        _progress = progress;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the home feed. Pull to retry.\n$e';
      });
    }
  }

  void _open(Subject s) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => DetailsScreen(subject: s),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.04, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 280),
      ),
    ).then((_) => _refreshProgress());
  }

  Future<void> _refreshProgress() async {
    final cw = await LocalStore.instance.continueWatching();
    if (mounted) {
      setState(() => _progress = {for (final c in cw) c.subject.id: c.progress});
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
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40, color: GlassTheme.muted),
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
    return RefreshIndicator(
      onRefresh: _load,
      color: GlassTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (_hero.isNotEmpty) _heroCarousel(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text('Trending now',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${_all.length} titles',
                    style: const TextStyle(fontSize: 12, color: GlassTheme.muted)),
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

  Widget _heroCarousel() {
    return SizedBox(
      height: 230,
      child: PageView.builder(
        controller: _heroController,
        onPageChanged: (i) => setState(() => _heroPage = i),
        itemCount: _hero.length,
        itemBuilder: (context, i) {
          final s = _hero[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: GestureDetector(
              onTap: () => _open(s),
              child: Hero(
                tag: 'hero-${s.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (s.posterUrl != null)
                        CachedNetworkImage(
                          imageUrl: s.posterUrl!,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          placeholder: (_, _) =>
                              Container(color: GlassTheme.surface),
                          errorWidget: (_, _, _) =>
                              Container(color: GlassTheme.surface),
                        )
                      else
                        Container(color: GlassTheme.surface),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16, right: 16, bottom: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (s.year != null)
                                  Text(s.year!,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white70)),
                                if (s.rating != null) ...[
                                  const SizedBox(width: 10),
                                  const Icon(Icons.star_rounded,
                                      size: 14, color: Colors.amber),
                                  Text(s.rating!,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white70)),
                                ],
                                if (s.isSeries) ...[
                                  const SizedBox(width: 10),
                                  const Text('TV SERIES',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: GlassTheme.accent2)),
                                ],
                              ],
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
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(height: 230, color: const Color(0xFF1A1A24)),
        ),
      );
}
