/// One row from the `vehicles` table, plus the latest `booking_status` for
/// that vehicle (fetched separately from `bookings`, see `home_screen.dart`).
class Vehicle {
  const Vehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.carNumber,
    this.photoUrl,
    this.bookingStatus,
    this.hasActiveSubscription = false,
    this.hasUpdate = false,
    this.vehicleType = 'four_wheeler',
  });

  final String id;
  final String brand;
  final String model;
  final String carNumber;
  final String? photoUrl;

  /// `'four_wheeler'` or `'two_wheeler'` — matches the `vehicles.vehicle_type`
  /// column (see profile_screen.dart's add/edit vehicle form). Drives which
  /// content the home screen shows below the Book Service/Book Washing
  /// buttons for the active vehicle.
  final String vehicleType;

  bool get isTwoWheeler => vehicleType == 'two_wheeler';

  /// Latest booking's `booking_status`, or `null` if the vehicle has no
  /// bookings yet.
  final String? bookingStatus;

  /// Whether this specific vehicle has a `subscriptions` row with
  /// `status = 'active'` — drives the "ACTIVE SUB" badge on its card. Each
  /// vehicle has its own subscription; this must never be true for every
  /// vehicle just because one of them is subscribed.
  final bool hasActiveSubscription;

  /// Whether the garage, a delivery partner, a washer, or an insurance
  /// claim has an update this vehicle's owner hasn't seen yet — see
  /// `VehicleUpdateTracker` for what counts as "seen". Drives the
  /// notification bell badge on its home-screen card.
  final bool hasUpdate;

  Vehicle copyWith({String? photoUrl}) {
    return Vehicle(
      id: id,
      brand: brand,
      model: model,
      carNumber: carNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      bookingStatus: bookingStatus,
      hasActiveSubscription: hasActiveSubscription,
      hasUpdate: hasUpdate,
      vehicleType: vehicleType,
    );
  }

  /// Separate from [copyWith] since a refreshed status can legitimately go
  /// back to `null` (no bookings left to show) — `?? this.bookingStatus`
  /// couldn't express that.
  Vehicle copyWithBookingStatus(String? bookingStatus) {
    return Vehicle(
      id: id,
      brand: brand,
      model: model,
      carNumber: carNumber,
      photoUrl: photoUrl,
      bookingStatus: bookingStatus,
      hasActiveSubscription: hasActiveSubscription,
      hasUpdate: hasUpdate,
      vehicleType: vehicleType,
    );
  }
}
