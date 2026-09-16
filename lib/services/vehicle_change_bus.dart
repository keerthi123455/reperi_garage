import 'package:flutter/foundation.dart';

/// App-wide "a vehicle's details changed" signal — same plain-singleton
/// `ChangeNotifier` pattern as `theme_controller.dart`'s `themeController`.
///
/// Home's vehicle carousel, the My Garage (profile) list, and the vehicle
/// dashboard screen each keep their own local copy of a vehicle's
/// name/brand/number rather than sharing one source of truth, so editing a
/// vehicle from any one of them (see the "Edit Vehicle" sheets in
/// profile_screen.dart and vehicle_bookings_screen.dart) wouldn't otherwise
/// be seen by the others until they happened to re-fetch on their own.
/// Firing this after a successful update lets every currently-mounted
/// screen refresh itself immediately.
class VehicleChangeBus extends ChangeNotifier {
  void notifyVehicleUpdated() => notifyListeners();
}

final vehicleChangeBus = VehicleChangeBus();
