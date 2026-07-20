import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'booking_details_screen.dart';
import 'fleet_request_details_screen.dart';
import 'login_screen.dart';
import '../services/push_notification_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List bookings = [];
  List fleetRequests = [];
  Set<String> unreadBookingIds = {};

  bool loading = true;

  final _searchController = TextEditingController();
  String searchText = '';
  int selectedTab = 0;

  @override
  void initState() {
    super.initState();
    PushNotificationService.loginAsAdmin();
    fetchBookings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchBookings() async {
    final supabase = Supabase.instance.client;

    final clientResponse = await supabase
        .from('bookings')
        .select('''
          *,
          vehicles (
            car_brand,
            car_model,
            car_number
          )
        ''')
        .order('created_at', ascending: false);

    final fleetResponse = await supabase
        .from('fleet_pickup_requests')
        .select()
        .order('created_at', ascending: false);

    // fetch all unread consumer messages in one query
    final unreadChats = await supabase
        .from('booking_chats')
        .select('booking_id')
        .eq('sender', 'consumer')
        .eq('is_read_by_admin', false);

    if (!mounted) return;

    final unreadIds = (unreadChats as List)
        .map((c) => c['booking_id'].toString())
        .toSet();

    setState(() {
      bookings = clientResponse;
      fleetRequests = fleetResponse;
      unreadBookingIds = unreadIds;
      loading = false;
    });
  }

  void _logout() {
    PushNotificationService.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredBookings = bookings.where((booking) {
      final vehicle = booking['vehicles'];
      final query = searchText.toLowerCase();
      return (vehicle['car_number'] ?? '').toString().toLowerCase().contains(query) ||
          (vehicle['car_model'] ?? '').toString().toLowerCase().contains(query) ||
          (booking['booking_status'] ?? '').toString().toLowerCase().contains(query);
    }).toList();

    final filteredFleet = fleetRequests.where((fleet) {
      final query = searchText.toLowerCase();
      return (fleet['car_number'] ?? '').toString().toLowerCase().contains(query) ||
          (fleet['company_name'] ?? '').toString().toLowerCase().contains(query) ||
          (fleet['status'] ?? '').toString().toLowerCase().contains(query);
    }).toList();

    final activeList = selectedTab == 0 ? filteredBookings : filteredFleet;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'GARAGE ADMIN',
          style: TextStyle(
            color: Color(0xFFD4A017),
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFD4A017)),
            onPressed: _logout,
            tooltip: 'Log out',
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        currentIndex: selectedTab,
        selectedItemColor: const Color(0xFFD4A017),
        unselectedItemColor: Colors.white54,
        onTap: (index) {
          setState(() {
            selectedTab = index;
            searchText = '';
            _searchController.clear();
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'CLIENT'),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_shipping), label: 'FLEET'),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4A017)),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        onChanged: (value) =>
                            setState(() => searchText = value),
                        decoration: InputDecoration(
                          hintText: selectedTab == 0
                              ? 'Search by model, number, status…'
                              : 'Search by company, number, status…',
                          hintStyle:
                              const TextStyle(color: Color(0xFF444444)),
                          prefixIcon: const Icon(Icons.search,
                              color: Color(0xFFD4A017)),
                          filled: true,
                          fillColor: const Color(0xFF111111),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: Color(0xFF2A2A2A)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: Color(0xFF2A2A2A)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: Color(0xFFD4A017)),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: activeList.isEmpty
                          ? Center(
                              child: Text(
                                selectedTab == 0
                                    ? 'No Bookings Found'
                                    : 'No Fleet Requests Found',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 18),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: fetchBookings,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(20),
                                itemCount: activeList.length,
                                itemBuilder: (context, index) {
                                  if (selectedTab == 0) {
                                    return _buildClientCard(activeList[index]);
                                  } else {
                                    return _buildFleetCard(activeList[index]);
                                  }
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildClientCard(Map booking) {
    final vehicle = booking['vehicles'];
    final hasUnread =
        unreadBookingIds.contains(booking['id'].toString());

    return _TappableScale(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BookingDetailsScreen(booking: booking),
          ),
        ).then((_) => fetchBookings());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF2A2A2A)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.directions_car,
                      color: Color(0xFFD4A017), size: 38),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle['car_model'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        vehicle['car_brand'] ?? '',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                // ── UNREAD CHAT BADGE ──
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_rounded,
                            color: Colors.white, size: 11),
                        SizedBox(width: 5),
                        Text(
                          'CHAT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              booking['package_name'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              vehicle['car_number'] ?? '',
              style: const TextStyle(
                color: Color(0xFFD4A017),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  booking['package_price'] ?? '',
                  style: const TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    booking['booking_status'] ?? '',
                    style: const TextStyle(
                      color: Color(0xFFD4A017),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Row(
              children: [
                Spacer(),
                Text(
                  'Tap to update progress',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: Colors.white38),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFleetCard(Map fleet) {
    final status = (fleet['status'] ?? 'PENDING').toString().toUpperCase();

    Color statusColor;
    switch (status) {
      case 'PICKED UP':
        statusColor = Colors.blueAccent;
        break;
      case 'IN GARAGE':
        statusColor = Colors.orangeAccent;
        break;
      case 'COMPLETED':
        statusColor = Colors.greenAccent;
        break;
      default:
        statusColor = const Color(0xFFD4A017);
    }

    return _TappableScale(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FleetRequestDetailsScreen(fleetRequest: fleet),
          ),
        ).then((_) => fetchBookings());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF2A2A2A)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(Icons.local_shipping_rounded,
                      color: statusColor, size: 36),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fleet['company_name'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fleet['vehicle_model'] ?? '',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fleet['car_number'] ?? '',
                  style: const TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                if (fleet['has_unread_update'] == true) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      fleet['latest_update_type'] ?? 'NEW UPDATE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Row(
                  children: [
                    Text(
                      'Tap to manage',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios,
                        size: 14, color: Colors.white38),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable tap feedback wrapper ─────────────────────────────
// Scales the child down slightly while pressed, and back up on
// release, so cards give a visible "clicked" response.
class _TappableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const _TappableScale({
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
  });

  @override
  State<_TappableScale> createState() => _TappableScaleState();
}

class _TappableScaleState extends State<_TappableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}