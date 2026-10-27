import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'booking_details_screen.dart';
import 'fleet_request_details_screen.dart';
import 'claim_details_screen.dart';
import 'garage_resolve_screen.dart';
import 'login_screen.dart';
import '../services/apple_review_assignment_override.dart';
import '../services/push_notification_service.dart';
import '../theme/garage_theme.dart';
import '../widgets/error_display.dart';
import '../widgets/reperi_logo.dart';

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
  /// ReperiResolve requests assigned to this garage from the CRM.
  List resolveRequests = [];
  Set<String> unreadBookingIds = {};
  String adminUsername = '';

  /// Shown at the top ("Haya Autogears"); from the admin row.
  String garageName = '';

  /// Car details for the claims list, by vehicle id.
  Map<String, Map> claimVehicles = {};

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

    // Separate, so a problem here never hides the normal bookings.
    _fetchResolveRequests();
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

  Future<void> _fetchResolveRequests() async {
    try {
      final rows = await Supabase.instance.client
          .rpc('garage_resolve_requests', params: {'p_admin_id': widget.adminId});
      if (!mounted) return;
      setState(() => resolveRequests = List.from(rows as List));
    } catch (e) {
      debugPrint('ReperiResolve requests not loaded: $e');
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
        .select('*')
        .eq('id', widget.adminId)
        .single();

    final adminUsername = adminData['username'] ?? '';
    final garageName = _garageNameFrom(adminData, adminUsername.toString());

    final isReviewAdmin = AppleReviewAssignmentOverride.enabled &&
        adminUsername == AppleReviewAssignmentOverride.adminUsername;

    // Fleet requests and claims: whatever is assigned to THIS garage
    // (assigned_to_admin_id) — set automatically by the rules in the CRM
    // (Assignment rules tab) and changeable per booking there.
    // supabase/assignments.sql gives fleet requests that column; until it's
    // run, fleet falls back to the old fixed routing below.
    List<dynamic> fleetResponse;
    try {
      fleetResponse = await supabase
          .from('fleet_pickup_requests')
          .select()
          .eq('assigned_to_admin_id', widget.adminId)
          .order('created_at', ascending: false);
    } catch (e) {
      debugPrint('Fleet by assignment not available yet, using old routing: $e');
      fleetResponse = await _legacyFleetRequests(supabase, adminUsername.toString(), isReviewAdmin);
    }

    final claimsResponse = await supabase
        .from('claim_table')
        .select('*')
        .eq('assigned_to_admin_id', widget.adminId)
        .order('created_at', ascending: false);

    // Number plate / brand / model for the claims (claims only store the
    // vehicle id). Not fatal — the tile falls back to the id.
    final claimVehicles = <String, Map>{};
    final claimVehicleIds = (claimsResponse as List)
        .map((c) => c['vehicle_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (claimVehicleIds.isNotEmpty) {
      try {
        final rows = await supabase
            .from('vehicles')
            .select('id, car_brand, car_model, car_number')
            .inFilter('id', claimVehicleIds);
        for (final v in rows as List) {
          claimVehicles['${v['id']}'] = v as Map;
        }
      } catch (e) {
        debugPrint('Claim vehicles not loaded: $e');
      }
    }

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
      this.garageName = garageName;
      this.claimVehicles = claimVehicles;
      loading = false;
    });
  }

  /// Old fixed fleet routing (before supabase/assignments.sql):
  /// the review fleet → the review garage, every real fleet → haya_autogears.
  Future<List<dynamic>> _legacyFleetRequests(SupabaseClient supabase, String adminUsername, bool isReviewAdmin) async {
    if (isReviewAdmin) {
      return await supabase
          .from('fleet_pickup_requests')
          .select()
          .eq('username', AppleReviewAssignmentOverride.reviewFleetUsername)
          .order('created_at', ascending: false);
    }
    if (adminUsername == 'haya_autogears') {
      return await supabase
          .from('fleet_pickup_requests')
          .select()
          // .neq alone would also hide rows whose username is NULL.
          .or('username.is.null,username.neq."${AppleReviewAssignmentOverride.reviewFleetUsername}"')
          .order('created_at', ascending: false);
    }
    return [];
  }

  /// A readable garage name from the admin row: its name column if it has
  /// one, otherwise the username ("haya_autogears" → "Haya Autogears").
  static String _garageNameFrom(Map row, String username) {
    for (final k in const ['garage_name', 'name', 'display_name']) {
      final v = (row[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return username
        .split(RegExp(r'[_\s.]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: G.card,
        surfaceTintColor: G.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log out',
          style: TextStyle(color: G.txt, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: G.mut),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('NO', style: TextStyle(color: G.mut, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'YES',
              style: TextStyle(color: G.red, fontWeight: FontWeight.w900),
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

  // ── Search ──────────────────────────────────────────────────────────
  /// Does any of [fields] contain what's typed? Spaces and dashes don't
  /// matter, so "ka01", "KA 01" and "ka-01-ab" all find "KA 01 AB 1234".
  bool _matches(List<dynamic> fields) {
    final q = G.squash(searchText);
    if (q.isEmpty) return true;
    return fields.any((f) => G.squash(f?.toString()).contains(q));
  }

  List<dynamic> _vehicleFields(Map? v) =>
      [v?['car_number'], v?['car_brand'], v?['car_model'], '${v?['car_brand'] ?? ''} ${v?['car_model'] ?? ''}'];

  /// "Hyundai Creta · KA01AB1234" (how ReperiResolve stores the vehicle)
  /// → (number, "Hyundai Creta").
  (String, String) _splitVehicleLabel(String? label) {
    final parts = (label ?? '').split('·').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return (parts.last, parts.sublist(0, parts.length - 1).join(' · '));
    return ('', parts.isEmpty ? 'Vehicle' : parts.first);
  }

  String _carName(Map? v) {
    final s = '${v?['car_brand'] ?? ''} ${v?['car_model'] ?? ''}'.trim();
    return s.isEmpty ? 'Vehicle details unavailable' : s;
  }

  @override
  Widget build(BuildContext context) {
    final filteredBookings = bookings.where((booking) {
      final vehicle = booking['vehicles'] as Map?;
      return _matches([
        ..._vehicleFields(vehicle),
        booking['booking_status'],
        booking['service_type'],
        booking['package_name'],
      ]);
    }).toList();

    final filteredFleet = fleetRequests.where((fleet) {
      return _matches([
        fleet['car_number'],
        fleet['vehicle_model'],
        fleet['company_name'],
        fleet['status'],
      ]);
    }).toList();

    final filteredClaims = claims.where((claim) {
      return _matches([
        ..._vehicleFields(claimVehicles['${claim['vehicle_id']}']),
        claim['vehicle_id'],
        claim['claim_status'],
      ]);
    }).toList();

    // Roadside Assistance bookings, assigned to this admin (see
    // PaymentScreen — they're stored in `bookings` under this prefix).
    final emergencyBookings = bookings
        .where((b) => _isEmergencyBooking(b))
        .where((b) => _matches([
              ..._vehicleFields(b['vehicles'] as Map?),
              b['package_name'],
              b['booking_status'],
            ]))
        .toList();

    // ReperiResolve requests sit on top of the bookings tab — open ones first.
    final filteredResolve = resolveRequests.where((r) {
      final s = (r['status'] ?? '').toString();
      if (s == 'Closed') return false;
      return _matches([
        r['vehicle_label'],
        ((r['categories'] as List?) ?? const []).join(' '),
        s,
      ]);
    }).toList()
      ..sort((a, b) {
        int rank(Map r) => const {'Submitted': 0, 'Accepted': 1, 'Quoted': 2}[r['status']] ?? 3;
        return rank(a).compareTo(rank(b));
      });

    final activeList = selectedTab == 0
        ? [...filteredResolve, ...filteredBookings]
        : selectedTab == 1
            ? filteredFleet
            : selectedTab == 2
                ? filteredClaims
                : emergencyBookings;

    final unreadCount = bookings.where((b) => unreadBookingIds.contains(b['id'].toString())).length;
    final fleetUnread = fleetRequests.where((f) => f['has_unread_update'] == true).length;
    final emergencyOpen = bookings
        .where((b) => _isEmergencyBooking(b) && b['return_otp_verified_at'] == null)
        .length;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: G.bg,
        bottomNavigationBar: _bottomNav(
          badges: [unreadCount, fleetUnread, 0, emergencyOpen],
        ),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  _searchBar(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      _countLine(activeList.length, unreadCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: G.mut, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator(color: G.navy))
                        : RefreshIndicator(
                            color: G.navy,
                            onRefresh: fetchBookings,
                            child: activeList.isEmpty
                                ? ListView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    children: [_emptyState()],
                                  )
                                : ListView.builder(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                    itemCount: activeList.length,
                                    itemBuilder: (context, index) {
                                      if (selectedTab == 0) {
                                        if (index < filteredResolve.length) {
                                          return _buildResolveCard(activeList[index]);
                                        }
                                        return _buildClientCard(activeList[index]);
                                      } else if (selectedTab == 1) {
                                        return _buildFleetCard(activeList[index]);
                                      } else if (selectedTab == 2) {
                                        return _buildClaimCard(activeList[index]);
                                      } else {
                                        return _buildEmergencyCard(activeList[index]);
                                      }
                                    },
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
  }

  static const _tabNames = ['bookings', 'fleet requests', 'claims', 'emergency bookings'];

  String _countLine(int shown, int unread) {
    final what = _tabNames[selectedTab];
    if (searchText.trim().isNotEmpty) {
      return '$shown found for “${searchText.trim()}”';
    }
    final base = '$shown $what';
    if (selectedTab == 0 && unread > 0) return '$base · $unread new message${unread == 1 ? '' : 's'}';
    return base;
  }

  Widget _header() {
    final name = garageName.isNotEmpty ? garageName : 'Your garage';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
      child: Row(
        children: [
          const ReperiLogoMark(size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: G.txt, fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const Text(
                  'Garage dashboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: G.mut, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _headerButton(
            Icons.storefront_rounded,
            'Update garage info',
            () => _launchURL('https://reperi.in/garage-info.html?admin_id=${widget.adminId}'),
          ),
          const SizedBox(width: 8),
          _headerButton(Icons.logout_rounded, 'Log out', _logout),
        ],
      ),
    );
  }

  Widget _headerButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: G.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: G.line),
            ),
            child: Icon(icon, color: G.navy, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => searchText = v),
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: G.txt, fontSize: 16, fontWeight: FontWeight.w700),
        cursorColor: G.navy,
        decoration: InputDecoration(
          hintText: 'Search car number, brand or model',
          hintStyle: const TextStyle(color: G.faint, fontSize: 15, fontWeight: FontWeight.w600),
          prefixIcon: const Icon(Icons.search_rounded, color: G.navy),
          suffixIcon: searchText.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, color: G.mut),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => searchText = '');
                  },
                ),
          filled: true,
          fillColor: G.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: G.navy, width: 1.8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: G.navy, width: 1.8),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: G.navy, width: 2.4),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final searching = searchText.trim().isNotEmpty;
    final what = _tabNames[selectedTab];
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 70, 32, 32),
      child: Column(
        children: [
          Icon(searching ? Icons.search_off_rounded : Icons.inbox_rounded, color: G.faint, size: 52),
          const SizedBox(height: 12),
          Text(
            searching ? 'Nothing matches “${searchText.trim()}”' : 'No $what yet',
            textAlign: TextAlign.center,
            style: const TextStyle(color: G.txt, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            searching ? 'Try the car number, brand or model.' : 'Pull down to refresh.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: G.mut, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav({required List<int> badges}) {
    const items = [
      (Icons.directions_car_rounded, 'Bookings'),
      (Icons.local_shipping_rounded, 'Fleet'),
      (Icons.shield_rounded, 'Claims'),
      (Icons.emergency_rounded, 'Emergency'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: G.card,
        border: Border(top: BorderSide(color: G.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        selectedTab = i;
                        searchText = '';
                        _searchController.clear();
                      });
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 54,
                              height: 30,
                              decoration: BoxDecoration(
                                color: selectedTab == i ? G.yellow : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(items[i].$1, size: 22, color: selectedTab == i ? G.navy : G.faint),
                            ),
                            if (badges[i] > 0)
                              Positioned(
                                right: -4,
                                top: -5,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 18),
                                  height: 18,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: G.red,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(color: G.card, width: 1.5),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    badges[i] > 9 ? '9+' : '${badges[i]}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, height: 1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              items[i].$2,
                              maxLines: 1,
                              style: TextStyle(
                                color: selectedTab == i ? G.navy : G.faint,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tiles ───────────────────────────────────────────────────────────
  /// One tile: number plate first, then the car, then what's being done,
  /// then status. Same shape on every tab.
  Widget _tile({
    required String? plate,
    required String title,
    String? subtitle,
    Widget? top,
    List<Widget> tags = const [],
    required Widget status,
    String action = 'Open',
    VoidCallback? onTap,
    Color? border,
    List<Widget> extra = const [],
  }) {
    final content = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: G.cardBox(border: border, width: border == null ? 1 : 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (top != null) ...[top, const SizedBox(height: 10)],
          if (plate != null) GaragePlate(plate),
          const SizedBox(height: 10),
          garageHighlight(
            title,
            searchText,
            const TextStyle(color: G.txt, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25),
            maxLines: 2,
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: G.mut, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ],
          ...extra,
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [status, ...tags],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Text(
                  '$action ›',
                  maxLines: 1,
                  style: const TextStyle(color: G.navy, fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return _TappableScale(onTap: onTap, child: content);
  }

  String _serviceName(Map booking) {
    final type = (booking['service_type'] ?? '').toString().trim();
    final pkg = (booking['package_name'] ?? '').toString().trim();
    final name = pkg.isNotEmpty ? pkg : (type.isNotEmpty ? G.sentence(type) : 'Service');
    final when = G.when(booking['created_at']);
    return when.isEmpty ? name : '$name · $when';
  }

  Widget _buildClientCard(Map booking) {
    final status = (booking['booking_status'] ?? 'Pending').toString();
    final hasUnread = unreadBookingIds.contains(booking['id'].toString());
    // The vehicle a booking points to can be gone (deleted since the
    // booking was made) — the tile has to cope with that.
    final vehicle = booking['vehicles'] as Map?;

    return _tile(
      plate: vehicle?['car_number']?.toString(),
      title: _carName(vehicle),
      subtitle: _serviceName(booking),
      status: GarageStatusPill(status, label: status.toLowerCase() == 'pending' ? 'New booking' : null),
      tags: [
        if (hasUnread) const GarageTag('New message', icon: Icons.chat_bubble_rounded),
      ],
      border: hasUnread ? G.red : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BookingDetailsScreen(booking: booking),
          ),
        ).then((_) => fetchBookings());
      },
    );
  }

  /// A ReperiResolve request assigned to this garage from the CRM.
  Widget _buildResolveCard(Map r) {
    final status = (r['status'] ?? 'Submitted').toString();
    final label = switch (status) {
      'Quoted' => 'Price sent',
      'Accepted' => 'Accepted — repair booking made',
      'Cancelled' => 'Cancelled',
      _ => 'Needs your price',
    };
    final cats = ((r['categories'] as List?) ?? const []).whereType<String>().toList();
    final files = ((r['media'] as List?) ?? const []).length;
    final (plate, car) = _splitVehicleLabel(r['vehicle_label']?.toString());
    return _tile(
      top: const GarageTag('REPERIRESOLVE', color: Color(0xFF1E5EFF), textColor: Color(0xFFFFE36A)),
      plate: plate.isEmpty ? null : plate,
      title: car,
      subtitle: [
        cats.isNotEmpty ? cats.join(' · ') : 'Problem reported',
        if (files > 0) '$files file${files == 1 ? '' : 's'} from customer',
      ].join(' · '),
      status: GarageStatusPill(status == 'Submitted' ? 'pending' : status, label: label),
      border: status == 'Submitted' ? G.navy : null,
      action: 'See photos',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GarageResolveScreen(request: r, adminId: widget.adminId)),
        ).then((_) => fetchBookings());
      },
    );
  }

  Widget _buildFleetCard(Map fleet) {
    final status = (fleet['status'] ?? 'Pending').toString();
    final unread = fleet['has_unread_update'] == true;
    final model = (fleet['vehicle_model'] ?? '').toString().trim();
    final company = (fleet['company_name'] ?? '').toString().trim();
    final when = G.when(fleet['created_at']);
    return _tile(
      plate: fleet['car_number']?.toString(),
      title: model.isNotEmpty ? model : 'Fleet vehicle',
      subtitle: [if (company.isNotEmpty) company, if (when.isNotEmpty) when].join(' · '),
      status: GarageStatusPill(status),
      tags: [
        if (unread) GarageTag((fleet['latest_update_type'] ?? 'New update').toString(), icon: Icons.notifications_rounded),
      ],
      border: unread ? G.red : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FleetRequestDetailsScreen(fleetRequest: fleet),
          ),
        ).then((_) => fetchBookings());
      },
    );
  }

  Widget _buildClaimCard(Map claim) {
    final status = (claim['claim_status'] ?? 'submitted').toString();
    final vehicle = claimVehicles['${claim['vehicle_id']}'];
    final when = G.when(claim['created_at']);
    return _tile(
      plate: vehicle?['car_number']?.toString(),
      title: vehicle != null ? _carName(vehicle) : 'Vehicle ID: ${claim['vehicle_id'] ?? 'Unknown'}',
      subtitle: ['Claim assistance', if (when.isNotEmpty) 'Submitted $when'].join(' · '),
      status: GarageStatusPill(status),
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
    );
  }

  /// Emergency (Roadside Assistance) tile — deliberately not tappable as a
  /// whole; the buttons on it do the work.
  Widget _buildEmergencyCard(Map booking) {
    final verified = booking['return_otp_verified_at'] != null;
    final otpCode = booking['return_otp_code']?.toString();
    final otpPending = !verified && booking['return_otp_generated_at'] != null && otpCode != null;
    final status = verified ? 'Done' : (booking['booking_status'] ?? 'Pending').toString();
    final name = (booking['customer_name'] ?? 'Unknown').toString();
    final phone = _customerPhone(booking);
    final address = (booking['pickup_address'] ?? 'Not specified').toString();
    final title = (booking['package_name'] ?? 'Roadside Assistance')
        .toString()
        .replaceFirst('Roadside Assistance - ', '');
    final vehicle = booking['vehicles'] as Map?;
    final when = G.when(booking['created_at']);

    return _tile(
      top: const GarageTag('EMERGENCY', icon: Icons.emergency_rounded),
      plate: vehicle?['car_number']?.toString(),
      title: title,
      subtitle: [if (vehicle != null) _carName(vehicle), if (when.isNotEmpty) when].join(' · '),
      status: verified
          ? const GarageStatusPill('done', label: 'Done — confirmed by customer')
          : GarageStatusPill(status, label: status.toLowerCase() == 'pending' ? 'New — go now' : null),
      border: verified ? null : G.red,
      extra: [
        const SizedBox(height: 12),
        _infoLine(Icons.person_rounded, name),
        const SizedBox(height: 6),
        _infoLine(Icons.location_on_rounded, address, maxLines: 3),
        if (!verified) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (phone != null) ...[
                Expanded(
                  child: _actionButton(
                    icon: Icons.call_rounded,
                    label: 'Call',
                    outlined: true,
                    color: G.navy,
                    onTap: () => _callCustomer(phone),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _actionButton(
                  icon: Icons.navigation_rounded,
                  label: 'Navigate',
                  color: G.red,
                  onTap: () => _navigateToEmergency(booking),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (otpPending)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: G.amberBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: G.amber.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  const Text(
                    'OTP — customer must enter it in their app',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: G.txt, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      otpCode,
                      style: const TextStyle(
                        color: G.navy,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Pull down to refresh once they confirm',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: G.mut, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            _actionButton(
              icon: Icons.check_circle_rounded,
              label: 'Mark as done',
              color: G.green,
              onTap: () => _markEmergencyDone(booking),
            ),
        ],
      ],
    );
  }

  Widget _infoLine(IconData icon, String text, {int maxLines = 1}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: G.mut, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: G.txt, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color, width: 1.5),
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: child,
            )
          : ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: child,
            ),
    );
  }

  Future<void> _navigateToEmergency(Map booking) async {
    final lat = booking['pickup_latitude'];
    final lng = booking['pickup_longitude'];
    final address = (booking['pickup_address'] ?? '').toString();
    final destination = (lat != null && lng != null)
        ? '$lat,$lng'
        : address;
    if (destination.isEmpty || destination == 'Not specified') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No location available for this booking'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
      'travelmode': 'driving',
    });
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Maps'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Generates the completion OTP for an emergency booking — same columns
  /// and status the normal "mark as done" uses for a no-pickup/drop
  /// booking (see BookingDetailsScreen._markAsDone). The customer types
  /// this code into the emergency banner on their home screen, which is
  /// what closes the booking.
  Future<void> _markEmergencyDone(Map booking) async {
    final otp = (1000 + math.Random().nextInt(9000)).toString();
    final nowIso = DateTime.now().toIso8601String();
    try {
      await Supabase.instance.client.from('bookings').update({
        'booking_status': 'Ready for Pickup',
        'marked_done_at': nowIso,
        'return_otp_code': otp,
        'return_otp_generated_at': nowIso,
      }).eq('id', booking['id']);
      if (!mounted) return;
      setState(() {
        booking['booking_status'] = 'Ready for Pickup';
        booking['marked_done_at'] = nowIso;
        booking['return_otp_code'] = otp;
        booking['return_otp_generated_at'] = nowIso;
      });
      await _showEmergencyOtpDialog(otp);
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not mark this booking as done. Please try again.',
      );
    }
  }

  Future<void> _showEmergencyOtpDialog(String otp) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: G.card,
        surfaceTintColor: G.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Completion OTP',
          style: TextStyle(color: G.txt, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ask the customer to enter this code on their home screen to confirm the service is done.',
              style: TextStyle(color: G.mut, height: 1.4),
            ),
            const SizedBox(height: 18),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                otp,
                style: const TextStyle(
                  color: G.navy,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'OK',
              style: TextStyle(color: G.navy, fontWeight: FontWeight.w900),
            ),
          ),
        ],
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