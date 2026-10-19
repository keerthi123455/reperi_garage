import 'package:flutter/material.dart';

import '../screens/ai_advisor_sheet.dart';
import '../screens/profile_screen.dart';
import '../screens/services_screen.dart';
import '../screens/vehicle_bookings_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'requirements.dart';

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
    // No vehicle: popup → Add vehicle → back, then open its bookings.
    _openBookingsAfterAddingVehicle(context);
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
/// identically on every screen that shows it. The advisor gives advice
/// and recommends packages from plain chat, independent of any vehicle —
/// it only needs one at the point someone taps a recommended package to
/// book it, which AiAdvisorSheet's own "add a vehicle" prompt covers, so
/// opening the sheet itself is never blocked.
void openAiAdvisor(BuildContext context, Map<String, dynamic>? activeVehicle) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => AiAdvisorSheet(vehicle: activeVehicle),
  );
}

Future<void> _openBookingsAfterAddingVehicle(BuildContext context) async {
  String? vehicleId;
  if (!await ensureReady(context, vehicle: true, onVehicle: (id) => vehicleId = id)) return;
  if (!context.mounted || vehicleId == null) return;
  Map<String, dynamic>? v;
  try {
    v = await Supabase.instance.client.from('vehicles').select().eq('id', vehicleId!).maybeSingle();
  } catch (_) {}
  if (!context.mounted) return;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder: (_) => VehicleBookingsScreen(
        vehicleId: vehicleId!,
        carModel: (v?['car_model'] ?? '').toString(),
        carBrand: (v?['car_brand'] ?? '').toString(),
        carNumber: (v?['car_number'] ?? '').toString(),
      ),
    ),
    (route) => route.isFirst,
  );
}
