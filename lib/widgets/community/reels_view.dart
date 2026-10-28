import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';

import '../../services/community_service.dart';
import 'community_ui.dart';

/// Content tab: vertical 9:16 videos, swiped up/down like TikTok.
///
/// Each reel sits in a rounded 9:16 card with room on every side, so the
/// whole video is always visible and nothing is drawn over it. Behind the
/// card is a soft glow made from the reel's own colours, which fades into
/// the next reel's colours as you swipe. The caption and Share button sit
/// under the card.
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

// ── Sizes shared by the reel, the caption and the loading skeleton ───────
const double _kCaptionSize = 14;
const double _kCaptionLine = 1.42;
const double _kCardRadius = 22;
const double _kShareSize = 44;

/// Where the card, progress line and caption row go for a given screen.
///
/// The card is always exactly 9:16 and as big as the space allows: below
/// the back button, above the caption row, at least 16 px from each side.
/// Taller text (accessibility text size) makes the caption row taller and
/// the card a little smaller, so nothing ever overflows.
class _ReelLayout {
  const _ReelLayout({
    required this.card,
    required this.captionTop,
    required this.captionH,
    required this.rowLeft,
    required this.rowW,
  });

  final Rect card;
  final double captionTop;
  final double captionH;
  final double rowLeft;
  final double rowW;

  static const double _gapUnderCard = 14;

  static _ReelLayout of(BuildContext context, Size size, double bottomInset) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final lineH = MediaQuery.textScalerOf(context).scale(_kCaptionSize) * _kCaptionLine;
    final captionH = math.max(_kShareSize + 2, lineH * 2 + 6);

    // Back button is at safeTop + 8 and 42 tall.
    final top = safeTop + 58;
    final bottom = size.height - bottomInset - captionH - _gapUnderCard;
    final availH = math.max(0.0, bottom - top);
    final maxW = math.max(0.0, size.width - 32);

    var h = availH;
    var w = h * 9 / 16;
    if (w > maxW) {
      w = maxW;
      h = w * 16 / 9;
    }
    final card = Rect.fromLTWH((size.width - w) / 2, top + (availH - h) / 2, w, h);

    // On very small cards (landscape) the caption row stays readable.
    final rowW = math.max(w, math.min(size.width - 32, 220.0));
    return _ReelLayout(
      card: card,
      captionTop: card.bottom + _gapUnderCard,
      captionH: captionH,
      rowLeft: (size.width - rowW) / 2,
      rowW: rowW,
    );
  }
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

  /// Browsers only autoplay muted videos, so the website starts muted and
  /// the first tap turns the sound on. The app plays with sound.
  bool _muted = kIsWeb;
  bool _soundFlash = false;
  Timer? _soundFlashTimer;
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
    _soundFlashTimer?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _page.dispose();
    super.dispose();
  }

  /// Scroll position in pages (1.5 = halfway between reel 1 and reel 2).
  double get _pageValue {
    if (_page.hasClients && _page.position.hasContentDimensions) {
      return _page.page ?? _index.toDouble();
    }
    return _index.toDouble();
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

  void _onCardTap() {
    final c = _controllers[_index];
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.lightImpact();

    // Website: the first tap turns the sound on instead of pausing.
    if (_muted) {
      setState(() {
        _muted = false;
        _soundFlash = true;
      });
      for (final v in _controllers.values) {
        v.setVolume(1);
      }
      _soundFlashTimer?.cancel();
      _soundFlashTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _soundFlash = false);
      });
      return;
    }

    setState(() => _userPaused = !_userPaused);
    _applyPlayback();
  }

  void _retry(int i) {
    setState(() => _failed.remove(i));
    _syncControllers();
  }

  // ── UI ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final showReels = !_loading && _error == null && _reels.isNotEmpty;

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
          itemBuilder: (context, i) => AnimatedBuilder(
            animation: _page,
            // The reel leaving the screen shrinks a touch; the one arriving
            // grows into place.
            builder: (context, child) {
              final d = (_pageValue - i).abs().clamp(0.0, 1.0);
              return Transform.scale(scale: 1 - 0.06 * d, child: child);
            },
            child: _ReelPage(
              key: ValueKey(_reels[i].id),
              reel: _reels[i],
              controller: _controllers[i],
              failed: _failed.contains(i),
              isCurrent: i == _index,
              paused: _userPaused && i == _index,
              soundFlash: _soundFlash && i == _index,
              bottomInset: widget.bottomInset,
              onTap: _onCardTap,
              onRetry: () => _retry(i),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        // The glowing background.
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOut,
            child: showReels
                ? AnimatedBuilder(
                    key: const ValueKey('ambient'),
                    animation: _page,
                    builder: (context, _) => _AmbientBackdrop(reels: _reels, page: _pageValue),
                  )
                : const _FallbackBackdrop(key: ValueKey('fallback')),
          ),
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            child: KeyedSubtree(key: ValueKey('$_loading|$_error|${_reels.isEmpty}'), child: body),
          ),
        ),
        // Back is the only button at the top.
        Positioned(
          top: top + 8,
          left: 16,
          child: GlassCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    );
  }
}

