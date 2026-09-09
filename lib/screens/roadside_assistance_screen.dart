import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

class RoadsideAssistanceScreen extends StatefulWidget {
  const RoadsideAssistanceScreen({super.key});

  @override
  State<RoadsideAssistanceScreen> createState() =>
      _RoadsideAssistanceScreenState();
}

class _RoadsideAssistanceScreenState
    extends State<RoadsideAssistanceScreen> {

  String address = "Detecting location...";

  @override
  void initState() {
    super.initState();
    _getLocation();
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  bool get _isLocationDetected =>
      address != "Detecting location..." && address != "Location unavailable";

  Future<void> _getLocation() async {
    try {
      // Web (especially Safari) doesn't reliably support the Permissions
      // API that checkPermission()/requestPermission() depend on, so we
      // skip straight to getCurrentPosition() on web — the browser shows
      // its own native "Allow location" prompt automatically, and denial
      // throws an error we catch below instead.
      if (!kIsWeb) {
        LocationPermission permission =
            await Geolocator.checkPermission();

        if (permission == LocationPermission.denied) {
          permission =
              await Geolocator.requestPermission();
        }

        if (permission ==
                LocationPermission.denied ||
            permission ==
                LocationPermission.deniedForever) {
          setState(() {
            address = "Location unavailable";
          });
          return;
        }
      }

      final position =
          await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.high,
      );

      final placemarks =
          await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final place = placemarks.first;

      setState(() {
        address =
            "${place.locality}, ${place.administrativeArea}";
      });
    } catch (e) {
      setState(() {
        address = "Location unavailable";
      });
    }
  }

  Future<void> _callSupport() async {
    final uri = Uri(scheme: 'tel', path: '9353094672');
    await launchUrl(uri);
  }

  // Called when "BOOK NOW" is tapped — either from a specific service card,
  // or from the generic "General Assistance" button at the bottom of the
  // main screen.
  // - If location is already detected, goes straight to the base-pay popup.
  // - If not, tries to detect it again.
  // - If it's still not detected after that retry, shows a "can't detect
  //   your location" message instead of proceeding.
  Future<void> _handleBookNow(String issueTitle) async {
    if (!_isLocationDetected) {
      await _getLocation();
    }

    if (!mounted) return;

    if (!_isLocationDetected) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Sorry! Cannot detect your location',
            style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Please enable location access and try again.',
            style: TextStyle(color: AppColors.txt.withOpacity(0.7)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Color(0xFFD4A017))),
            ),
          ],
        ),
      );
      return;
    }

    // Location is detected — show the base-pay notice before proceeding.
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Base Fare',
          style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Base pay is ₹399. Additional charges will apply based on distance and service required.',
          style: TextStyle(color: AppColors.txt.withOpacity(0.7), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: TextStyle(color: AppColors.mut)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A017),
            ),
            onPressed: () {
              Navigator.pop(context); // close this dialog
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentScreen(
                    title: 'Roadside Assistance - $issueTitle',
                    price: '₹399',
                    duration: 'On-demand',
                    vehicleId: '',
                  ),
                ),
              );
            },
            child: Text('CONTINUE',
                style: TextStyle(color: AppColors.onAccentDark, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,

      appBar: AppBar(
        backgroundColor: AppColors.ink,
        elevation: 0,
        title: Text(
          'Roadside Assistance',
          style: TextStyle(color: AppColors.txt),
        ),
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

            /// LOCATION
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [

                  const Icon(
                    Icons.location_on,
                    color: Color(0xFFD4A017),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
  child: Column(
    crossAxisAlignment:
        CrossAxisAlignment.start,
    children: [

      Text(
        "Current Location",
        style: TextStyle(
          color: AppColors.mut,
          fontSize: 11,
        ),
      ),

      Text(
        address,
        style: TextStyle(
          color: AppColors.txt,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  ),
),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Text(
              "What do you need help with?",
              style: TextStyle(
                color: AppColors.txt,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 18),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: [

                _serviceCard(
                  "Flat Tyre",
                  Icons.tire_repair,
                ),

                _serviceCard(
                  "Dead Battery",
                  Icons.battery_alert,
                ),

                _serviceCard(
                  "Out Of Fuel",
                  Icons.local_gas_station,
                ),

                _serviceCard(
                  "Towing",
                  Icons.local_shipping,
                ),

                _serviceCard(
                  "Breakdown",
                  Icons.build,
                ),

                _serviceCard(
                  "Accident",
                  Icons.warning_amber,
                ),
              ],
            ),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [

                  Text(
                    "Can't find what you need?",
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "If none of the above fits your issue, call our experts directly.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.txt.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            /// GENERAL BOOK NOW BUTTON — same flow as a service-card
            /// booking, just with a generic "General Assistance" label
            /// instead of a specific issue.
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: () => _handleBookNow('General Assistance'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A017),
                  foregroundColor: AppColors.onAccentDark,
                ),
                child: const Text(
                  "BOOK NOW",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                onPressed: _callSupport,
                icon: const Icon(Icons.call),
                label: const Text(
                  "CALL US",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A017),
                  foregroundColor: AppColors.onAccentDark,
                ),
              ),
            ),

            const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _serviceCard(
  String title,
  IconData icon,
) {
    return GestureDetector(
  onTap: () {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // Lets the sheet size itself to content instead of a fixed height,
      // and lets it scroll on small screens instead of overflowing.
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [

                  Center(
                    child: Container(
                      width: 60,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.line,
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    "Features",
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 15),

                  Text(
                    "• Fast technician dispatch\n"
                    "• Live location tracking\n"
                    "• Professional assistance\n"
                    "• Emergency support",
                    style: TextStyle(
                      color: AppColors.txt.withOpacity(0.7),
                      height: 1.8,
                    ),
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // close the bottom sheet first
                        _handleBookNow(title);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFFD4A017),
                      ),
                      child: Text(
                        "BOOK NOW",
                        style: TextStyle(
                          color: AppColors.onAccentDark,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      onPressed: _callSupport,
                      icon: const Icon(Icons.call),
                      label: const Text(
                        "CALL US",
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  },
  child: Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          Icon(
            icon,
            color: const Color(0xFFD4A017),
            size: 34,
          ),

          const SizedBox(height: 10),

          Text(
            title,
            style: TextStyle(
              color: AppColors.txt,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ));
  }
}
