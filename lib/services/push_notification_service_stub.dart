/// Fallback for any platform that's neither web nor mobile/desktop
/// (shouldn't normally be reached). No-ops rather than throwing, since a
/// missing push notification integration shouldn't crash the app.
class PushNotificationService {
  PushNotificationService._();

  static Future<void> init() async {}

  static Future<void> requestPermission() async {}

  // Reports permission already granted so the "soft ask" primer never
  // tries to show on a platform with no real push integration.
  static bool hasPermission() => true;

  static void loginAsCustomer(String supabaseUserId) {}

  static void loginAsFleet(String fleetUserId) {}

  static void loginAsAdmin() {}

  static void logout() {}
}