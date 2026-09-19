import 'dart:async';

import 'package:flutter/material.dart';

import 'dot_indicator_row.dart';
import 'placeholder_box.dart';

/// One slide of [AutoBannerStrip].
class AutoBannerItem {
  const AutoBannerItem({
    required this.assetPath,
    this.badgeLabel,
    this.onTap,
  });

  final String assetPath;

  /// e.g. "COMING SOON" — shown as a dark overlay badge over the slide.
  final String? badgeLabel;

  final VoidCallback? onTap;
}

/// How far into [_kVirtualSpan] copies of the real list the controller
/// starts — lets auto-advance always call `animateToPage(page + 1)` (always
/// moving the same direction) without ever needing to snap backward when it
/// loops from the last slide to the first, and leaves plenty of room for a
/// manual swipe in either direction too.
const int _kVirtualSpan = 10000;

/// A banner strip that keeps the centered slide large while its neighbours
/// peek in from either side, and auto-advances every [interval], looping
/// forever in one continuous direction — the flat "2D" counterpart to the
/// 3D coverflow higher up the Home screen. Still swipeable by hand — auto-
/// advance pauses on touch and stays paused for
/// [_AutoBannerStripState._resumeDelay] after the last touch ends, so it
/// doesn't yank the slide away mid-look or fight a series of quick manual
/// swipes.
class AutoBannerStrip extends StatefulWidget {
  const AutoBannerStrip({
    super.key,
    required this.items,
    this.aspectRatio = 1280 / 720,
    this.viewportFraction = 0.823,
    this.interval = const Duration(milliseconds: 1500),
  });

  final List<AutoBannerItem> items;
  final double aspectRatio;

  /// How much of the strip's width the centered slide occupies — the rest
  /// is split between the previous/next slides peeking in from the sides.
  final double viewportFraction;
  final Duration interval;

  @override
  State<AutoBannerStrip> createState() => _AutoBannerStripState();
}

class _AutoBannerStripState extends State<AutoBannerStrip> {
  late final PageController _controller;
  Timer? _timer;
  // Auto-advance stays paused for this long after the last touch — not
  // just while a finger is actually down — so someone dragging through a
  // couple of slides by hand isn't fighting the auto-advance the moment
  // they lift off between swipes.
  static const Duration _resumeDelay = Duration(seconds: 3);
  Timer? _resumeTimer;
  int _virtualPage = 0;
  double _pageValue = 0;
  bool _paused = false;

  int get _realCount => widget.items.length;

  @override
  void initState() {
    super.initState();
    _virtualPage = (_kVirtualSpan * _realCount) ~/ 2;
    _pageValue = _virtualPage.toDouble();
    _controller = PageController(
      initialPage: _virtualPage,
      viewportFraction: widget.viewportFraction,
    )..addListener(_onScroll);
    _startTimer();
  }

  void _onScroll() {
    final page = _controller.page;
    if (page != null) setState(() => _pageValue = page);
  }

  void _startTimer() {
    _timer?.cancel();
    if (_realCount <= 1) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!_paused) _advance();
    });
  }

  void _advance() {
    if (!mounted || !_controller.hasClients) return;
    _virtualPage++;
    _controller.animateToPage(
      _virtualPage,
      // A slightly longer, decelerating curve reads as a deliberate glide
      // rather than a mechanical snap.
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutQuint,
    );
  }

  /// Called on every touch-down — pauses immediately and cancels any
  /// countdown already running, so a second touch inside the 3-second
  /// window restarts the wait instead of resuming mid-count.
  void _onInteractionStart() {
    _paused = true;
    _resumeTimer?.cancel();
  }

  /// Called on touch-up/cancel — starts (or restarts) the 3-second
  /// countdown before auto-advance is allowed to resume.
  void _onInteractionEnd() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeDelay, () {
      if (mounted) _paused = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resumeTimer?.cancel();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The centered slide's own box — everything narrower than the full
        // strip width is what lets the previous/next slides peek in at the
        // sides instead of the current slide filling edge to edge.
        final slideWidth = constraints.maxWidth * widget.viewportFraction;
        final slideHeight = slideWidth / widget.aspectRatio;

        return Column(
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _onInteractionStart(),
              onPointerUp: (_) => _onInteractionEnd(),
              onPointerCancel: (_) => _onInteractionEnd(),
              child: SizedBox(
                height: slideHeight,
                child: PageView.builder(
                  controller: _controller,
                  clipBehavior: Clip.none,
                  onPageChanged: (i) => _virtualPage = i,
                  itemBuilder: (context, index) {
                    final item = widget.items[index % _realCount];

                    // Distance from the currently-settled page — 0 when this
                    // slide is centered, growing toward 1 as it slides off.
                    // Driving a subtle scale + fade off that (rather than a
                    // hard cut) is what gives the transition its glide.
                    final distance = (_pageValue - index).abs().clamp(0.0, 1.0);
                    final scale = 1.0 - (distance * 0.12);
                    final opacity = (1.0 - (distance * 0.45)).clamp(0.0, 1.0);

                    final slide = Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Transform.scale(
                          scale: scale,
                          child: Opacity(
                            opacity: opacity,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.asset(
                                      item.assetPath,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => PlaceholderBox(
                                        label: item.assetPath.split('/').last,
                                        borderRadius: 0,
                                      ),
                                    ),
                                    if (item.badgeLabel != null)
                                      Positioned.fill(
                                        child: Container(
                                          color: Colors.black.withOpacity(0.45),
                                          alignment: Alignment.center,
                                          child: Text(
                                            item.badgeLabel!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );

                    if (item.onTap == null) return slide;
                    return GestureDetector(onTap: item.onTap, child: slide);
                  },
                ),
              ),
            ),
            if (_realCount > 1) ...[
              const SizedBox(height: 10),
              DotIndicatorRow(count: _realCount, activeIndex: _virtualPage % _realCount),
            ],
          ],
        );
      },
    );
  }
}
