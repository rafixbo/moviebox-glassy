import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/models.dart';
import '../api/moviebox_api.dart';
import '../services/storage.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import 'details_screen.dart';

const List<String> kTrendingSearches = [
  'Avengers',
  'Pushpa',
  'Squid Game',
  'Money Heist',
  'John Wick',
  'Dune',
  'Breaking Bad',
  'Interstellar',
];

enum SearchFilter { all, movie, series }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Subject> _results = [];
  List<Subject> _filtered = [];
  List<String> _recent = [];
  bool _searching = false;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = false;
  String? _error;
  SearchFilter _filter = SearchFilter.all;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final r = await LocalStore.instance.recentSearches();
    if (mounted) setState(() => _recent = r);
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _filtered = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _page = 1;
    });
    try {
      final res = await MovieBoxApi.instance.search(query, page: 1);
      await LocalStore.instance.addRecentSearch(query);
      if (!mounted) return;
      setState(() {
        _results = res;
        _searching = false;
        _hasMore = res.length >= 15;
      });
      _applyFilter();
      _loadRecent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Search failed. Check your connection and tap Retry.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _controller.text.trim().isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final res = await MovieBoxApi.instance.search(
        _controller.text.trim(),
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _page++;
        _results = [..._results, ...res];
        _hasMore = res.length >= 15;
        _loadingMore = false;
      });
      _applyFilter();
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _applyFilter() {
    setState(() {
      _filtered = switch (_filter) {
        SearchFilter.all => _results,
        SearchFilter.movie => _results.where((s) => !s.isSeries).toList(),
        SearchFilter.series => _results.where((s) => s.isSeries).toList(),
      };
    });
  }

  void _open(Subject s) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => DetailsScreen(subject: s)));
  }

  void _runSearch(String q) {
    _controller.text = q;
    _search(q);
  }

  @override
  Widget build(BuildContext context) {
    final showIdle = _controller.text.trim().isEmpty && _results.isEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SearchBar(
            controller: _controller,
            hintText: 'Search movies, TV shows…',
            leading: const Icon(Icons.search),
            trailing: [
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _controller.clear();
                    _search('');
                    setState(() {});
                  },
                ),
            ],
            onChanged: _onChanged,
            onSubmitted: _search,
            elevation: const WidgetStatePropertyAll(0),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              for (final f in SearchFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(switch (f) {
                      SearchFilter.all => 'All',
                      SearchFilter.movie => 'Movies',
                      SearchFilter.series => 'TV Shows',
                    }),
                    selected: _filter == f,
                    selectedColor: AppTheme.accent,
                    labelStyle: const TextStyle(fontSize: 12),
                    onSelected: (_) {
                      setState(() => _filter = f);
                      _applyFilter();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (_searching)
          const Expanded(child: PosterGridSkeleton())
        else if (_error != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
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
                      onPressed: () => _search(_controller.text),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (showIdle)
          Expanded(child: _idle())
        else
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('No results for this filter.'))
                : PosterGrid(
                    items: _filtered,
                    controller: _scroll,
                    onTap: _open,
                    footer: _loadingMore
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : null,
                  ),
          ),
      ],
    );
  }

  Widget _idle() => ListView(
    padding: const EdgeInsets.all(16),
    scrollCacheExtent: const ScrollCacheExtent.pixels(400),
    children: [
      if (_recent.isNotEmpty) ...[
        const Text(
          'Recent',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _recent
              .map(
                (q) => ActionChip(
                  label: Text(q),
                  avatar: const Icon(Icons.history, size: 16),
                  onPressed: () => _runSearch(q),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
      ],
      const Text(
        'Trending',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: kTrendingSearches
            .map(
              (q) => ActionChip(
                label: Text(q),
                avatar: const Icon(Icons.trending_up, size: 16),
                onPressed: () => _runSearch(q),
              ),
            )
            .toList(),
      ),
    ],
  );
}
