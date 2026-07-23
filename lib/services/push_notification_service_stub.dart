/// Fallback for any platform that's neither web nor mobile/desktop
/// (shouldn't normally be reached). No-ops rather than throwing, since a
/// missing push notification integration shouldn't crash the app.
class PushNotificationService {
  PushNotificationService._();

  static Future<void> init() async {}

  static void loginAsCustomer(String supabaseUserId) {}

  static void loginAsFleet(String fleetUserId) {}

  static void loginAsAdmin() {}

  static void logout() {}
}