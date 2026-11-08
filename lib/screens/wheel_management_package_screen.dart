import 'package:flutter/material.dart';

import 'tyre_care_screen.dart';

/// "Wheel Management" — the home banner and the Services list open this.
///
/// Wheel alignment, balancing and the combo now live on one screen
/// ([TyreCareScreen], the green Wheel Care screen), so this simply opens
/// that, keeping the same constructor every caller already uses.
class WheelManagementPackageScreen extends StatelessWidget {
  final String vehicleId;

  /// A package name to pre-select (case-insensitive), e.g. "Wheel Balancing".
  final String? highlightPackage;

  const WheelManagementPackageScreen({super.key, required this.vehicleId, this.highlightPackage});

  @override
  Widget build(BuildContext context) {
    return TyreCareScreen(
      vehicle: {'id': vehicleId},
      highlightPackage: highlightPackage,
    );
  }
}
