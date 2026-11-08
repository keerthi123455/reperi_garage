import 'package:in_app_update/in_app_update.dart';

/// Google Play's own "is there a newer version?" check (Android only).
/// Returns the newer version code (0 if Play doesn't say), or null when
/// there's no update / the app wasn't installed from the Play Store.
Future<int?> playStoreUpdateVersionCode() async {
  final u = await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 8));
  if (u.updateAvailability != UpdateAvailability.updateAvailable) return null;
  return u.availableVersionCode ?? 0;
}
