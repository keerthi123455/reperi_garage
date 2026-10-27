import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';

import '../../services/community_service.dart';
import 'community_ui.dart';

/// Content tab: full-screen vertical videos, swiped up/down like TikTok.
///
/// Only three videos are ever loaded — the one on screen and its two
/// neighbours — so the next swipe starts instantly without holding every
/// video in memory. Tap pauses / plays. The current video stops whenever
/// this tab, the page or the app isn't in front ([active]).
class ReelsView extends StatefulWidget {
  const ReelsView({
    super.key,
    required this.active,
    required this.bottomInset,
    this.focusReelId,
  });

  /// True while the Content tab is visible and the app is in front.
  final bool active;

  /// Space at the bottom taken by the floating tab bar.
  final double bottomInset;

  /// Opened from a shared link: show this reel first.
  final String? focusReelId;

  @override
  State<ReelsView> createState() => _ReelsViewState();
}

class _ReelsViewState extends State<ReelsView> {
  static const int _pageSize = 12;

  final PageController _page = PageController();
  final List<CommunityReel> _reels = [];
  final Map<int, VideoPlayerController> _controllers = {};
  final Set<int> _failed = {};

  int _index = 0;
  int _offset = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _end = false;
  String? _error;

  /// Browsers only autoplay muted videos, so the website starts muted.
  bool _muted = kIsWeb;
  bool _userPaused = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ReelsView old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _applyPlayback();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _page.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────
  Future<void> _load() async {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _failed.clear();
    if (_error != null || !_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await CommunityService.fetchReels(limit: _pageSize);
      _offset = list.length;
      _end = list.length < _pageSize;
      final focusId = widget.focusReelId;
      if (focusId != null) {
        CommunityReel? focus;
        for (final r in list) {
          if (r.id == focusId) focus = r;
        }
        focus ??= await CommunityService.fetchReel(focusId);
        if (focus != null) {
          final f = focus;
          list
            ..removeWhere((r) => r.id == f.id)
            ..insert(0, f);
        }
      }
      if (!mounted) return;
      setState(() {
        _reels
          ..clear()
          ..addAll(list);
        _index = 0;
        _userPaused = false;
        _loading = false;
      });
      if (_page.hasClients) _page.jumpToPage(0);
      _syncControllers();
    } catch (e) {
      debugPrint('Community reels not loaded: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Check your internet connection and try again.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _end || _loading) return;
    _loadingMore = true;
    try {
      final more = await CommunityService.fetchReels(offset: _offset, limit: _pageSize);
      _offset += more.length;
      _end = more.length < _pageSize;
      final have = _reels.map((r) => r.id).toSet();
      if (!mounted) return;
      setState(() => _reels.addAll(more.where((r) => !have.contains(r.id))));
      _syncControllers();
    } catch (_) {
      // Try again on the next swipe.
    } finally {
      _loadingMore = false;
    }
  }

  // ── Video controllers ─────────────────────────────────────────────────
  void _syncControllers() {
    if (_reels.isEmpty) return;
    final keep = <int>{_index - 1, _index, _index + 1}.where((i) => i >= 0 && i < _reels.length).toSet();
    for (final i in _controllers.keys.toList()) {
      if (!keep.contains(i)) _controllers.remove(i)?.dispose();
    }
    // The visible one first, so it gets the network before its neighbours.
    for (final i in [_index, _index + 1, _index - 1]) {
      if (keep.contains(i) && !_controllers.containsKey(i) && !_failed.contains(i)) _create(i);
    }
    _applyPlayback();
  }

  void _create(int i) {
    final c = VideoPlayerController.networkUrl(
      Uri.parse(_reels[i].videoUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controllers[i] = c;
    c.initialize().then((_) async {
      if (!mounted || _controllers[i] != c) return;
      await c.setLooping(true);
      await c.setVolume(_muted ? 0 : 1);
      if (!mounted || _controllers[i] != c) return;
      setState(() {});
      _applyPlayback();
    }).catchError((Object e) {
      debugPrint('Reel $i did not load: $e');
      if (!mounted || _controllers[i] != c) return;
      _controllers.remove(i);
      c.dispose();
      setState(() => _failed.add(i));
    });
  }

  void _applyPlayback() {
    _controllers.forEach((i, c) {
      if (!c.value.isInitialized) return;
      final play = widget.active && i == _index && !_userPaused;
      if (play) {
        if (!c.value.isPlaying) c.play();
      } else {
        if (c.value.isPlaying) c.pause();
        // Swiping back to a reel starts it from the beginning.
        if (i != _index && c.value.position > Duration.zero) c.seekTo(Duration.zero);
      }
    });
  }

  void _onPage(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _index = i;
      _userPaused = false;
    });
    _syncControllers();
    if (i >= _reels.length - 3) _loadMore();
  }

  void _togglePause() {
    final c = _controllers[_index];
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.lightImpact();
    setState(() => _userPaused = !_userPaused);
    _applyPlayback();
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    setState(() => _muted = !_muted);
    for (final c in _controllers.values) {
      c.setVolume(_muted ? 0 : 1);
    }
  }

  void _retry(int i) {
    setState(() => _failed.remove(i));
    _syncControllers();
  }

  // ── UI ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    Widget body;
    if (_loading) {
      body = _ReelsSkeleton(bottomInset: widget.bottomInset);
    } else if (_error != null) {
      body = CommunityMessage(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load reels",
        body: _error!,
        onDark: true,
        action: 'Try again',
        onAction: _load,
      );
    } else if (_reels.isEmpty) {
      body = const CommunityMessage(
        icon: Icons.smart_display_rounded,
        title: 'No reels yet',
        body: 'Videos of our latest work will show up here soon.',
        onDark: true,
      );
    } else {
      body = ScrollConfiguration(
        behavior: const CommunityScrollBehavior(),
        child: PageView.builder(
          controller: _page,
          scrollDirection: Axis.vertical,
          itemCount: _reels.length,
          onPageChanged: _onPage,
          itemBuilder: (context, i) => _ReelPage(
            key: ValueKey(_reels[i].id),
            reel: _reels[i],
            controller: _controllers[i],
            failed: _failed.contains(i),
            isCurrent: i == _index,
            paused: _userPaused && i == _index,
            bottomInset: widget.bottomInset,
            onTap: _togglePause,
            onRetry: () => _retry(i),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              child: KeyedSubtree(key: ValueKey('$_loading|$_error|${_reels.isEmpty}'), child: body),
            ),
          ),
          // Back · title · sound
          Positioned(
            top: top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                GlassCircleButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 18,
                  tooltip: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'Community',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: communityText(
                        size: 17,
                        weight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                        shadows: const [Shadow(color: Colors.black45, blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: GlassCircleButton(
                    key: ValueKey(_muted),
                    icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    tooltip: _muted ? 'Turn sound on' : 'Mute',
                    onTap: _reels.isEmpty ? null : _toggleMute,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One reel, filling the screen.
class _ReelPage extends StatelessWidget {
  const _ReelPage({
    super.key,
    required this.reel,
    required this.controller,
    required this.failed,
    required this.isCurrent,
    required this.paused,
    required this.bottomInset,
    required this.onTap,
    required this.onRetry,
  });

  final CommunityReel reel;
  final VideoPlayerController? controller;
  final bool failed;
  final bool isCurrent;
  final bool paused;
  final double bottomInset;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cover frame first, so there's never a black flash.
        if (reel.posterUrl != null)
          CachedNetworkImage(
            imageUrl: reel.posterUrl!,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 180),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        if (c != null) _ReelVideo(controller: c),
        // Shade at the top and bottom keeps text readable on any video.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x80000000), Color(0x00000000), Color(0x00000000), Color(0xC7000000)],
                stops: [0, 0.2, 0.5, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
        ),
        if (c != null && !failed) Center(child: _BufferingAndPause(controller: c, paused: paused)),
        if (failed)
          Center(
            child: PressScale(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text("Couldn't play — tap to retry",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: communityText(size: 14, weight: FontWeight.w700, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Avatar + Share, on the right.
        Positioned(
          right: 10,
          bottom: bottomInset + 56,
          child: AnimatedSlide(
            offset: isCurrent ? Offset.zero : const Offset(0.4, 0),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: isCurrent ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CommunityAvatar(size: 48),
                  const SizedBox(height: 26),
                  Builder(
                    builder: (btnContext) => _RailButton(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      onTap: () => CommunityService.share(
                        btnContext,
                        text: reel.caption,
                        link: CommunityService.reelLink(reel.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Name + caption, bottom-left.
        Positioned(
          left: 16,
          right: 86,
          bottom: bottomInset + 26,
          child: AnimatedSlide(
            offset: isCurrent ? Offset.zero : const Offset(0, 0.25),
            duration: const Duration(milliseconds: 460),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: isCurrent ? 1 : 0,
              duration: const Duration(milliseconds: 320),
              child: _ReelCaption(reel: reel),
            ),
          ),
        ),
        // Progress (drag to seek).
        if (c != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: bottomInset + 4,
            child: _ReelProgress(controller: c),
          ),
      ],
    );
  }
}

/// The video itself, cropped to fill the screen; fades in over the cover.
class _ReelVideo extends StatelessWidget {
  const _ReelVideo({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final ready = v.isInitialized && v.size.width > 0 && v.size.height > 0;
        return AnimatedOpacity(
          opacity: ready ? 1 : 0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          child: ready
              ? ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: v.size.width,
                      height: v.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                )
              : const SizedBox.expand(),
        );
      },
    );
  }
}

/// Spinner while buffering; a big play icon while paused by a tap.
class _BufferingAndPause extends StatelessWidget {
  const _BufferingAndPause({required this.controller, required this.paused});

  final VideoPlayerController controller;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, v, _) {
          final loading = !v.isInitialized || (v.isBuffering && !paused);
          return Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: loading ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                ),
              ),
              AnimatedScale(
                scale: paused ? 1 : 1.5,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: paused ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.38),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 52),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PressScale(
        onTap: onTap,
        pressedScale: 0.8,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 34, shadows: const [Shadow(color: Colors.black54, blurRadius: 10)]),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: communityText(
                    size: 13,
                    weight: FontWeight.w800,
                    color: Colors.white,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Reperi ✓ · 2d" and the caption, which expands on tap.
class _ReelCaption extends StatefulWidget {
  const _ReelCaption({required this.reel});

  final CommunityReel reel;

  @override
  State<_ReelCaption> createState() => _ReelCaptionState();
}

class _ReelCaptionState extends State<_ReelCaption> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black54, blurRadius: 8)];
    final caption = widget.reel.caption.trim();
    final style = communityText(size: 14.5, weight: FontWeight.w500, color: Colors.white, height: 1.4, shadows: shadow);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Flexible(child: CommunityName(color: Colors.white, size: 16, shadows: shadow)),
            const SizedBox(width: 6),
            Text('· ${communityTimeAgo(widget.reel.createdAt, short: true)}',
                maxLines: 1,
                style: communityText(
                    size: 13, weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.78), shadows: shadow)),
          ],
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, box) {
              final painter = TextPainter(
                text: TextSpan(text: caption, style: style),
                maxLines: 2,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: box.maxWidth);
              final long = painter.didExceedMaxLines;
              painter.dispose();
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: long ? () => setState(() => _open = !_open) : null,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    // Long captions scroll instead of covering the video.
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.32),
                    child: SingleChildScrollView(
                      physics: _open ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            caption,
                            maxLines: _open ? null : 2,
                            overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
                            style: style,
                          ),
                          if (long)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(_open ? 'less' : 'more',
                                  style: communityText(
                                      size: 14, weight: FontWeight.w800, color: Colors.white70, shadows: shadow)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Thin progress line you can drag to seek.
class _ReelProgress extends StatelessWidget {
  const _ReelProgress({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: VideoProgressIndicator(
        controller,
        allowScrubbing: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        colors: VideoProgressColors(
          playedColor: Colors.white,
          bufferedColor: Colors.white.withValues(alpha: 0.32),
          backgroundColor: Colors.white.withValues(alpha: 0.16),
        ),
      ),
    );
  }
}

/// Dark shimmer in the shape of a reel while the first list loads.
class _ReelsSkeleton extends StatelessWidget {
  const _ReelsSkeleton({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(h / 2)),
        );
    return Shimmer.fromColors(
      baseColor: const Color(0xFF1B1C1F),
      highlightColor: const Color(0xFF34363B),
      child: Stack(
        children: [
          Positioned(
            right: 18,
            bottom: bottomInset + 64,
            child: Column(children: [bar(48, 48), const SizedBox(height: 28), bar(36, 36)]),
          ),
          Positioned(
            left: 16,
            bottom: bottomInset + 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(120, 16), const SizedBox(height: 12), bar(230, 12), const SizedBox(height: 8), bar(180, 12)],
            ),
          ),
        ],
      ),
    );
  }
}
