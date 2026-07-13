import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';

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
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Sorry! Cannot detect your location',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Please enable location access and try again.',
            style: TextStyle(color: Colors.white70),
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
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Base Fare',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Base pay is ₹1000. Additional charges will apply based on distance and service required.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
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
                    price: '₹1000',
                    duration: 'On-demand',
                    vehicleId: '',
                  ),
                ),
              );
            },
            child: const Text('CONTINUE',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Roadside Assistance',
          style: TextStyle(color: Colors.white),
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
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [

                  Icon(
                    Icons.location_on,
                    color: Color(0xFFD4A017),
                  ),

                  SizedBox(width: 8),

                  Expanded(
  child: Column(
    crossAxisAlignment:
        CrossAxisAlignment.start,
    children: [

      const Text(
        "Current Location",
        style: TextStyle(
          color: Colors.white54,
          fontSize: 11,
        ),
      ),

      Text(
        address,
        style: const TextStyle(
          color: Colors.white,
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

            /// HERO IMAGE
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/images/assistance_hero.jpg',
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "What do you need help with?",
              style: TextStyle(
                color: Colors.white,
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

            const SizedBox(height: 25),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [

                  Text(
                    "Can't find what you need?",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: 8),

                  Text(
                    "If none of the above fits your issue, call our experts directly.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
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
                  foregroundColor: Colors.black,
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
                  foregroundColor: Colors.black,
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
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(
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
                        color: Colors.white24,
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
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

                  const Text(
                    "• Fast technician dispatch\n"
                    "• Live location tracking\n"
                    "• Professional assistance\n"
                    "• Emergency support",
                    style: TextStyle(
                      color: Colors.white70,
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
                            Color(0xFFD4A017),
                      ),
                      child: const Text(
                        "BOOK NOW",
                        style: TextStyle(
                          color: Colors.black,
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
        color: const Color(0xFF151515),
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
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ));
  }
}