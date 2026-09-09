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
  });

  final String id;
  final String brand;
  final String model;
  final String carNumber;
  final String? photoUrl;

  /// Latest booking's `booking_status`, or `null` if the vehicle has no
  /// bookings yet.
  final String? bookingStatus;

  Vehicle copyWith({String? photoUrl}) {
    return Vehicle(
      id: id,
      brand: brand,
      model: model,
      carNumber: carNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      bookingStatus: bookingStatus,
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
    );
  }
}
