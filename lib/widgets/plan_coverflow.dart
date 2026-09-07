import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/plan.dart';
import 'plan_card.dart';

/// The 3D "coverflow" subscription-plan picker: all three plans stay on
/// screen, the selected one sits upright and forward in gold, the other two
/// tilt inward and recede. A single continuous `_position` value (a
/// fractional plan index) drives every card's transform every frame, so:
///  - dragging moves `_position` 1:1 with the finger (no easing — the cards
///    track the touch directly),
///  - releasing animates `_position` the rest of the way to the nearest
///    plan with the same 450ms `cubic-bezier(.32,.72,.24,1)` ease the
///    prototype used for tap-to-select.
/// Card colours/text stay a hard on/off swap (as in the prototype — CSS
/// only transitions `transform`/`opacity`, not colour), snapping the moment
/// a card crosses the midpoint between two plans.
class PlanCoverflow extends StatefulWidget {
  const PlanCoverflow({
    super.key,
    required this.plans,
    required this.selectedIndex,
    required this.onSelect,
    required this.onSubscribe,
  });

  final List<Plan> plans;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onSubscribe;

  @override
  State<PlanCoverflow> createState() => _PlanCoverflowState();
}

class _PlanCoverflowState extends State<PlanCoverflow>
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
        if (_settleAnim != null) setState(() => _position = _settleAnim!.value);
      });
  }

  @override
  void didUpdateWidget(PlanCoverflow oldWidget) {
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

  double get _maxIndex => (widget.plans.length - 1).toDouble();

  void _onDragStart(DragStartDetails details) {
    _controller.stop();
    _dragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _position =
          (_position - details.delta.dx / _pxPerStep).clamp(0.0, _maxIndex).toDouble();
    });
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
    target = target.clamp(0, widget.plans.length - 1).toInt();
    _settleTo(target);
    if (target != widget.selectedIndex) widget.onSelect(target);
  }

  @override
  Widget build(BuildContext context) {
    final nearest = _position.round().clamp(0, widget.plans.length - 1).toInt();
    final order = List.generate(widget.plans.length, (i) => i)
      ..sort((a, b) =>
          (b - _position).abs().compareTo((a - _position).abs()));

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: SizedBox(
        height: kPlanCardHeight,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            for (final i in order)
              _PlanTransform(
                params: _paramsFor(i - _position),
                child: PlanCard(
                  plan: widget.plans[i],
                  selected: i == nearest,
                  onTap: () {
                    _controller.stop();
                    _dragging = false;
                    _settleTo(i);
                    if (i != widget.selectedIndex) widget.onSelect(i);
                  },
                  onSubscribe: () => widget.onSubscribe(i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static _CardParams _paramsFor(double d) {
    final absD = d.abs();
    final sign = d == 0 ? 0.0 : (d > 0 ? 1.0 : -1.0);
    double lerp(double a, double b, double t) => a + (b - a) * t;

    // `_position` is always clamped to [0, plans.length - 1] (see
    // `_onDragUpdate`/`_settleTo`), so `t` never needs clamping here: it's
    // already within [0, 1] on both legs of this piecewise interpolation.
    late final double tz, ryMag, scale, opacity, txMag;
    if (absD <= 1) {
      final double t = absD;
      tz = lerp(70, -80, t);
      ryMag = lerp(0, 40, t);
      scale = lerp(1.0, 0.86, t);
      opacity = lerp(1.0, 0.62, t);
      txMag = lerp(0, 118, t);
    } else {
      final double t = absD - 1;
      tz = -80;
      ryMag = 40;
      scale = lerp(0.86, 0.76, t);
      opacity = lerp(0.62, 0.40, t);
      txMag = lerp(118, 236, t);
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

class _PlanTransform extends StatelessWidget {
  const _PlanTransform({required this.params, required this.child});

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
