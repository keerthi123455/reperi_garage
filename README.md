# Reperi Garage

A Flutter app for booking vehicle service, repair, and care packages — car wash, paint care, tyre care, denting/tinkering, AC service, insurance claims, roadside assistance, subscriptions, and fleet management — with online payments and admin/garage/fleet dashboards.

## Tech Stack

- **Flutter / Dart**
- **Supabase** — database, auth, and edge functions
- **Razorpay** — payments
- **OneSignal** — push notifications

## Project Structure

```
lib/
  constants/   # App-wide constants (colors, etc.)
  models/      # Data models
  screens/     # UI screens (customer, admin, garage, fleet)
  services/    # Business logic and backend integration
  theme/       # Theming and color schemes
  utils/       # Helper utilities
  widgets/     # Reusable UI components

supabase/functions/   # Supabase edge functions (login, delete-account, etc.)
```

## Getting Started

1. Install [Flutter](https://docs.flutter.dev/get-started/install).
2. Install dependencies:
   ```
   flutter pub get
   ```
3. Configure Supabase, Razorpay, and OneSignal credentials.
4. Run the app:
   ```
   flutter run
   ```
