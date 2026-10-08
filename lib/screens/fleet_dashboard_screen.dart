import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fleet_order_sheet.dart';
import 'fleet_request_view_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import '../services/push_notification_service.dart';
import '../widgets/error_display.dart';

class FleetDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> fleetUser;

  const FleetDashboardScreen({
    super.key,
    required this.fleetUser,
  });

  @override
  State<FleetDashboardScreen> createState() =>
      _FleetDashboardScreenState();
}

class _FleetDashboardScreenState
    extends State<FleetDashboardScreen> {

  List requests = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    PushNotificationService.loginAsFleet(widget.fleetUser['id'].toString());
    fetchRequests();
  }

  Future<void> fetchRequests() async {

    try {
      final response =
          await Supabase.instance.client
              .from('fleet_pickup_requests')
              .select()
              .eq(
                'fleet_user_id',
                widget.fleetUser['id'],
              )
              .order(
                'created_at',
                ascending: false,
              );

      if (!mounted) return;

      setState(() {
        requests = response;
        loading = false;
      });
    } catch (e) {
      // Without this, a failed initial load left `loading` stuck true
      // forever, and a failed pull-to-refresh threw unhandled.
      if (!mounted) return;
      setState(() => loading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not load your pickup requests. Please check your connection and try again.',
      );
    }
  }

  /// Fleet logout only ends the FLEET session — the customer's own
  /// Supabase Auth session is left untouched, so they land back on their
  /// client HomeScreen still signed in. Tapping Fleet Login again from the
  /// drawer then shows the username/password sheet, since the fleet keys
  /// below are gone.
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fleet_logged_in');
    await prefs.remove('fleet_user_id');
    await prefs.remove('fleet_company');
    await prefs.remove('fleet_username');

    final customer = Supabase.instance.client.auth.currentUser;
    if (customer != null) {
      // Hand this device's push identity back to the customer instead of
      // logging it out entirely (loginAsFleet had taken it over).
      PushNotificationService.loginAsCustomer(customer.id);
    } else {
      PushNotificationService.logout();
    }

    if (!mounted) return;
    _goToClientHome();
  }

  /// Back to the client HomeScreen. Pops when HomeScreen is underneath
  /// (the normal case — fleet login is opened from inside it); otherwise
  /// rebuilds the stack with HomeScreen, or LoginScreen if no customer is
  /// signed in at all.
  void _goToClientHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    final signedIn = Supabase.instance.client.auth.currentUser != null;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => signedIn ? const HomeScreen() : const LoginScreen(),
      ),
      (route) => false,
    );
  }

  Color _statusColor(String status) {

    switch (status.toUpperCase()) {

      case 'PICKED UP':
        return Colors.blue;

      case 'IN GARAGE':
        return Colors.orange;

      case 'COMPLETED':
        return Colors.green;

      default:
        return const Color(0xFFD4A017);
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF262626),

      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        centerTitle: true,
        // Always shown — not left to automaticallyImplyLeading, which
        // hides it whenever there's no route underneath.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFD4A017)),
          tooltip: 'Back to home',
          onPressed: _goToClientHome,
        ),
        title: Text(
          widget.fleetUser['company_name'] ?? 'Fleet',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFD4A017)),
            onPressed: _logout,
            tooltip: 'Log out',
          ),
        ],
      ),

      floatingActionButton:
          FloatingActionButton.extended(

        backgroundColor:
            const Color(0xFFD4A017),

        onPressed: () async {

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  FleetOrderSheet(
                fleetUser:
                    widget.fleetUser,
              ),
            ),
          );

          fetchRequests();
        },

        label: const Text(
          'REQUEST PICKUP',
          style: TextStyle(
            color: Colors.black,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        icon: const Icon(
          Icons.add,
          color: Colors.black,
        ),
      ),

      body: loading

          ? const Center(
              child:
                  CircularProgressIndicator(),
            )

          : requests.isEmpty

              ? const Center(
                  child: Text(
                    'No Requests Yet',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                )

              : RefreshIndicator(

                  onRefresh:
                      fetchRequests,

                  child: Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 600),
    child: ListView.builder(
      padding: const EdgeInsets.all(16),
      

                    itemCount:
                        requests.length,

                    itemBuilder:
                        (context, index) {

                      final request =
                          requests[index];

                      final status =
                          request['status'] ??
                              'Pending';

                      return _TappableScale(

                        onTap: () {

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FleetRequestViewScreen(
                                request:
                                    request,
                              ),
                            ),
                          );
                        },

                        child: Container(

                          margin:
                              const EdgeInsets.only(
                            bottom: 16,
                          ),

                          padding:
                              const EdgeInsets.all(
                                  18),

                          decoration:
                              BoxDecoration(

                            color:
                                const Color(
                                    0xFF1C1C1C),

                            borderRadius:
                                BorderRadius.circular(
                                    22),
                          ),

                          child: Column(

                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,

                            children: [

                              Text(
                                request['vehicle_model'] ?? 'Vehicle',
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white,
                                  fontSize:
                                      20,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                              ),

                              const SizedBox(
                                  height: 8),

                              Text(
                                request['car_number'] ?? 'N/A',
                                style:
                                    const TextStyle(
                                  color: Color(
                                      0xFFD4A017),
                                ),
                              ),
                              if (request['has_unread_update'] == true)
  Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 6,
    ),
    decoration: BoxDecoration(
      color: Colors.red,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Text(
      'NEW UPDATE',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),

                              const SizedBox(
                                  height: 16),

                              Container(

                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal:
                                      14,
                                  vertical:
                                      8,
                                ),

                                decoration:
                                    BoxDecoration(

                                  color: _statusColor(
                                          status)
                                      .withOpacity(
                                          0.15),

                                  borderRadius:
                                      BorderRadius.circular(
                                          12),
                                ),

                                child: Text(

                                  status
                                      .toUpperCase(),

                                  style:
                                      TextStyle(
                                    color:
                                        _statusColor(
                                            status),
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
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