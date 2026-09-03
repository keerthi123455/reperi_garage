import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'booking_tracking_screen.dart';

class VehicleBookingsScreen extends StatefulWidget {
  final String vehicleId;
  final String carModel;
  final String carBrand;
  final String carNumber;

  const VehicleBookingsScreen({
    super.key,
    required this.vehicleId,
    required this.carModel,
    required this.carBrand,
    required this.carNumber,
  });

  @override
  State<VehicleBookingsScreen> createState() =>
      _VehicleBookingsScreenState();
}

class _VehicleBookingsScreenState extends State<VehicleBookingsScreen> {
  List bookings = [];
  Set<String> unreadBookingIds = {};
  List insuranceUpdates = [];
  List washHistory = [];
  bool loading = true;
  bool _insuranceExpanded = false;
  bool _subscriptionExpanded = false;
  Map subscription = {};

  @override
  void initState() {
    super.initState();
    fetchBookings();
    fetchInsuranceUpdates();
    fetchSubscription();
    fetchWashHistory();
  }

  Future<void> fetchSubscription() async {
    try {
      final supabase = Supabase.instance.client;

      final response = await supabase
          .from('subscriptions')
          .select('*')
          .eq('vehicle_id', widget.vehicleId)
          .single();

      if (mounted) {
        setState(() {
          subscription = response;
        });
      }
    } catch (e) {
      debugPrint('Error fetching subscription: $e');
    }
  }

