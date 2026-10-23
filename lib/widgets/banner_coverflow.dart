import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_colors.dart';
import 'placeholder_box.dart';

// Portrait 9:16 — matches wheelmanagement.jpg/paintcare.jpg/washing.jpg's
// native aspect ratio, so BoxFit.cover in `_BannerSlide` never has to crop.
// 5% smaller than the previous 151.2x268.8 (which was 20% smaller than the
// original 189x336).
const double kBannerWidth = 143.64;
const double kBannerHeight = 255.36;

/// The 3D "coverflow" image banner strip: all banners stay on screen at
/// once, the selected one sits upright and forward with a gold outline, the
/// other two tilt inward and recede. Pure images — no text/pricing content —
/// but otherwise the exact same transform/drag mechanic as the subscription
/// coverflow this replaced: a single continuous `_position` value (a
/// fractional index) drives every slide's transform every frame, so
/// dragging tracks the finger 1:1 and releasing eases to the nearest
/// banner over 450ms with a `cubic-bezier(.32,.72,.24,1)` curve.
class BannerCoverflow extends StatefulWidget {
  const BannerCoverflow({
    super.key,
    required this.imagePaths,
    required this.selectedIndex,
    required this.onSelect,
    this.onPositionChanged,
    this.onTapSelected,
  });

  final List<String> imagePaths;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Fired with the continuous drag/settle position (a fractional index)
  /// every time it changes — lets a parent fade other UI in/out in lockstep
  /// with the coverflow instead of only reacting once a drag settles.
  final ValueChanged<double>? onPositionChanged;

  /// Fired when the user taps the slide that's already centered/selected —
  /// tapping any other slide just brings it to center (see [onSelect])
  /// without opening anything, so a second, deliberate tap is what commits.
  final ValueChanged<int>? onTapSelected;

  @override
  State<BannerCoverflow> createState() => _BannerCoverflowState();
}

class _BannerCoverflowState extends State<BannerCoverflow>
    with SingleTickerProviderStateMixin {
  static const double _perspective = 1100;
  // Finger travel for one slide — lower = easier to move (was 170).
  static const double _pxPerStep = 115;
  static const Duration _settleDuration = Duration(milliseconds: 450);
  static const Cubic _settleCurve = Cubic(0.32, 0.72, 0.24, 1.0);

  late final AnimationController _controller;
  Animation<double>? _settleAnim;

  double _position = 0;
  bool _dragging = false;
  int _lastAnimatedTarget = 0;

  @override
  void initState() {
    super.initState();
    _position = widget.selectedIndex.toDouble();
    _lastAnimatedTarget = widget.selectedIndex;
    _controller = AnimationController(vsync: this, duration: _settleDuration)
      ..addListener(() {
        if (_settleAnim != null) {
          setState(() => _position = _settleAnim!.value);
          widget.onPositionChanged?.call(_position);
        }
      });
  }

  @override
  void didUpdateWidget(BannerCoverflow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && widget.selectedIndex != _lastAnimatedTarget) {
      _settleTo(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _settleTo(int target) {
    _lastAnimatedTarget = target;
    // Longer trips (tapping a slide two away) glide a little longer, so the
    // jump reads as one smooth sweep rather than a snap.
    final distance = (target - _position).abs();
    _controller.duration = Duration(milliseconds: (380 + 170 * distance.clamp(0.0, 3.0)).round());
    final curved = CurvedAnimation(parent: _controller, curve: _settleCurve);
    _settleAnim = Tween<double>(begin: _position, end: target.toDouble()).animate(curved);
    _controller
      ..value = 0
      ..forward();
  }

  /// Tap on any slide (front or background): bring it to the front in one
  /// glide; tapping the front one opens it.
  void _tapSlide(int i) {
    _controller.stop();
    _dragging = false;
    _settleTo(i);
    if (i != widget.selectedIndex) {
      widget.onSelect(i);
    } else {
      widget.onTapSelected?.call(i);
    }
  }

  double get _maxIndex => (widget.imagePaths.length - 1).toDouble();

  void _onDragStart(DragStartDetails details) {
    _controller.stop();
    _dragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _position =
          (_position - details.delta.dx / _pxPerStep).clamp(0.0, _maxIndex).toDouble();
    });
    widget.onPositionChanged?.call(_position);
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    int target;
    if (velocity.abs() >= 1400) {
      // A fast flick carries on to the next-but-one slide, like momentum.
      final projected = _position - velocity / (_pxPerStep * 9);
      target = velocity < 0
          ? math.max(projected.round(), _position.ceil())
          : math.min(projected.round(), _position.floor());
    } else if (velocity <= -250) {
      target = _position.ceil();
    } else if (velocity >= 250) {
      target = _position.floor();
    } else {
      target = _position.round();
    }
    target = target.clamp(0, widget.imagePaths.length - 1).toInt();
    _settleTo(target);
    if (target != widget.selectedIndex) widget.onSelect(target);
  }

  @override
  Widget build(BuildContext context) {
    final nearest = _position.round().clamp(0, widget.imagePaths.length - 1).toInt();
    final order = List.generate(widget.imagePaths.length, (i) => i)
      ..sort((a, b) => (b - _position).abs().compareTo((a - _position).abs()));

    // The side slides are painted outside this widget's own box (they peek
    // out to the left/right), so normal hit-testing would ignore touches on
    // them. _SwipeArea accepts touches anywhere in the strip's height —
    // drag anywhere to scroll, tap any slide to bring it forward.
    return _SwipeArea(
      onDragStart: _onDragStart,
      onDragUpdate: _onDragUpdate,
      onDragEnd: _onDragEnd,
      child: SizedBox(
        height: kBannerHeight,
        child: _OverflowHitStack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            for (final i in order)
              _BannerTransform(
                params: _paramsFor(i - _position),
                child: _BannerSlide(
                  assetPath: widget.imagePaths[i],
                  selected: i == nearest,
                  onTap: () => _tapSlide(i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Horizontal step between slides, as a fraction of the card's own width —
  // kept proportional so widening/narrowing kBannerWidth doesn't change how
  // much of a neighbour peeks out relative to the card itself.
  static const double _txStepRatio = 118 / 192;
  static const double _txStep = kBannerWidth * _txStepRatio;

  static _CardParams _paramsFor(double d) {
    final absD = d.abs();
    final sign = d == 0 ? 0.0 : (d > 0 ? 1.0 : -1.0);
    double lerp(double a, double b, double t) => a + (b - a) * t;

    // `_position` is always clamped to [0, imagePaths.length - 1], so `t`
    // never needs clamping here: it's already within [0, 1] on both legs.
    late final double tz, ryMag, scale, opacity, txMag;
    if (absD <= 1) {
      final double t = absD;
      tz = lerp(70, -80, t);
      ryMag = lerp(0, 40, t);
      scale = lerp(1.0, 0.86, t);
      opacity = lerp(1.0, 0.62, t);
      txMag = lerp(0, _txStep, t);
    } else {
      final double t = absD - 1;
      tz = -80;
      ryMag = 40;
      scale = lerp(0.86, 0.76, t);
      opacity = lerp(0.62, 0.40, t);
      txMag = lerp(_txStep, _txStep * 2, t);
    }

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, -1 / _perspective)
      ..translate(txMag * sign, 0.0, tz)
      ..rotateY(-ryMag * sign * math.pi / 180)
      ..scale(scale, scale, scale);

    return _CardParams(matrix: matrix, opacity: opacity);
  }
}

class _CardParams {
  const _CardParams({required this.matrix, required this.opacity});
  final Matrix4 matrix;
  final double opacity;
}

class _BannerTransform extends StatelessWidget {
  const _BannerTransform({required this.params, required this.child});

  final _CardParams params;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Transform on the outside so taps land on the slide where it is drawn
    // (Opacity would otherwise reject touches outside the un-moved box).
    // Visually identical to Opacity(Transform(...)).
    return Transform(
      alignment: Alignment.center,
      transform: params.matrix,
      child: Opacity(
        opacity: params.opacity.clamp(0.0, 1.0).toDouble(),
        child: child,
      ),
    );
  }
}

class _BannerSlide extends StatelessWidget {
  const _BannerSlide({
    required this.assetPath,
    required this.selected,
    required this.onTap,
  });

  final String assetPath;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: kBannerWidth,
        height: kBannerHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppColors.surfaceRaised,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [
                  const BoxShadow(
                    color: Color(0x8C000000),
                    blurRadius: 44,
                    offset: Offset(0, 18),
                  ),
                  BoxShadow(color: AppColors.accent.withOpacity(0.35), blurRadius: 34),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 26,
                    offset: Offset(0, 10),
                  ),
                ],
        ),
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => PlaceholderBox(
            label: assetPath.split('/').last,
            borderRadius: 0,
          ),
        ),
      ),
    );
  }
}


