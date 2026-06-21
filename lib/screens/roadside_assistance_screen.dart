import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

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

  Future<void> _getLocation() async {
    try {
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

            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                onPressed: () {},
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
      builder: (_) => Container(
        height: 420,
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
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

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {},
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
                  onPressed: () {},
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