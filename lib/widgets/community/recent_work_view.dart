import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../services/community_service.dart';
import '../../theme/app_colors.dart';
import 'community_ui.dart';
import 'media_viewer.dart';

/// Recent work tab: a Facebook-style feed of posts — a brief and 1–10
/// photos/videos each. Tap any photo to open it full screen.
class RecentWorkView extends StatefulWidget {
  const RecentWorkView({super.key, required this.bottomInset, this.focusPostId});

  final double bottomInset;

  /// Opened from a shared link: show this post first, highlighted.
  final String? focusPostId;

  @override
  State<RecentWorkView> createState() => _RecentWorkViewState();
}

class _RecentWorkViewState extends State<RecentWorkView> {
  static const int _pageSize = 10;

  final ScrollController _scroll = ScrollController();
  final List<CommunityPost> _posts = [];
  final Set<String> _shown = {};

  int _offset = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _end = false;
  String? _error;
  String? _highlightId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 900) _loadMore();
  }

  Future<void> _load() async {
    if (_error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await CommunityService.fetchPosts(limit: _pageSize);
      _offset = list.length;
      _end = list.length < _pageSize;
      final focusId = widget.focusPostId;
      String? highlight;
      if (focusId != null && _posts.isEmpty) {
        CommunityPost? focus;
        for (final p in list) {
          if (p.id == focusId) focus = p;
        }
        focus ??= await CommunityService.fetchPost(focusId);
        if (focus != null) {
          final f = focus;
          list
            ..removeWhere((p) => p.id == f.id)
            ..insert(0, f);
          highlight = f.id;
        }
      }
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(list.where((p) => p.media.isNotEmpty));
        _loading = false;
        _highlightId = highlight ?? _highlightId;
      });
      if (highlight != null) {
        Future.delayed(const Duration(milliseconds: 2600), () {
          if (mounted) setState(() => _highlightId = null);
        });
      }
    } catch (e) {
      debugPrint('Community posts not loaded: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Check your internet connection and try again.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _end || _loading || _error != null) return;
    setState(() => _loadingMore = true);
    try {
      final more = await CommunityService.fetchPosts(offset: _offset, limit: _pageSize);
      _offset += more.length;
      _end = more.length < _pageSize;
      final have = _posts.map((p) => p.id).toSet();
      if (!mounted) return;
      setState(() => _posts.addAll(more.where((p) => p.media.isNotEmpty && !have.contains(p.id))));
    } catch (_) {
      // Next scroll tries again.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    _end = false;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const headerHeight = 64.0;

    final slivers = <Widget>[SliverToBoxAdapter(child: SizedBox(height: top + headerHeight + 8))];
    if (_loading) {
      slivers.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverList.list(children: const [_PostSkeleton(), _PostSkeleton()]),
      ));
    } else if (_error != null) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomInset),
          child: CommunityMessage(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load recent work",
            body: _error!,
            onDark: false,
            action: 'Try again',
            onAction: _load,
          ),
        ),
      ));
    } else if (_posts.isEmpty) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomInset),
          child: const CommunityMessage(
            icon: Icons.collections_rounded,
            title: 'No posts yet',
            body: 'Photos and videos of cars we have worked on will show up here soon.',
            onDark: false,
          ),
        ),
      ));
    } else {
      slivers.add(SliverPadding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, widget.bottomInset + 12),
        sliver: SliverList.builder(
          itemCount: _posts.length + (_loadingMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= _posts.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: kCommunityGoldDeep),
                  ),
                ),
              );
            }
            final post = _posts[i];
            final first = _shown.add(post.id);
            return EntranceFade(
              key: ValueKey(post.id),
              animate: first,
              delayIndex: i,
              child: CommunityPostCard(post: post, highlight: post.id == _highlightId),
            );
          },
        ),
      ));
    }

    return ColoredBox(
      color: AppColors.ink,
      child: Stack(
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              color: kCommunityGoldDeep,
              backgroundColor: AppColors.surfaceRaised,
              edgeOffset: top + headerHeight,
              onRefresh: _refresh,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: slivers,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _FeedHeader(height: headerHeight),
          ),
        ],
      ),
    );
  }
}

/// Frosted header: back · "Community / RECENT WORK".
class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: top + height,
          padding: EdgeInsets.only(top: top, left: 16, right: 16),
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.82),
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              GlassCircleButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                onDark: false,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Community',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: communityText(size: 17, weight: FontWeight.w800, color: AppColors.txt)),
                    const SizedBox(height: 1),
                    Text('RECENT WORK',
                        maxLines: 1,
                        style: communityText(
                            size: 11.5, weight: FontWeight.w800, color: kCommunityGoldDeep, letterSpacing: 1.2)),
                  ],
                ),
              ),
              const SizedBox(width: 42),
            ],
          ),
        ),
      ),
    );
  }
}

/// One post: header, brief, photo grid, Share.
class CommunityPostCard extends StatelessWidget {
  const CommunityPostCard({super.key, required this.post, this.highlight = false});

  final CommunityPost post;
  final bool highlight;