// ── Touch handling for the whole strip ──────────────────────────────────

/// A Stack that also hit-tests children painted outside its own box.
class _OverflowHitStack extends Stack {
  const _OverflowHitStack({
    super.alignment,
    super.clipBehavior,
    super.children,
  });

  @override
  RenderStack createRenderObject(BuildContext context) => _RenderOverflowHitStack(
        alignment: alignment,
        textDirection: textDirection ?? Directionality.maybeOf(context),
        fit: fit,
        clipBehavior: clipBehavior,
      );
}

class _RenderOverflowHitStack extends RenderStack {
  _RenderOverflowHitStack({
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
  });

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

/// Horizontal-drag area that accepts touches across the strip's full height
/// even where slides peek outside the widget's own box, and lets taps fall
/// through to the slide under the finger.
class _SwipeArea extends SingleChildRenderObjectWidget {
  const _SwipeArea({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required super.child,
  });

  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  _RenderSwipeArea createRenderObject(BuildContext context) =>
      _RenderSwipeArea(onDragStart, onDragUpdate, onDragEnd, MediaQuery.maybeGestureSettingsOf(context));

  @override
  void updateRenderObject(BuildContext context, _RenderSwipeArea renderObject) {
    renderObject.drag
      ..onStart = onDragStart
      ..onUpdate = onDragUpdate
      ..onEnd = onDragEnd
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
  }
}

class _RenderSwipeArea extends RenderProxyBox {
  _RenderSwipeArea(
    GestureDragStartCallback onStart,
    GestureDragUpdateCallback onUpdate,
    GestureDragEndCallback onEnd,
    DeviceGestureSettings? settings,
  ) : drag = HorizontalDragGestureRecognizer()
          ..onStart = onStart
          ..onUpdate = onUpdate
          ..onEnd = onEnd
          ..gestureSettings = settings;

  final HorizontalDragGestureRecognizer drag;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Anywhere within the strip's height counts — including the space to
    // the left/right where the side slides are drawn.
    if (position.dy < 0 || position.dy > size.height) return false;
    hitTestChildren(result, position: position);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) drag.addPointer(event);
  }

  @override
  void dispose() {
    drag.dispose();
    super.dispose();
  }
}
