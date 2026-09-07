import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  });

  final List<String> imagePaths;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Fired with the continuous drag/settle position (a fractional index)
  /// every time it changes — lets a parent fade other UI in/out in lockstep
  /// with the coverflow instead of only reacting once a drag settles.
  final ValueChanged<double>? onPositionChanged;

  @override
  State<BannerCoverflow> createState() => _BannerCoverflowState();
}

class _BannerCoverflowState extends State<BannerCoverflow>
    with SingleTickerProviderStateMixin {
  static const double _perspective = 1100;
  static const double _pxPerStep = 170;
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
    final curved = CurvedAnimation(parent: _controller, curve: _settleCurve);
    _settleAnim = Tween<double>(begin: _position, end: target.toDouble()).animate(curved);
    _controller
      ..value = 0
      ..forward();
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
    if (velocity <= -300) {
      target = _position.ceil();
    } else if (velocity >= 300) {
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: SizedBox(
        height: kBannerHeight,
        child: Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            for (final i in order)
              _BannerTransform(
                params: _paramsFor(i - _position),
                child: _BannerSlide(
                  assetPath: widget.imagePaths[i],
                  selected: i == nearest,
                  onTap: () {
                    _controller.stop();
                    _dragging = false;
                    _settleTo(i);
                    if (i != widget.selectedIndex) widget.onSelect(i);
                  },
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
    return Opacity(
      opacity: params.opacity.clamp(0.0, 1.0).toDouble(),
      child: Transform(
        alignment: Alignment.center,
        transform: params.matrix,
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
