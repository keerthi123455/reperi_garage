import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/community_service.dart';
import '../theme/app_colors.dart';
import '../widgets/community/community_ui.dart';
import '../widgets/community/recent_work_view.dart';
import '../widgets/community/reels_view.dart';

/// Community — opened from the purple circle in the Home hub, or from a
/// shared reperi.in/community/... link.
///
/// Two tabs in a floating bar at the bottom:
///   • Content      — reels, full screen, swiped like TikTok
///   • Recent work  — posts of photos/videos with a brief, like Facebook
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, this.link});

  /// Set when opened from a shared link (which tab, which reel/post first).
  final CommunityLink? link;

  /// Grows out of the tapped hub circle ([origin], in screen coordinates)
  /// as an expanding circle; a plain fade-and-rise without one.
  static Route<void> route({Rect? origin, CommunityLink? link}) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 620),
      reverseTransitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, __, ___) => CommunityScreen(link: link),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        if (origin == null || MediaQuery.of(context).disableAnimations) {
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        }
        return AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, child) {
            final t = curved.value;
            final size = MediaQuery.sizeOf(context);
            final c = origin.center;
            // Far enough to cover the farthest corner.
            final maxR = [
              Offset.zero,
              Offset(size.width, 0),
              Offset(0, size.height),
              Offset(size.width, size.height),
            ].map((p) => (p - c).distance).reduce(math.max);
            final r = ui.lerpDouble(origin.width / 2, maxR, t)!;
            final tint = (1 - t * 1.8).clamp(0.0, 1.0);
            return ClipPath(
              clipper: _CircleReveal(c, r),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child!,
                  // Starts as the purple circle and dissolves into the page.
                  if (tint > 0)
                    IgnorePointer(child: ColoredBox(color: kCommunityPurple.withValues(alpha: tint))),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CircleReveal extends CustomClipper<Path> {
  const _CircleReveal(this.center, this.radius);

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) => Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleReveal old) => old.center != center || old.radius != radius;
}

class _CommunityScreenState extends State<CommunityScreen> with WidgetsBindingObserver {
  late int _tab = widget.link?.tab ?? 0;
  late final Set<int> _opened = {_tab};
  bool _appInFront = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final front = state == AppLifecycleState.resumed;
    if (front != _appInFront) setState(() => _appInFront = front);
  }

  void _select(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tab = i;
      _opened.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    // Room the content leaves for the floating bar.
    final navSpace = _CommunityNavBar.height + 14 + bottomPad + 10;
    // Pauses the reels while a photo is open on top of this page.
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final onDark = _tab == 0 || AppColors.isDark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: onDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: _tab == 0 ? Colors.black : AppColors.ink)),
            if (_opened.contains(0))
              Positioned.fill(
                child: _TabLayer(
                  visible: _tab == 0,
                  child: ReelsView(
                    active: _tab == 0 && _appInFront && isCurrent,
                    bottomInset: navSpace,
                    focusReelId: widget.link?.reelId,
                  ),
                ),
              ),
            if (_opened.contains(1))
              Positioned.fill(
                child: _TabLayer(
                  visible: _tab == 1,
                  child: RecentWorkView(
                    bottomInset: navSpace,
                    focusPostId: widget.link?.postId,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _CommunityNavBar(index: _tab, onDark: _tab == 0, onSelect: _select),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cross-fades the tabs; the hidden one keeps its place but stops ticking.
class _TabLayer extends StatelessWidget {
  const _TabLayer({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          scale: visible ? 1 : 0.985,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: TickerMode(enabled: visible, child: child),
        ),
      ),
    );
  }
}

/// Floating frosted pill: Content | Recent work, with a gold highlight that
/// slides between them. Dark over reels, light over the feed.
class _CommunityNavBar extends StatelessWidget {
  const _CommunityNavBar({required this.index, required this.onDark, required this.onSelect});

  static const double height = 64;

  final int index;
  final bool onDark;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.smart_display_rounded, 'Content'),
    (Icons.collections_rounded, 'Recent work'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final fill = onDark ? const Color(0xA6141416) : AppColors.surfaceRaised.withValues(alpha: 0.86);
    final border = onDark ? Colors.white.withValues(alpha: 0.12) : AppColors.line;
    final idle = onDark ? Colors.white.withValues(alpha: 0.74) : AppColors.mut;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 14 + bottomPad),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: onDark ? 0.4 : 0.12),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              height: height,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(color: border),
              ),
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth / _items.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        left: w * index,
                        top: 0,
                        bottom: 0,
                        width: w,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(height / 2),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFF0C552), kCommunityGold, kCommunityGoldDeep],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: kCommunityGold.withValues(alpha: 0.45),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: i == index,
                                label: _items[i].$2,
                                child: PressScale(
                                  pressedScale: 0.94,
                                  onTap: () => onSelect(i),
                                  child: SizedBox.expand(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: _NavLabel(
                                          icon: _items[i].$1,
                                          label: _items[i].$2,
                                          color: i == index ? AppColors.onAccentDark : idle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavLabel extends StatelessWidget {
  const _NavLabel({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: const Duration(milliseconds: 260),
      builder: (context, c, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: c),
          const SizedBox(width: 8),
          Text(label, maxLines: 1, style: communityText(size: 15, weight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }
}
