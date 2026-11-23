import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/models.dart';
import '../theme.dart';

/// Plain Material 3 card: solid surface, no blur, no glass effect.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: body,
            ),
    );
  }
}

/// Compact poster card: poster + title + year/rating. Hero-animated.
class PosterCard extends StatelessWidget {
  final Subject subject;
  final VoidCallback onTap;
  final double? progress; // 0..1 continue-watching progress, if any

  const PosterCard({
    super.key,
    required this.subject,
    required this.onTap,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Hero(
                tag: 'poster-${subject.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _poster(),
                      if (subject.isSeries)
                        Positioned(top: 6, right: 6, child: _chip('TV')),
                      if (progress != null && progress! > 0.02)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress,
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
            ),
            const SizedBox(height: 6),
            Text(
              subject.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (subject.year != null)
                  Text(
                    subject.year!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                if (subject.year != null && subject.rating != null)
                  const Text(
                    '  ·  ',
                    style: TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                if (subject.rating != null) ...[
                  const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                  const SizedBox(width: 2),
                  Text(
                    subject.rating!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white24),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );

  Widget _poster() {
    final url = subject.posterUrl;
    if (url == null || url.isEmpty) {
      return Container(
        color: AppTheme.surface,
        child: const Icon(
          Icons.movie_outlined,
          size: 40,
          color: AppTheme.muted,
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // Downscale decoded posters: far less memory + no jank on scroll.
      memCacheWidth: 400,
      placeholder: (_, _) => const _Shimmer(),
      errorWidget: (_, _, _) => Container(
        color: AppTheme.surface,
        child: const Icon(
          Icons.broken_image_outlined,
          size: 32,
          color: AppTheme.muted,
        ),
      ),
    );
  }
}

/// Lightweight shimmer placeholder (no extra dependency).
class _Shimmer extends StatefulWidget {
  const _Shimmer();
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Container(
      color: Color.lerp(
        const Color(0xFF1A1A24),
        const Color(0xFF262633),
        _c.value,
      ),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 32, color: AppTheme.muted),
      ),
    ),
  );
}

/// Responsive poster grid: 3 cols phone, 5–6 wide Windows window.
class PosterGrid extends StatelessWidget {
  final List<Subject> items;
  final void Function(Subject) onTap;
  final Map<String, double>? progressById;
  final ScrollController? controller;
  final Widget? footer;

  const PosterGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.progressById,
    this.controller,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1100
        ? 6
        : width >= 800
        ? 5
        : width >= 600
        ? 4
        : 3;
    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      scrollCacheExtent: const ScrollCacheExtent.pixels(800),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: items.length + (footer == null ? 0 : 1),
      itemBuilder: (context, i) {
        if (i >= items.length) return footer!;
        final s = items[i];
        return PosterCard(
          subject: s,
          progress: progressById?[s.id],
          onTap: () => onTap(s),
        );
      },
    );
  }
}

/// Skeleton grid shown while the home feed loads.
class PosterGridSkeleton extends StatelessWidget {
  const PosterGridSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1100
        ? 6
        : width >= 800
        ? 5
        : width >= 600
        ? 4
        : 3;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: cols * 2,
      itemBuilder: (_, _) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _Shimmer()),
          SizedBox(height: 6),
          _ShimmerBar(width: 90),
          SizedBox(height: 4),
          _ShimmerBar(width: 50),
        ],
      ),
    );
  }
}

class _ShimmerBar extends StatelessWidget {
  final double width;
  const _ShimmerBar({required this.width});
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 10,
    decoration: BoxDecoration(
      color: const Color(0xFF23232F),
      borderRadius: BorderRadius.circular(5),
    ),
  );
}
