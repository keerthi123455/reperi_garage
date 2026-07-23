/// Centralizes all OneSignal setup and identity binding.
///
/// The app has three separate login systems (Supabase Auth for
/// customers, a plain `admin` table, and a plain `fleet_users` table),
/// so "who is this device logged in as" has to be told to OneSignal
/// explicitly at each of those three login points rather than relying
/// on any single shared session mechanism.
///
/// External ID scheme:
///   customer -> 'customer_<supabase_auth_user_id>'
///   fleet    -> 'fleet_<fleet_users.id>'
///   admin    -> 'admin' (fixed — the app currently has a single admin
///               account with no per-admin identity tracked anywhere;
///               revisit this if multi-admin login is ever added)
///
/// The official `onesignal_flutter` package only supports Android/iOS,
/// not Flutter Web, so this file picks the right implementation per
/// platform at compile time — same conditional-import pattern already
/// used for Razorpay in payment_service_factory.dart. Callers everywhere
/// else just `import 'push_notification_service.dart'` and call
/// PushNotificationService.xxx() — nothing else needs to know which
/// implementation is actually running.
export 'push_notification_service_stub.dart'
    if (dart.library.js_interop) 'push_notification_service_web.dart'
    if (dart.library.io) 'push_notification_service_mobile.dart';