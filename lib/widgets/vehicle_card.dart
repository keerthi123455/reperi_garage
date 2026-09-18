import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import 'placeholder_box.dart';

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

  static const double _photoSize = 76;

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
    final status = _statusFor(widget.vehicle.bookingStatus);

    return ScaleTransition(
      scale: _scale,
      child: Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          width: widget.width,
          padding: const EdgeInsets.all(14),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VehiclePhoto(url: widget.vehicle.photoUrl, onTap: widget.onPhotoTap),
              const SizedBox(width: 14),
              Expanded(
                // A separate GestureDetector from the photo's — nesting one
                // inside the other would make both onTap callbacks fire on
                // a photo tap, since sibling tap recognizers don't
                // suppress each other in Flutter's gesture arena.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.vehicle.brand.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: AppColors.mut,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              widget.vehicle.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.txt,
                              ),
                            ),
                          ),
                          if (widget.vehicle.hasActiveSubscription) ...[
                            const SizedBox(width: 8),
                            const _ActiveSubBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(height: 1, color: AppColors.line),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(child: _LicensePlate(number: widget.vehicle.carNumber)),
                          const Spacer(),
                          Icon(Symbols.arrow_forward, size: 18, color: AppColors.accent),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          status.pulsing
                              ? _PulsingDot(color: status.dotColor)
                              : _StaticDot(color: status.dotColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              status.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: AppColors.mut,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (status.showBadge)
          const Positioned(top: -8, right: 8, child: _ServiceBadge()),
        // Bottom-left — the one corner nothing else reaches into. The
        // photo (top-left) tops out well above this, and the license
        // plate/arrow row lives over in the right-hand content column, so
        // this can't crowd either one the way bottom-right did.
        if (widget.vehicle.hasUpdate)
          const Positioned(bottom: -10, left: 8, child: _NotificationBadge()),
      ],
      ),
    );
  }
}

class _VehiclePhoto extends StatelessWidget {
  const _VehiclePhoto({required this.url, required this.onTap});

  final String? url;

  /// Opens the camera/gallery picker for this vehicle's photo.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = url != null && url!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: VehicleCard._photoSize,
        height: VehicleCard._photoSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            hasPhoto
                ? ClipOval(
                    child: Image.network(
                      url!,
                      width: VehicleCard._photoSize,
                      height: VehicleCard._photoSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => PlaceholderBox(
                        label: 'CAR PHOTO',
                        borderRadius: VehicleCard._photoSize / 2,
                      ),
                    ),
                  )
                : PlaceholderBox(
                    label: 'CAR PHOTO',
                    borderRadius: VehicleCard._photoSize / 2,
                  ),
            // Gold "+" badge signals the photo circle is tappable.
            Positioned(
              bottom: -2,
              right: -2,
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
          ],
        ),
      ),
    );
  }
}

class _ActiveSubBadge extends StatelessWidget {
  const _ActiveSubBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'ACTIVE SUB',
        style: GoogleFonts.manrope(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.onAccentDark,
        ),
      ),
    );
  }
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

class _StaticDot extends StatelessWidget {
  const _StaticDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// A status dot with an expanding, fading ring behind it — used when a
/// service is actively in progress on this vehicle.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 1 - t,
                child: Container(
                  width: 8 + t * 10,
                  height: 8 + t * 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The red "service in progress" spanner badge overlaid on the card's top
/// corner, with the same expanding-ring pulse as [_PulsingDot].
class _ServiceBadge extends StatefulWidget {
  const _ServiceBadge();

  @override
  State<_ServiceBadge> createState() => _ServiceBadgeState();
}

class _ServiceBadgeState extends State<_ServiceBadge> with SingleTickerProviderStateMixin {
  static const Color _red = Color(0xFFE5484D);

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.5,
                child: Container(
                  width: 28 + t * 14,
                  height: 28 + t * 14,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _red),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _red,
                  border: Border.all(color: AppColors.surfaceRaised, width: 2),
                ),
                child: const Icon(Symbols.build, size: 15, color: Colors.white, weight: 700),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The red "update from garage/washer/delivery/insurance" bell badge,
/// overlaid on the card's bottom-right corner — deliberately bigger than
/// [_ServiceBadge]'s spanner (34px core vs. 28px) since a new update needs
/// to be the first thing that catches your eye on the tile. Goes off (see
/// `VehicleUpdateTracker.markSeen`) once the vehicle's bookings screen —
/// where every one of those sources is actually shown — has been opened.
class _NotificationBadge extends StatelessWidget {
  const _NotificationBadge();

  static const Color _red = Color(0xFFE5484D);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _red,
        border: Border.all(color: AppColors.surfaceRaised, width: 2),
        boxShadow: [
          BoxShadow(
            color: _red.withOpacity(0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(Icons.notifications_rounded, size: 19, color: Colors.white),
    );
  }
}

class _StatusInfo {
  const _StatusInfo({
    required this.label,
    required this.dotColor,
    required this.pulsing,
    required this.showBadge,
  });

  final String label;
  final Color dotColor;
  final bool pulsing;
  final bool showBadge;
}

/// Maps the latest booking's `booking_status` to the tile's status row.
/// `null`/empty means the vehicle has no bookings yet; any non-"delivered"
/// status (pending, confirmed, in_progress, ...) reads as an active service.
_StatusInfo _statusFor(String? bookingStatus) {
  final status = bookingStatus?.trim().toLowerCase();
  if (status == null || status.isEmpty) {
    return const _StatusInfo(
      label: 'NO ACTIVE SERVICE',
      dotColor: Color(0xFF9AA0A6),
      pulsing: false,
      showBadge: false,
    );
  }
  if (status == 'delivered') {
    return const _StatusInfo(
      label: 'VEHICLE IS DELIVERED',
      dotColor: Color(0xFF3DBE6C),
      pulsing: false,
      showBadge: false,
    );
  }
  return const _StatusInfo(
    label: 'SERVICE IN PROGRESS',
    dotColor: AppColors.accent,
    pulsing: true,
    showBadge: true,
  );
}