// ── Background ───────────────────────────────────────────────────────────

/// Saturates the colours and darkens them, so the glow is rich but never
/// competes with the video.
ColorFilter _saturateAndDim(double saturation, double brightness) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final s = saturation, b = brightness;
  final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  return ColorFilter.matrix(<double>[
    (sr + s) * b, sg * b, sb * b, 0, 0, //
    sr * b, (sg + s) * b, sb * b, 0, 0, //
    sr * b, sg * b, (sb + s) * b, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}

final ColorFilter _ambientFilter = _saturateAndDim(1.6, 0.48);

/// Blurred, darkened copy of the reel's cover frame filling the screen.
/// While swiping, the current and next reel's colours cross-fade.
class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({required this.reels, required this.page});

  final List<CommunityReel> reels;
  final double page;

  @override
  Widget build(BuildContext context) {
    final last = reels.length - 1;
    final p = page.clamp(0.0, last.toDouble());
    final a = p.floor();
    final b = math.min(a + 1, last);
    final t = p - a;
    return Stack(
      fit: StackFit.expand,
      children: [
        const _FallbackBackdrop(),
        ClipRect(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: ColorFiltered(
              colorFilter: _ambientFilter,
              child: Transform.scale(
                scale: 1.25,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _AmbientImage(url: reels[a].posterUrl),
                    if (b != a && t > 0.002) Opacity(opacity: t, child: _AmbientImage(url: reels[b].posterUrl)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const _Vignette(),
      ],
    );
  }
}

/// A tiny (32 px wide) decode of the cover — it gets blurred anyway, so
/// this keeps the background cheap.
class _AmbientImage extends StatelessWidget {
  const _AmbientImage({required this.url, this.tint});

  final String? url;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return const SizedBox.expand();
    return Image(
      image: ResizeImage(CachedNetworkImageProvider(u), width: 32),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      color: tint,
      colorBlendMode: tint == null ? null : BlendMode.modulate,
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    );
  }
}

/// Dark background with a faint gold and purple glow — used while loading
/// and when a reel has no cover frame.
class _FallbackBackdrop extends StatelessWidget {
  const _FallbackBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFF0D0D10)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.9, -0.85),
                radius: 1.1,
                colors: [Color(0x33E3B23C), Color(0x00E3B23C)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.95, 0.75),
                radius: 1.2,
                colors: [Color(0x407B3FE4), Color(0x007B3FE4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Darker edges and a little shade at the top and bottom so the status bar,
/// back button and caption stay readable on any colours.
class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.15),
                radius: 1.15,
                colors: [Color(0x00000000), Color(0x99000000)],
                stops: [0.4, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x40000000), Color(0x00000000), Color(0x00000000), Color(0x73000000)],
                stops: [0, 0.25, 0.6, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── One reel ─────────────────────────────────────────────────────────────

/// One reel: the 9:16 card, its glow, the progress line, caption and Share.
class _ReelPage extends StatelessWidget {
  const _ReelPage({
    super.key,
    required this.reel,
    required this.controller,
    required this.failed,
    required this.isCurrent,
    required this.paused,
    required this.soundFlash,
    required this.bottomInset,
    required this.onTap,
    required this.onRetry,
  });

  final CommunityReel reel;
  final VideoPlayerController? controller;
  final bool failed;
  final bool isCurrent;
  final bool paused;
  final bool soundFlash;
  final double bottomInset;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final poster = reel.posterUrl;
    final caption = reel.caption.trim();

    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final l = _ReelLayout.of(context, size, bottomInset);
        final card = l.card;
        if (card.width < 40 || card.height < 40) return const SizedBox.expand();
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final captionW = math.max(0.0, l.rowW - _kShareSize - 10);

        return Stack(
          children: [
            // Soft glow in the reel's own colours, hugging the card.
            if (poster != null)
              Positioned.fromRect(
                rect: card.inflate(16),
                child: IgnorePointer(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26, tileMode: ui.TileMode.decal),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: _AmbientImage(url: poster, tint: const Color(0x8CFFFFFF)),
                    ),
                  ),
                ),
              ),

            // The card.
            Positioned.fromRect(
              rect: card,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(_kCardRadius)),
                  boxShadow: [BoxShadow(color: Color(0x8C000000), blurRadius: 50, offset: Offset(0, 22))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kCardRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0xFF16161A)),
                      // Cover frame first, so there's never a black flash.
                      if (poster != null)
                        CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          memCacheWidth: (card.width * dpr).round(),
                          fadeInDuration: const Duration(milliseconds: 180),
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      if (c != null) _ReelVideo(controller: c),
                      Positioned.fill(
                        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
                      ),
                      if (c != null && !failed)
                        Center(child: _BufferingAndPause(controller: c, paused: paused, soundFlash: soundFlash)),
                      if (failed) Center(child: _RetryChip(onTap: onRetry)),
                      // Hairline edge.
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(_kCardRadius)),
                            border: Border.fromBorderSide(BorderSide(color: Color(0x24FFFFFF))),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Progress line just under the card (drag to seek).
            if (c != null)
              Positioned(
                left: card.left + 4,
                top: card.bottom,
                width: card.width - 8,
                height: 14,
                child: _ReelProgress(controller: c),
              ),

            // Caption — grows upward on glass when "more" is tapped.
            if (caption.isNotEmpty && captionW > 0)
              Positioned(
                left: l.rowLeft,
                width: captionW,
                bottom: size.height - (l.captionTop + l.captionH),
                child: _ShowWhenCurrent(
                  visible: isCurrent,
                  child: _ReelCaption(
                    caption: caption,
                    width: captionW,
                    rowHeight: l.captionH,
                    maxOpenHeight: math.max(80.0, card.height * 0.62),
                  ),
                ),
              ),

            // Share.
            Positioned(
              left: l.rowLeft + l.rowW - _kShareSize,
              top: l.captionTop + (l.captionH - _kShareSize) / 2,
              child: _ShowWhenCurrent(
                visible: isCurrent,
                child: Builder(
                  builder: (btnContext) => GlassCircleButton(
                    icon: Icons.share_rounded,
                    iconSize: 20,
                    size: _kShareSize,
                    tooltip: 'Share',
                    onTap: () => CommunityService.share(
                      btnContext,
                      text: reel.caption,
                      link: CommunityService.reelLink(reel.id),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Caption and Share of the reel on screen fade + rise in; the ones on
/// the reel being swiped away fade out.
class _ShowWhenCurrent extends StatelessWidget {
  const _ShowWhenCurrent({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 0.25),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(ignoring: !visible, child: child),
      ),
    );
  }
}

/// The video itself, filling the 9:16 card; fades in over the cover frame.
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

/// Spinner while buffering, a big play icon while paused by a tap, and a
/// quick speaker pop when the website turns the sound on.
class _BufferingAndPause extends StatelessWidget {
  const _BufferingAndPause({required this.controller, required this.paused, required this.soundFlash});

  final VideoPlayerController controller;
  final bool paused;
  final bool soundFlash;

  @override
  Widget build(BuildContext context) {
    Widget bubble(bool show, IconData icon, double iconSize) => AnimatedScale(
          scale: show ? 1 : 1.5,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.38),
              ),
              child: Icon(icon, color: Colors.white, size: iconSize),
            ),
          ),
        );

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
              bubble(paused, Icons.play_arrow_rounded, 52),
              bubble(soundFlash && !paused, Icons.volume_up_rounded, 38),
            ],
          );
        },
      ),
    );
  }
}

