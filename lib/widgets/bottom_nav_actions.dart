import 'package:flutter/material.dart';

import '../screens/ai_advisor_sheet.dart';
import '../screens/profile_screen.dart';
import '../screens/services_screen.dart';
import '../screens/vehicle_bookings_screen.dart';

/// Shared navigation for the four [BottomNavBar] destinations — Home (0),
/// Bookings (1), Services (3), Profile (4); index 2 is the floating "Ask AI"
/// button's empty slot, handled separately by [openAiAdvisor] below.
///
/// Used by every screen that shows the bar EXCEPT HomeScreen itself (which
/// already owns richer active-vehicle state and its own push methods).
/// Switching tabs always collapses the stack back to the first route before
/// pushing the new one, so the bar reflects a fixed two-level stack — Home,
/// then whichever tab is open — no matter which tab you jump from, instead
/// of growing a deep chain of pushes as you bounce between tabs.
void handleBottomNavSelect(
  BuildContext context,
  int index, {
  required int currentIndex,
  required Map<String, dynamic>? activeVehicle,
}) {
  if (index == currentIndex) return;

  if (index == 0) {
    Navigator.popUntil(context, (route) => route.isFirst);
    return;
  }

  if (index == 1 && activeVehicle == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a vehicle first')),
    );
    return;
  }

  final Widget destination = switch (index) {
    1 => VehicleBookingsScreen(
        vehicleId: activeVehicle!['id'].toString(),
        carModel: (activeVehicle['car_model'] ?? '').toString(),
        carBrand: (activeVehicle['car_brand'] ?? '').toString(),
        carNumber: (activeVehicle['car_number'] ?? '').toString(),
      ),
    3 => ServicesScreen(activeVehicle: activeVehicle),
    4 => const ProfileScreen(),
    _ => const SizedBox.shrink(),
  };

  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => destination),
    (route) => route.isFirst,
  );
}

/// Opens the Ask AI advisor sheet — shared so the floating button behaves
/// identically on every screen that shows it.
void openAiAdvisor(BuildContext context, Map<String, dynamic>? activeVehicle) {
  if (activeVehicle == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a vehicle first')),
    );
    return;
  }
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => AiAdvisorSheet(vehicle: activeVehicle),
  );
}
