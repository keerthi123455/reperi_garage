import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';

class VehicleCard extends StatefulWidget {
  const VehicleCard({
    super.key,
    required this.vehicle,
    required this.width,
    required this.onTap,
    required this.onPhotoTap,
    this.isActive = false,
  });

  final Vehicle vehicle;
  final double width;

  /// Opens the vehicle's booking history — bound to everything in the tile
  /// except the photo, which has its own tap target (see [onPhotoTap]).
  final VoidCallback onTap;

  /// Opens the camera/gallery bottom sheet to change the vehicle's photo.
  final VoidCallback onPhotoTap;

  /// True for the vehicle currently centered/settled in the carousel —
  /// draws a gold glow and, the moment this flips from false to true, a
  /// quick scale "pop" confirming that this tile is now the active
  /// vehicle for anything booked elsewhere on the Home screen.
  final bool isActive;

  static const double _photoSize = 56;

  @override
  State<VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<VehicleCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.06).chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.06, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
      weight: 55,
    ),
  ]).animate(_pulseController);

  @override
  void didUpdateWidget(VehicleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only pop on the false→true transition — becoming inactive (or
    // already being active on the very first build) stays silent, so the
    // pop reads as "you just landed on this one" rather than firing on
    // every rebuild.
    if (!oldWidget.isActive && widget.isActive) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final name = [v.brand, v.model].where((s) => s.trim().isNotEmpty).join(' ');

    // Slim card: photo, name and plate on one row, then a "My bookings &
    // updates" bar so it's obvious what tapping the card does. Text scaling
    // is capped a little here because the carousel gives every card a
    // fixed height — this keeps big system font sizes from overflowing.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isActive ? AppColors.accent : AppColors.line,
              width: widget.isActive ? 1.5 : 1,
            ),
            color: AppColors.surfaceRaised,
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      _VehiclePhoto(
                        url: v.photoUrl,
                        isBike: v.isTwoWheeler,
                        onTap: widget.onPhotoTap,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        // A separate GestureDetector from the photo's — nesting
                        // one inside the other would make both fire on a photo tap.
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onTap,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                name.isEmpty ? 'My vehicle' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.txt,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _LicensePlate(number: v.carNumber),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(height: 1, color: AppColors.line),
              Material(
                color: Colors.transparent,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(
                      children: [
                        Icon(Symbols.calendar_month, size: 18, color: AppColors.accent, weight: 600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'My bookings & updates',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        if (v.hasUpdate) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5484D),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'New',
                              style: GoogleFonts.manrope(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.mut),
                      ],
                    ),
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

class _VehiclePhoto extends StatelessWidget {
  const _VehiclePhoto({required this.url, required this.onTap, this.isBike = false});

  final String? url;

  /// Picks the default car / bike picture when there's no photo yet.
  final bool isBike;

  /// Opens the camera/gallery picker for this vehicle's photo.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = url != null && url!.isNotEmpty;
    return SizedBox(
      width: VehicleCard._photoSize,
      height: VehicleCard._photoSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            // With a photo already there, tapping the circle views it full
            // screen (zoomable) instead of immediately jumping to the
            // camera/gallery picker — that's now the "+" badge's job below,
            // so changing the photo is still one tap away, just no longer
            // the only thing tapping the photo can do.
            onTap: hasPhoto ? () => _showVehiclePhotoViewer(context, url!) : onTap,
            child: hasPhoto
                ? ClipOval(
                    child: Image.network(
                      url!,
                      width: VehicleCard._photoSize,
                      height: VehicleCard._photoSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _DefaultVehicleAvatar(isBike: isBike),
                    ),
                  )
                : _DefaultVehicleAvatar(isBike: isBike),
          ),
          // Gold "+" badge — always opens the camera/gallery picker,
          // regardless of whether a photo already exists.
          Positioned(
            bottom: -2,
            right: -2,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent,
                  border: Border.all(color: AppColors.surfaceRaised, width: 2),
                ),
                child: Icon(Symbols.add, size: 14, color: AppColors.onAccentDark, weight: 700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen pinch-to-zoom viewer for a vehicle's photo — same look as
/// vehicle_bookings_screen.dart's before/after wash-photo viewer, just
/// standalone here since VehicleCard is a separate widget with no access
/// to that screen's private method.
void _showVehiclePhotoViewer(BuildContext context, String imageUrl) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.9),
    builder: (context) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: Colors.black.withOpacity(0.85),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Vehicle Photo',
                  style: TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.image_not_supported,
                    color: AppColors.mut,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A real Indian number plate's look — white plate, black text, blue strip —
/// kept fixed regardless of light/dark mode since it represents a physical
/// object, not a themed surface.
class _LicensePlate extends StatelessWidget {
  const _LicensePlate({required this.number});

  final String number;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(
        color: Colors.white,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 5, height: 22, color: const Color(0xFF1E3A8A)),
            // Flexible is what actually makes `overflow: ellipsis` below
            // do anything — a bare Text as a Row child reports its own
            // full intrinsic width upward instead of shrinking, so on a
            // phone with a bumped-up system text scale the plate could
            // overflow its Row instead of truncating.
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text(
                  number.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown until the customer adds a photo of their own vehicle: a friendly
/// cartoon car (or scooter) on a light-blue circle, drawn in code.
class _DefaultVehicleAvatar extends StatelessWidget {
  const _DefaultVehicleAvatar({required this.isBike});

  final bool isBike;

  @override
  Widget build(BuildContext context) {
    const size = VehicleCard._photoSize;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment(-0.4, -1),
          end: Alignment(0.4, 1),
          colors: [Color(0xFFBFE3FF), Color(0xFF7FB8F0)],
        ),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.82,
        height: size * 0.82 * 40 / 66,
        child: CustomPaint(painter: _CartoonVehiclePainter(isBike: isBike)),
      ),
    );
  }
}

/// The same cartoon car / scooter avatar at any size — used by the
/// vehicle dashboard header (vehicle_bookings_screen.dart).
class VehicleCartoonAvatar extends StatelessWidget {
  const VehicleCartoonAvatar({super.key, required this.isBike, this.size = 72});

  final bool isBike;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment(-0.4, -1),
          end: Alignment(0.4, 1),
          colors: [Color(0xFFBFE3FF), Color(0xFF7FB8F0)],
        ),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.82,
        height: size * 0.82 * 40 / 66,
        child: CustomPaint(painter: _CartoonVehiclePainter(isBike: isBike)),
      ),
    );
  }
}