  String get _summary {
    final parts = <String>[];
    if (post.photoCount > 0) parts.add('${post.photoCount} ${post.photoCount == 1 ? 'photo' : 'photos'}');
    if (post.videoCount > 0) parts.add('${post.videoCount} ${post.videoCount == 1 ? 'video' : 'videos'}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: highlight ? kCommunityGold : AppColors.line,
          width: highlight ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: highlight ? kCommunityGold.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.05),
            blurRadius: highlight ? 26 : 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  const CommunityAvatar(size: 42, spin: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CommunityName(color: AppColors.txt),
                        const SizedBox(height: 2),
                        Text(
                          [communityTimeAgo(post.createdAt), _summary].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: communityText(size: 12.5, weight: FontWeight.w600, color: AppColors.mut),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (post.body.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: _ExpandableText(text: post.body.trim()),
              ),
            CommunityMediaGrid(post: post),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Divider(height: 1, thickness: 1, color: AppColors.line),
                  Builder(
                    builder: (btnContext) => _ShareButton(
                      onTap: () => CommunityService.share(
                        btnContext,
                        text: post.body,
                        link: CommunityService.postLink(post.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: kCommunityGold.withValues(alpha: 0.18),
        highlightColor: kCommunityGold.withValues(alpha: 0.08),
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.share_rounded, size: 20, color: AppColors.txt),
              const SizedBox(width: 8),
              Flexible(
                child: Text('Share',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: communityText(size: 15, weight: FontWeight.w800, color: AppColors.txt)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The brief: 4 lines, then "See more".
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = communityText(size: 14.5, weight: FontWeight.w500, color: AppColors.txt, height: 1.48);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 4,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: long ? () => setState(() => _open = !_open) : null,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.text,
                  maxLines: _open ? null : 4,
                  overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: style,
                ),
                if (long)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_open ? 'See less' : 'See more',
                        style: communityText(size: 14, weight: FontWeight.w800, color: kCommunityGoldDeep)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Facebook-style layouts for 1, 2, 3, 4 and 5+ items ("+N" on the last).
class CommunityMediaGrid extends StatelessWidget {
  const CommunityMediaGrid({super.key, required this.post});

  final CommunityPost post;

  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final media = post.media;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        Widget tile(int i, double width, double height, {int more = 0}) => SizedBox(
              width: width,
              height: height,
              child: _MediaTile(post: post, index: i, more: more),
            );

        switch (media.length) {
          case 1:
            final aspect = (media.first.aspect ?? 4 / 3).clamp(0.8, 1.91);
            return tile(0, w, w / aspect);
          case 2:
            final s = (w - _gap) / 2;
            return Row(children: [tile(0, s, s), const SizedBox(width: _gap), tile(1, s, s)]);
          case 3:
            final h = w * 0.68;
            final big = (w - _gap) * 2 / 3;
            final small = w - _gap - big;
            final half = (h - _gap) / 2;
            return Row(children: [
              tile(0, big, h),
              const SizedBox(width: _gap),
              Column(children: [tile(1, small, half), const SizedBox(height: _gap), tile(2, small, half)]),
            ]);
          case 4:
            final s = (w - _gap) / 2;
            return Column(children: [
              Row(children: [tile(0, s, s), const SizedBox(width: _gap), tile(1, s, s)]),
              const SizedBox(height: _gap),
              Row(children: [tile(2, s, s), const SizedBox(width: _gap), tile(3, s, s)]),
            ]);
          default:
            final top = (w - _gap) / 2;
            final bottom = (w - 2 * _gap) / 3;
            return Column(children: [
              Row(children: [tile(0, top, top), const SizedBox(width: _gap), tile(1, top, top)]),
              const SizedBox(height: _gap),
              Row(children: [
                tile(2, bottom, bottom),
                const SizedBox(width: _gap),
                tile(3, bottom, bottom),
                const SizedBox(width: _gap),
                tile(4, bottom, bottom, more: media.length - 5),
              ]),
            ]);
        }
      },
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.post, required this.index, this.more = 0});

  final CommunityPost post;
  final int index;

  /// Shown as "+N" over the last tile when there are more items.
  final int more;

  @override
  Widget build(BuildContext context) {
    final m = post.media[index];
    final still = m.stillUrl;
    final placeholder = ColoredBox(color: AppColors.photoPlaceholder);
    return PressScale(
      pressedScale: 0.97,
      onTap: () => CommunityMediaViewer.open(context, post: post, index: index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: CommunityMediaViewer.heroTag(post.id, index),
            child: still == null
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF1B1C1F), Color(0xFF34363B)]),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: still,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 220),
                    placeholder: (_, __) => Shimmer.fromColors(
                      baseColor: AppColors.photoPlaceholder,
                      highlightColor: AppColors.surfaceRaised,
                      child: placeholder,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.photoPlaceholder,
                      alignment: Alignment.center,
                      child: Icon(Icons.broken_image_outlined, color: AppColors.mut),
                    ),
                  ),
          ),
          if (m.isVideo && more == 0)
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.42),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 1.5),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
              ),
            ),
          if (m.isVideo && m.duration != null && more == 0)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(_duration(m.duration!),
                    style: communityText(size: 11.5, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          if (more > 0)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('+$more',
                      style: communityText(size: 26, weight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _duration(double s) {
    final t = s.round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }
}

/// Shimmering placeholder card while the feed loads.
class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double w, double h, {double r = 8}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(r)),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Shimmer.fromColors(
        baseColor: AppColors.line,
        highlightColor: AppColors.surfaceRaised,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                block(42, 42, r: 21),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  block(90, 13),
                  const SizedBox(height: 7),
                  block(130, 10),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                block(double.infinity, 11),
                const SizedBox(height: 8),
                block(200, 11),
              ]),
            ),
            AspectRatio(aspectRatio: 1.5, child: block(double.infinity, double.infinity, r: 0)),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