class _RetryChip extends StatelessWidget {
  const _RetryChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Scales down instead of overflowing if the card is ever tiny.
    return Padding(
      padding: const EdgeInsets.all(12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: PressScale(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    child: Text(
                      "Couldn't play — tap to retry",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: communityText(size: 14, weight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two lines with "… more" at the end. Tapping opens the full caption on a
/// frosted panel that grows upward over the bottom of the card; tapping
/// the panel closes it.
class _ReelCaption extends StatefulWidget {
  const _ReelCaption({
    required this.caption,
    required this.width,
    required this.rowHeight,
    required this.maxOpenHeight,
  });

  final String caption;
  final double width;
  final double rowHeight;
  final double maxOpenHeight;

  @override
  State<_ReelCaption> createState() => _ReelCaptionState();
}

class _ReelCaptionState extends State<_ReelCaption> {
  bool _open = false;

  static final TextStyle _style = communityText(
    size: _kCaptionSize,
    weight: FontWeight.w500,
    color: const Color(0xEBFFFFFF),
    height: _kCaptionLine,
  );
  static final TextStyle _moreStyle = communityText(
    size: _kCaptionSize,
    weight: FontWeight.w800,
    color: Colors.white70,
    height: _kCaptionLine,
  );

  static String _trimEnd(String s) => s.replaceFirst(RegExp(r'[\s.,;:!?\-–—]+$'), '');

  /// The longest start of the caption that fits in two lines with
  /// "… more" after it.
  ({String text, bool long}) _measure(TextStyle style, TextStyle more, TextScaler scaler, TextDirection dir) {
    final caption = widget.caption;
    final maxW = widget.width;
    TextPainter lay(InlineSpan span) =>
        TextPainter(text: span, maxLines: 2, textDirection: dir, textScaler: scaler)..layout(maxWidth: maxW);

    final full = lay(TextSpan(text: caption, style: style));
    final long = full.didExceedMaxLines;
    full.dispose();
    if (!long) return (text: caption, long: false);

    final chars = caption.characters;
    var lo = 0;
    var hi = chars.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      final p = lay(TextSpan(
        style: style,
        children: [
          TextSpan(text: '${_trimEnd(chars.take(mid).toString())}… '),
          TextSpan(text: 'more', style: more),
        ],
      ));
      final fits = !p.didExceedMaxLines;
      p.dispose();
      if (fits) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (text: _trimEnd(chars.take(lo).toString()), long: true);
  }

  void _setOpen(bool v) {
    HapticFeedback.selectionClick();
    setState(() => _open = v);
  }

  @override
  Widget build(BuildContext context) {
    // Same style the Text widgets end up with, so the measuring is exact.
    final style = DefaultTextStyle.of(context).style.merge(_style);
    final more = style.merge(_moreStyle);
    final m = _measure(style, more, MediaQuery.textScalerOf(context), Directionality.of(context));

    final closed = SizedBox(
      key: const ValueKey('closed'),
      width: widget.width,
      height: widget.rowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: m.long ? () => _setOpen(true) : null,
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(text: m.long ? '${m.text}… ' : m.text),
                if (m.long) TextSpan(text: 'more', style: more),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.clip,
          ),
        ),
      ),
    );

    final open = GestureDetector(
      key: const ValueKey('open'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _setOpen(false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: widget.width,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: const Color(0xA30E0E10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxOpenHeight),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text.rich(
                  TextSpan(
                    style: style,
                    children: [
                      TextSpan(text: '${widget.caption} '),
                      TextSpan(text: 'less', style: more),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomLeft,
          children: [...previous, if (current != null) current],
        ),
        child: _open ? open : closed,
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 5),
        colors: VideoProgressColors(
          playedColor: Colors.white,
          bufferedColor: Colors.white.withValues(alpha: 0.32),
          backgroundColor: Colors.white.withValues(alpha: 0.16),
        ),
      ),
    );
  }
}

/// Shimmering card + caption shapes in the same place as a real reel.
class _ReelsSkeleton extends StatelessWidget {
  const _ReelsSkeleton({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final l = _ReelLayout.of(context, box.biggest, bottomInset);
        final card = l.card;
        if (card.width < 40 || card.height < 40) return const SizedBox.expand();

        Widget block(double w, double h, double r) => Container(
              width: math.max(0.0, w),
              height: h,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(r)),
            );
        final lineW = math.max(0.0, l.rowW - _kShareSize - 24);

        return Shimmer.fromColors(
          baseColor: const Color(0x1FFFFFFF),
          highlightColor: const Color(0x3DFFFFFF),
          child: Stack(
            children: [
              Positioned.fromRect(rect: card, child: block(card.width, card.height, _kCardRadius)),
              Positioned(
                left: l.rowLeft,
                top: l.captionTop + (l.captionH - 31) / 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(math.min(220.0, lineW), 11, 6),
                    const SizedBox(height: 9),
                    block(math.min(150.0, lineW * 0.7), 11, 6),
                  ],
                ),
              ),
              Positioned(
                left: l.rowLeft + l.rowW - _kShareSize,
                top: l.captionTop + (l.captionH - _kShareSize) / 2,
                child: block(_kShareSize, _kShareSize, _kShareSize / 2),
              ),
            ],
          ),
        );
      },
    );
  }
}
