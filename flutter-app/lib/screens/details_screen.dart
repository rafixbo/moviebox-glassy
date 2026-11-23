import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/models.dart';
import '../api/moviebox_api.dart';
import '../services/downloads.dart';
import '../services/storage.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import 'player_screen.dart';

class DetailsScreen extends StatefulWidget {
  final Subject subject;

  /// Titles to show under "More like this" (from the home feed).
  final List<Subject> moreLikeThis;

  const DetailsScreen({
    super.key,
    required this.subject,
    this.moreLikeThis = const [],
  });

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  Details? _details;
  String? _error;
  bool _loading = true;
  bool _isFav = false;
  int _season = 1;
  int _episode = 1;
  String? _dubSubjectId;
  Duration? _savedPosition;

  Subject get _subject {
    final d = _details?.subject;
    if (d == null) return widget.subject;
    // A chosen dub is a different subjectId (same title, other language).
    return d;
  }

  String get _activeId => _dubSubjectId ?? widget.subject.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await MovieBoxApi.instance.details(widget.subject.id);
      final fav = await LocalStore.instance.isFavorite(widget.subject.id);
      final pos = await LocalStore.instance.positionFor(
        widget.subject.id,
        d.isSeries ? 1 : 0,
        d.isSeries ? 1 : 0,
      );
      if (!mounted) return;
      setState(() {
        _details = d;
        _loading = false;
        _isFav = fav;
        _savedPosition = pos;
        if (d.seasons.isNotEmpty) {
          _season = d.seasons.first.season;
          _episode = d.seasons.first.episodes.isNotEmpty
              ? d.seasons.first.episodes.first
              : 1;
        }
      });
      await LocalStore.instance.addHistory(widget.subject);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load details. Check your connection and tap Retry.';
      });
    }
  }

  Future<void> _toggleFav() async {
    await LocalStore.instance.toggleFavorite(widget.subject);
    if (mounted) setState(() => _isFav = !_isFav);
  }

  Future<void> _play() async {
    final startAt = await _resumePrompt();
    if (startAt == null && _savedPosition != null) return; // dismissed
    await _openSources(startAt: startAt ?? Duration.zero);
  }

  /// Returns Duration.zero to start over, the saved position to resume,
  /// or null if the dialog was dismissed.
  Future<Duration?> _resumePrompt() async {
    final pos = _savedPosition;
    if (pos == null || pos.inSeconds < 10) return Duration.zero;
    return showDialog<Duration>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continue watching?'),
        content: Text('Resume from ${_fmt(pos)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, Duration.zero),
            child: const Text('Start over'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, pos),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSources({required Duration startAt}) async {
    List<StreamSource> sources = [];
    bool loading = true;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            if (loading) {
              MovieBoxApi.instance
                  .streams(
                    _activeId,
                    season: _subject.isSeries ? _season : 0,
                    episode: _subject.isSeries ? _episode : 0,
                    detectors: _details?.detectors ?? const [],
                  )
                  .then((s) {
                    if (ctx.mounted) {
                      setSheet(() {
                        sources = s;
                        loading = false;
                        if (s.isEmpty) {
                          error = 'No playable sources found for this title.';
                        }
                      });
                    }
                  })
                  .catchError((e) {
                    if (ctx.mounted) {
                      setSheet(() {
                        loading = false;
                        error = 'Could not load sources. Check your connection and try again.';
                      });
                    }
                  });
            }
            return _sourcesSheet(ctx, sources, loading, error, startAt);
          },
        );
      },
    );
  }

  Widget _sourcesSheet(
    BuildContext ctx,
    List<StreamSource> sources,
    bool loading,
    String? error,
    Duration startAt,
  ) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scroll) => AppCard(
        radius: 24,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _subject.isSeries
                  ? 'Sources · S$_season E$_episode'
                  : 'Sources · ${_subject.title}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Some links are resolver links and may not play in-app — '
              'use “Open externally” if playback fails.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              Expanded(
                child: Center(child: Text(error, textAlign: TextAlign.center)),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(400),
                  itemCount: sources.length,
                  itemBuilder: (_, i) {
                    final s = sources[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        radius: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                s.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.uploader ?? 'Direct',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  if (s.sizeLabel.isNotEmpty)
                                    Text(
                                      s.sizeLabel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Download',
                              icon: const Icon(Icons.download_rounded),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await DownloadManager.instance.start(
                                  subjectId: _activeId,
                                  season: _subject.isSeries ? _season : 0,
                                  episode: _subject.isSeries ? _episode : 0,
                                  title: _subject.title,
                                  url: s.url,
                                  qualityLabel: s.label,
                                  cookie: s.cookie,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Download started — see Library → Downloads',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Play',
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                color: AppTheme.accent2,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _playSource(sources, s, startAt);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _playSource(
    List<StreamSource> sources,
    StreamSource source,
    Duration startAt,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          subject: _subject,
          season: _subject.isSeries ? _season : 0,
          episode: _subject.isSeries ? _episode : 0,
          sources: sources,
          initialSource: source,
          startAt: startAt,
          detectors: _details?.detectors ?? const [],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _subject;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: wide ? 420 : 340,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'poster-${widget.subject.id}',
                    child: s.posterUrl == null
                        ? Container(color: AppTheme.surface)
                        : CachedNetworkImage(
                            imageUrl: s.posterUrl!,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            memCacheWidth: 1000,
                            placeholder: (_, _) =>
                                Container(color: AppTheme.surface),
                            errorWidget: (_, _, _) =>
                                Container(color: AppTheme.surface),
                          ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          AppTheme.bg.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isFav ? Icons.favorite : Icons.favorite_border,
                  color: _isFav ? AppTheme.accent3 : null,
                ),
                onPressed: _toggleFav,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _error != null
                  ? Center(
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
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _body(s),
            ),
          ),
        ],
      ),
    );
  }

  /// Reference-style layout: single column on phones, two columns
  /// (info | episodes + more like this) on wide screens.
  Widget _body(Subject s) {
    final d = _details!;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final info = _infoSection(s, d);
    final episodes = d.isSeries && d.seasons.isNotEmpty
        ? _episodesPanel(d)
        : const SizedBox.shrink();
    final more = _moreLikeThisSection();
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          info,
          if (d.isSeries && d.seasons.isNotEmpty) ...[
            const SizedBox(height: 20),
            episodes,
          ],
          if (more != null) ...[const SizedBox(height: 24), more],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: info),
        const SizedBox(width: 28),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d.isSeries && d.seasons.isNotEmpty) episodes,
              if (more != null) ...[const SizedBox(height: 24), more],
            ],
          ),
        ),
      ],
    );
  }

  /// Title, rating chip + meta line, genre chips, white pill Play,
  /// description and facts.
  Widget _infoSection(Subject s, Details d) {
    final meta = <String>[
      if (s.year != null) s.year!,
      s.isSeries ? 'Series' : 'Movie',
      if (s.duration != null) s.duration!,
      if (d.isSeries && d.seasons.isNotEmpty)
        d.seasons.length == 1 ? '1 season' : '${d.seasons.length} seasons',
    ].join('  •  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.title,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (s.rating != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      s.rating!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            if (s.rating != null) const SizedBox(width: 10),
            Expanded(
              child: Text(
                meta,
                style: const TextStyle(fontSize: 13, color: AppTheme.muted),
              ),
            ),
          ],
        ),
        if (s.genres.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: s.genres
                .map(
                  (g) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      g,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFCFC8FF),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
            label: Text(
              _savedPosition != null && _savedPosition!.inSeconds >= 10
                  ? 'Play · resume ${_fmt(_savedPosition!)}'
                  : 'Play',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
        if ((s.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'About',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            s.description!,
            style: const TextStyle(color: AppTheme.muted, height: 1.5),
          ),
        ],
        if (s.director != null || s.stars != null) ...[
          const SizedBox(height: 16),
          if (s.director != null) _fact('Director', s.director!),
          if (s.stars != null) _fact('Cast', s.stars!),
        ],
        const SizedBox(height: 20),
        const Text(
          'Sources are resolved live from the MovieBox API. '
          'This app hosts no media.',
          style: TextStyle(fontSize: 11, color: AppTheme.muted),
        ),
      ],
    );
  }

  /// Episodes panel: count badge, Audio + Season dropdowns, episode chips.
  Widget _episodesPanel(Details d) {
    final totalEps = d.seasons.fold<int>(
      0,
      (sum, se) => sum + se.episodes.length,
    );
    return AppCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Episodes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$totalEps episodes',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dropdownField<String?>(
                  icon: Icons.audiotrack_rounded,
                  value: _dubSubjectId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Original'),
                    ),
                    for (final dub in d.dubs)
                      DropdownMenuItem<String?>(
                        value: dub.subjectId,
                        child: Text(
                          dub.language,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _dubSubjectId = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdownField<int>(
                  icon: Icons.layers_rounded,
                  value: _season,
                  items: [
                    for (final se in d.seasons)
                      DropdownMenuItem<int>(
                        value: se.season,
                        child: Text('Season ${se.season}'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _season = v;
                      final eps = _currentEpisodes(d);
                      _episode = eps.isNotEmpty ? eps.first : 1;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _currentEpisodes(d)
                .map(
                  (ep) => ChoiceChip(
                    label: Text(ep.toString().padLeft(2, '0')),
                    selected: _episode == ep,
                    selectedColor: AppTheme.accent,
                    onSelected: (_) => setState(() => _episode = ep),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _dropdownField<T>({
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.muted),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              style: const TextStyle(fontSize: 13, color: AppTheme.text),
              dropdownColor: AppTheme.surface,
            ),
          ),
        ],
      ),
    );
  }

  /// "More like this" grid: poster + title + star rating + year.
  Widget? _moreLikeThisSection() {
    final items = widget.moreLikeThis
        .where((s) => s.id != widget.subject.id)
        .toList();
    if (items.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'More like this',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final s = items[i];
            return PosterCard(
              subject: s,
              onTap: () {
                final rest = items.where((e) => e.id != s.id).toList();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        DetailsScreen(subject: s, moreLikeThis: rest),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  List<int> _currentEpisodes(Details d) {
    final se = d.seasons.firstWhere(
      (s) => s.season == _season,
      orElse: () => d.seasons.first,
    );
    return se.episodes;
  }

  Widget _fact(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: AppTheme.text),
        children: [
          TextSpan(
            text: '$k: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: v,
            style: const TextStyle(color: AppTheme.muted),
          ),
        ],
      ),
    ),
  );
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}