  Future<void> fetchWashHistory() async {
    try {
      final supabase = Supabase.instance.client;

      final subResponse = await supabase
          .from('subscriptions')
          .select('id')
          .eq('vehicle_id', widget.vehicleId)
          .single();

      if (subResponse == null) return;

      final subscriptionId = subResponse['id'];

      final response = await supabase
          .from('service_history')
          .select('*')
          .eq('subscription_id', subscriptionId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          washHistory = response as List;
        });
      }
    } catch (e) {
      debugPrint('Error fetching wash history: $e');
    }
  }

  Future<void> fetchInsuranceUpdates() async {
    try {
      final supabase = Supabase.instance.client;

      // Get all insurance claims for this vehicle
      final claimsResponse = await supabase
          .from('insurance_claims')
          .select('id')
          .eq('vehicle_id', widget.vehicleId);

      if ((claimsResponse as List).isEmpty) {
        if (!mounted) return;
        setState(() => insuranceUpdates = []);
        return;
      }

      // Get all claim IDs
      final claimIds =
          (claimsResponse as List).map((c) => c['id']).toList();

      // Get all updates for these claims
      final updatesResponse = await supabase
          .from('insurance_claims_updates')
          .select('*')
          .inFilter('claim_id', claimIds)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        insuranceUpdates = updatesResponse;
      });
    } catch (e) {
      print('Error fetching insurance updates: $e');
    }
  }

  Future<void> fetchBookings() async {
    final supabase = Supabase.instance.client;

    // ── UPDATED QUERY: Now includes admin table data (garage name & address) ──
    final response = await supabase
        .from('bookings')
        .select('''
          *,
          admin:assigned_to_admin_id (
            username,
            address
          )
        ''')
        .eq('vehicle_id', widget.vehicleId)
        .order('created_at', ascending: false);

    // fetch all unread admin messages in one query
    final bookingIds =
        (response as List).map((b) => b['id'].toString()).toList();

    Set<String> unreadIds = {};

    if (bookingIds.isNotEmpty) {
      final unreadChats = await supabase
          .from('booking_chats')
          .select('booking_id')
          .inFilter('booking_id', bookingIds)
          .eq('sender', 'admin')
          .eq('is_read_by_consumer', false);

      unreadIds = (unreadChats as List)
          .map((c) => c['booking_id'].toString())
          .toSet();
    }

    if (!mounted) return;

    setState(() {
      bookings = response;
      unreadBookingIds = unreadIds;
      loading = false;
    });
  }

  String formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String formatDay(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[date.weekday - 1];
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF262626),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        elevation: 0,
        title: Text(
          widget.carModel,
          style: const TextStyle(
            color: Color(0xFFD4A017),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFFD4A017)),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // ── VEHICLE HEADER ──
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF262626), Color(0xFF1C1C1C)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border:
                            Border.all(color: const Color(0xFF3A3A3A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ACTIVE VEHICLE',
                            style: TextStyle(
                              color: Color(0xFFD4A017),
                              fontSize: 11,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.carModel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.carBrand,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 16),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4A017)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFD4A017)
                                    .withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              widget.carNumber,
                              style: const TextStyle(
                                color: Color(0xFFD4A017),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 34),

                    const Text(
                      'Washing Subscription',
                      style: TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── EXPANDABLE SUBSCRIPTION TILE ──
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _subscriptionExpanded = !_subscriptionExpanded;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4A017).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFD4A017).withOpacity(0.5),
                          ),
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
                                      const Text(
                                        'Car Wash Subscription - Luxury Cars',
                                        style: TextStyle(
                                          color: Color(0xFFD4A017),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '₹${subscription['price'] ?? '1200'}/month',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD4A017),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'Active',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  _subscriptionExpanded ? Icons.expand_less : Icons.expand_more,
                                  color: const Color(0xFFD4A017),
                                  size: 28,
                                ),
                              ],
                            ),

                            // ── EXPANDED WASH HISTORY ──
                            if (_subscriptionExpanded) ...[
                              const SizedBox(height: 20),
                              const Divider(color: Color(0xFFD4A017)),
                              const SizedBox(height: 16),
                              const Text(
                                'Wash History',
                                style: TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (washHistory.isEmpty)
                                const Text(
                                  'No washes yet',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                )
                              else
                                ...washHistory.map((wash) {
                                  final dateStr = formatDate(wash['created_at'] ?? '');
                                  final dayStr = formatDay(wash['created_at'] ?? '');

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF262626),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFF3A3A3A),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Date and Day
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  dateStr,
                                                  style: const TextStyle(
                                                    color: Color(0xFFD4A017),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  dayStr,
                                                  style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade900.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Completed',
                                                style: TextStyle(
                                                  color: Colors.green.shade400,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        // Before and After Photos
                                        if (wash['before_photo_url'] != null || wash['after_photo_url'] != null)
                                          Row(
                                            children: [
                                              if (wash['before_photo_url'] != null)
                                                Expanded(
                                                  child: Column(
                                                    children: [
                                                      GestureDetector(
                                                        onTap: () {
                                                          _showImageViewer(context, wash['before_photo_url'], 'Before Photo');
                                                        },
                                                        child: ClipRRect(
                                                          borderRadius: BorderRadius.circular(8),
                                                          child: Image.network(
                                                            wash['before_photo_url'],
                                                            height: 70,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (_, __, ___) => Container(
                                                              height: 70,
                                                              color: const Color(0xFF333333),
                                                              child: const Icon(Icons.image_not_supported, color: Colors.white54),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      const Text(
                                                        'Before',
                                                        style: TextStyle(
                                                          color: Colors.white54,
                                                          fontSize: 9,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              const SizedBox(width: 8),
                                              if (wash['after_photo_url'] != null)
                                                Expanded(
                                                  child: Column(
                                                    children: [
                                                      GestureDetector(
                                                        onTap: () {
                                                          _showImageViewer(context, wash['after_photo_url'], 'After Photo');
                                                        },
                                                        child: ClipRRect(
                                                          borderRadius: BorderRadius.circular(8),
                                                          child: Image.network(
                                                            wash['after_photo_url'],
                                                            height: 70,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (_, __, ___) => Container(
                                                              height: 70,
                                                              color: const Color(0xFF333333),
                                                              child: const Icon(Icons.image_not_supported, color: Colors.white54),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      const Text(
                                                        'After',
                                                        style: TextStyle(
                                                          color: Colors.white54,
                                                          fontSize: 9,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 34),

                    const Text(
                      'Booked Services',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── INSURANCE UPDATES SECTION ──
                    GestureDetector(
                      onTap: () => setState(() => _insuranceExpanded = !_insuranceExpanded),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1C),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: insuranceUpdates.isNotEmpty
                                ? const Color(0xFFD4A017).withOpacity(0.3)
                                : Colors.grey.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Insurance Updates',
                                  style: TextStyle(
                                    color: Color(0xFFD4A017),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Icon(
                                  _insuranceExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: const Color(0xFFD4A017),
                                ),
                              ],
                            ),
                            if (_insuranceExpanded) ...[
                              const SizedBox(height: 16),
                              if (insuranceUpdates.isEmpty)
                                const Center(
                                  child: Text(
                                    'No insurance updates yet',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              else
                                ...insuranceUpdates.map((update) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF262626),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (update['photo_url'] != null)
                                          Container(
                                            height: 160,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              image: DecorationImage(
                                                image: NetworkImage(
                                                    update['photo_url']),
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            margin: const EdgeInsets.only(
                                                bottom: 12),
                                          ),
                                        Text(
                                          update['description'] ??
                                              'No description',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            height: 1.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          DateTime.parse(update['created_at'])
                                              .toString()
                                              .split('.')[0],
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (bookings.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1C),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: const Center(
                          child: Text(
                            'No Services Booked Yet',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 16),
                          ),
                        ),
                      ),

                    ...bookings.map((booking) {
                      final hasUpdate =
                          booking['booking_status'] != 'Pending';
                      final hasUnread = unreadBookingIds
                          .contains(booking['id'].toString());

                      // ── GET GARAGE INFO FROM ADMIN DATA ──
                      final adminData = booking['admin'] as Map<String, dynamic>?;
                      final garageName = adminData?['username'] ?? 'Garage';
                      final garageAddress = adminData?['address'] ?? '';

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BookingTrackingScreen(
                                booking: booking,
                              ),
                            ),
                          ).then((_) => fetchBookings());
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 22),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1C),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                                color: const Color(0xFF3A3A3A)),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      booking['package_name'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  // ── UNREAD CHAT BADGE ──
                                  if (hasUnread) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.red
                                                .withOpacity(0.5),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              Icons
                                                  .chat_bubble_rounded,
                                              color: Colors.white,
                                              size: 11),
                                          SizedBox(width: 5),
                                          Text(
                                            'CHAT',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight:
                                                  FontWeight.w900,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 10),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white38,
                                    size: 18,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),

                              if (hasUpdate)
                                Container(
                                  margin: const EdgeInsets.only(
                                      bottom: 18),
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade700,
                                    borderRadius:
                                        BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red
                                            .withOpacity(0.45),
                                        blurRadius: 18,
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                          Icons
                                              .notifications_active,
                                          color: Colors.white,
                                          size: 18),
                                      SizedBox(width: 10),
                                      Text(
                                        'NEW SERVICE UPDATE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              Text(
                                booking['package_price'],
                                style: const TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 20),

                              // ── NEW: GARAGE INFO SECTION ──
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF262626),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFF3A3A3A),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Garage Name
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on_outlined,
                                          color:
                                              const Color(0xFFD4A017),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Garage: $garageName',
                                            style: const TextStyle(
                                              color: Color(0xFFD4A017),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Garage Address
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.home_outlined,
                                          color: Colors.white54,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            garageAddress,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                              height: 1.4,
                                            ),
                                            maxLines: 2,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4A017),
                                  borderRadius:
                                      BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFD4A017)
                                          .withOpacity(0.35),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  booking['booking_status'],
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 22),

                              const Row(
                                children: [
                                  Spacer(),
                                  Text(
                                    'Tap to view live updates',
                                    style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 13),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_ios,
                                      color: Colors.white38, size: 13),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  void _showImageViewer(BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C1C),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // Image
            Padding(
              padding: const EdgeInsets.all(16),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF333333),
                  child: const Icon(
                    Icons.image_not_supported,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}