/// Draws in a 66 × 40 grid, scaled to fit.
class _CartoonVehiclePainter extends CustomPainter {
  const _CartoonVehiclePainter({required this.isBike});

  final bool isBike;

  static const _red = Color(0xFFE8453C);
  static const _darkRed = Color(0xFFB8322B);
  static const _glass = Color(0xFFDFF2FF);
  static const _light = Color(0xFFFFE08A);
  static const _tyre = Color(0xFF222222);
  static const _hub = Color(0xFFDDDDDD);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 66, size.height / 40);
    final p = Paint()..isAntiAlias = true;

    // Shadow
    p.color = const Color(0x401D3B63);
    canvas.drawOval(Rect.fromCenter(center: const Offset(33, 36.3), width: 54, height: 5), p);

    if (isBike) {
      _scooter(canvas, p);
    } else {
      _car(canvas, p);
    }
    canvas.restore();
  }

  void _wheel(Canvas canvas, Paint p, Offset c, double r, double hub) {
    p.color = _tyre;
    canvas.drawCircle(c, r, p);
    p.color = _hub;
    canvas.drawCircle(c, hub, p);
  }

  void _car(Canvas canvas, Paint p) {
    final body = Path()
      ..moveTo(5, 28)
      ..cubicTo(5, 22, 8, 20, 14, 19)
      ..lineTo(20, 12)
      ..cubicTo(22, 10, 25, 9, 29, 9)
      ..lineTo(40, 9)
      ..cubicTo(44, 9, 47, 10, 50, 13)
      ..lineTo(55, 19)
      ..cubicTo(60, 20, 62, 22, 62, 27)
      ..lineTo(62, 30)
      ..cubicTo(62, 31, 61, 32, 60, 32)
      ..lineTo(7, 32)
      ..cubicTo(6, 32, 5, 31, 5, 30)
      ..close();
    p.color = _red;
    canvas.drawPath(body, p);

    p.color = _glass;
    canvas.drawPath(
      Path()
        ..moveTo(22, 13)
        ..cubicTo(23, 12, 25, 11.5, 28, 11.5)
        ..lineTo(32, 11.5)
        ..lineTo(32, 19)
        ..lineTo(17, 19)
        ..close(),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(34, 11.5)
        ..lineTo(40, 11.5)
        ..cubicTo(43, 11.5, 45, 12.5, 47, 14.5)
        ..lineTo(51, 19)
        ..lineTo(34, 19)
        ..close(),
      p,
    );

    p.color = _light;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(56, 22, 5, 2.5), const Radius.circular(1.2)), p);

    _wheel(canvas, p, const Offset(17, 31), 6, 2.6);
    _wheel(canvas, p, const Offset(50, 31), 6, 2.6);
  }

  void _scooter(Canvas canvas, Paint p) {
    // Handlebar
    final bar = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(49, 9), const Offset(57, 6.5), bar);

    // Rear body
    p.color = _red;
    canvas.drawPath(
      Path()
        ..moveTo(8, 26)
        ..cubicTo(8, 19, 13, 16, 20, 16)
        ..lineTo(31, 16)
        ..cubicTo(34, 16, 35, 18, 35, 21)
        ..lineTo(35, 26)
        ..close(),
      p,
    );
    // Floorboard
    p.color = _darkRed;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 24, 15, 4), const Radius.circular(1.5)), p);
    // Front shield / steering column
    p.color = _red;
    canvas.drawPath(
      Path()
        ..moveTo(41, 28)
        ..lineTo(46, 12)
        ..cubicTo(46.6, 10, 48, 9, 50, 9)
        ..lineTo(52, 9)
        ..lineTo(51.5, 12)
        ..lineTo(50, 12)
        ..lineTo(46, 28)
        ..close(),
      p,
    );
    // Front mudguard
    canvas.drawPath(
      Path()
        ..moveTo(43.5, 30)
        ..cubicTo(44.5, 24, 59.5, 24, 60.5, 30)
        ..close(),
      p,
    );
    // Seat
    p.color = const Color(0xFF333333);
    canvas.drawPath(
      Path()
        ..moveTo(11, 16)
        ..cubicTo(11, 13, 14, 12, 18, 12)
        ..lineTo(29, 12)
        ..cubicTo(31.5, 12, 32.5, 13.5, 31.5, 16)
        ..close(),
      p,
    );
    // Headlight
    p.color = _light;
    canvas.drawCircle(const Offset(51.5, 14), 2.1, p);

    _wheel(canvas, p, const Offset(15, 31), 5.5, 2.4);
    _wheel(canvas, p, const Offset(52, 31), 5.5, 2.4);
  }

  @override
  bool shouldRepaint(covariant _CartoonVehiclePainter old) => old.isBike != isBike;
}
