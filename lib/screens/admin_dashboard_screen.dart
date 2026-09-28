import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'booking_details_screen.dart';
import 'fleet_request_details_screen.dart';
import 'claim_details_screen.dart';
import 'login_screen.dart';
import '../services/apple_review_assignment_override.dart';
import '../services/push_notification_service.dart';
import '../widgets/error_display.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String adminId;
  
  const AdminDashboardScreen({super.key, required this.adminId});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List bookings = [];
  List fleetRequests = [];
  List claims = [];
  Set<String> unreadBookingIds = {};
  String adminUsername = '';

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

    try {
      await _fetchBookingsUnsafe(supabase);
    } catch (e) {
      debugPrint('Error fetching bookings: $e');
      if (!mounted) return;
      setState(() => loading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not load bookings. Please check your connection and try again.',
      );
    }
  }

  Future<void> _fetchBookingsUnsafe(SupabaseClient supabase) async {
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
        .eq('assigned_to_admin_id', widget.adminId)
        .order('created_at', ascending: false);

    // Get current admin's username
    final adminData = await supabase
        .from('admin')
        .select('username')
        .eq('id', widget.adminId)
        .single();

    final adminUsername = adminData['username'] ?? '';

    final isReviewAdmin = AppleReviewAssignmentOverride.enabled &&
        adminUsername == AppleReviewAssignmentOverride.adminUsername;

    // Fleet requests always go to exactly one admin — haya_autogears
    // normally, or the review admin while Apple review routing is
    // enabled. A full swap rather than an addition, since this fetch has
    // no per-request filter (whoever passes this gate sees every fleet
    // request that exists) — haya_autogears is meant to stop seeing them
    // while review mode has this rerouted, not see them alongside the
    // review admin.
    final fleetGateUsername = AppleReviewAssignmentOverride.enabled
        ? AppleReviewAssignmentOverride.adminUsername
        : 'haya_autogears';
    final fleetResponse = adminUsername == fleetGateUsername
        ? await supabase
            .from('fleet_pickup_requests')
            .select()
            .order('created_at', ascending: false)
        : [];

    // Only fetch claims if admin is newexpert_care (or the review admin —
    // see isReviewAdmin above). claim_table.assigned_to_admin_id is a
    // foreign key to admin.id (a uuid) — this used to compare against the
    // literal username string 'newexpert_care', which matched back when
    // that column was `text` and stored raw usernames; now that it's a
    // real uuid FK, it has to compare against that admin's actual id.
    final claimsResponse = (adminUsername == 'newexpert_care' || isReviewAdmin)
        ? await supabase
            .from('claim_table')
            .select('*')
            .eq('assigned_to_admin_id', isReviewAdmin
                ? (await AppleReviewAssignmentOverride.resolveAdminId())!
                : '1bcf9d81-6625-4c01-ac23-f0c237462eb7')
            .order('created_at', ascending: false)
        : [];

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
      claims = claimsResponse;
      unreadBookingIds = unreadIds;
      this.adminUsername = adminUsername;
      loading = false;
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log Out',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('NO', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'YES',
              style: TextStyle(color: Color(0xFFD4A017), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    PushNotificationService.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_logged_in');
    await prefs.remove('admin_id');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open garage info page'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not open the garage info page. Please try again.',
      );
    }
  }

  String _getStatusEmoji(String status) {
    switch (status) {
      case 'submitted':
        return '🟡';
      case 'inspection_scheduled':
        return '🔵';
      case 'inspection_completed':
        return '🟢';
      case 'approved':
        return '✅';
      case 'rejected':
        return '❌';
      default:
        return '⚪';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredBookings = bookings.where((booking) {
      final vehicle = booking['vehicles'];
      final query = searchText.toLowerCase();
      
      // Handle null vehicle safely
      if (vehicle == null) {
        return (booking['booking_status'] ?? '').toString().toLowerCase().contains(query);
      }
      
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

    final filteredClaims = claims;

    final activeList = selectedTab == 0
        ? filteredBookings
        : selectedTab == 1
            ? filteredFleet
            : filteredClaims;

    return Scaffold(
      backgroundColor: const Color(0xFF262626),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
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
        backgroundColor: const Color(0xFF1C1C1C),
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
          BottomNavigationBarItem(icon: Icon(Icons.shield), label: 'CLAIMS'),
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
                    Expanded(
                      child: activeList.isEmpty
                          ? Center(
                              child: Text(
                                selectedTab == 0
                                    ? 'No Bookings Found'
                                    : selectedTab == 1
                                        ? 'No Fleet Requests Found'
                                        : 'No Claims Found',
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
                                  } else if (selectedTab == 1) {
                                    return _buildFleetCard(activeList[index]);
                                  } else {
                                    return _buildClaimCard(activeList[index]);
                                  }
                                },
                              ),
                            ),
                    ),
                    // ── UPDATE GARAGE INFO BUTTON ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: GestureDetector(
                        onTap: () {
                          final garageInfoUrl = 'https://reperi.in/garage-info.html?admin_id=${widget.adminId}';
                          _launchURL(garageInfoUrl);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A017),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.info, color: Colors.black),
                              SizedBox(width: 8),
                              Text(
                                'Update Garage Info',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
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
    final status = (booking['booking_status'] ?? 'PENDING').toString().toUpperCase();
    final hasUnread = unreadBookingIds.contains(booking['id'].toString());
    // The vehicle a booking points to can be gone (deleted since the
    // booking was made) — the search filter above already accounts for
    // that, so this card has to as well instead of assuming it's there.
    final vehicle = booking['vehicles'] as Map?;

    Color statusColor;
    switch (status) {
      case 'PENDING':
        statusColor = const Color(0xFFD4A017);
        break;
      case 'ACCEPTED':
        statusColor = Colors.blueAccent;
        break;
      case 'IN GARAGE':
        statusColor = Colors.orangeAccent;
        break;
      case 'COMPLETED':
        statusColor = Colors.greenAccent;
        break;
      case 'CANCELLED':
        statusColor = Colors.redAccent;
        break;
      default:
        statusColor = const Color(0xFFD4A017);
    }

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
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF3A3A3A)),
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
                  child: Icon(Icons.build_rounded,
                      color: statusColor, size: 36),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle != null
                            ? '${vehicle['car_brand']} ${vehicle['car_model']}'
                            : 'Vehicle unavailable',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        booking['service_type']?.toString().replaceAll('_', ' ').toUpperCase() ?? 'SERVICE',
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
                  (vehicle?['car_number'] ?? '—').toString().toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                if (hasUnread) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'NEW MESSAGE',
                      style: TextStyle(
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Text(
                      'Tap to update',
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
          
            // Customer Name (if available)
            if (booking['customer_name'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Customer: ${booking['customer_name']}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ),
            // Emergency Service (Roadside Assistance) has no delivery
            // partner in the loop at all (see PaymentScreen's
            // assignsDeliveryPartner: false for this flow) — the admin
            // dispatching the technician is the only person who can reach
            // the customer, so a call option is offered right here instead
            // of only on a delivery dashboard elsewhere. Every other
            // booking type keeps in-app chat as the way to reach the
            // customer, so this is deliberately scoped to just this one
            // service.
            if (_isEmergencyBooking(booking) && _customerPhone(booking) != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: GestureDetector(
                  onTap: () => _callCustomer(_customerPhone(booking)!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.call_rounded, color: Color(0xFFD4A017), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Call Customer — ${_customerPhone(booking)}',
                          style: const TextStyle(
                            color: Color(0xFFD4A017),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Roadside Assistance rows are all inserted with
  /// package_name = 'Roadside Assistance - <issue title>' (see
  /// roadside_assistance_screen.dart's _handleBookNow) — that prefix is the
  /// only reliable signal for "this is an emergency-service booking",
  /// since assigned_to_admin_id alone can't tell it apart from any other
  /// booking type while Apple review routing has everything landing on the
  /// same demo admin.
  bool _isEmergencyBooking(Map booking) =>
      (booking['package_name'] ?? '').toString().startsWith('Roadside Assistance');

  /// customer_phone on a profile that was never filled in comes back as an
  /// empty string, not null — checking `!= null` alone let the call button
  /// render with nothing after the dash ("Call Customer — "). Trims and
  /// returns null for anything blank so the button doesn't show at all in
  /// that case.
  String? _customerPhone(Map booking) {
    final phone = booking['customer_phone']?.toString().trim();
    return (phone == null || phone.isEmpty) ? null : phone;
  }

  Future<void> _callCustomer(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF3A3A3A)),
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

  Widget _buildClaimCard(Map claim) {
    final status = (claim['claim_status'] ?? 'SUBMITTED').toString().toUpperCase();
    final emoji = _getStatusEmoji((claim['claim_status'] ?? 'submitted').toString());
    final vehicleId = claim['vehicle_id'] ?? 'Unknown';

    return _TappableScale(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ClaimDetailsScreen(
              claimId: claim['id'],
              adminUsername: adminUsername,
            ),
          ),
        ).then((_) => fetchBookings());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF3A3A3A)),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Claim Assistance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vehicle ID: $vehicleId',
                        style: const TextStyle(
                          color: Color(0xFFD4A017),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  emoji,
                  style: const TextStyle(fontSize: 32),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFD4A017).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFD4A017).withOpacity(0.3),
                ),
              ),
              child: Text(
                status.replaceAll('_', ' '),
                style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Submitted: ${claim['created_at'] != null ? DateTime.tryParse(claim['created_at'].toString())?.toString().split('.')[0] ?? 'Unknown' : 'Unknown'}',
              style: TextStyle(
                color: Colors.grey.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Tap to view details',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios,
                    size: 12, color: Colors.white38),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable tap feedback wrapper ─────────────────────────────
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