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
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchBookings();
  }

  Future<void> fetchBookings() async {
    final supabase = Supabase.instance.client;

    final response = await supabase
        .from('bookings')
        .select()
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
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
                          colors: [Color(0xFF1A1A1A), Color(0xFF111111)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border:
                            Border.all(color: const Color(0xFF2A2A2A)),
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
                      'Booked Services',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (bookings.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
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
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                                color: const Color(0xFF2A2A2A)),
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
}