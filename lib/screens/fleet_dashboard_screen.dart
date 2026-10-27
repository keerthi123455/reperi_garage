import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fleet_order_sheet.dart';
import 'fleet_request_view_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import '../services/push_notification_service.dart';
import '../theme/fleet_theme.dart';
import '../theme/garage_theme.dart' show G, GaragePlate;
import '../widgets/error_display.dart';

class FleetDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> fleetUser;

  const FleetDashboardScreen({
    super.key,
    required this.fleetUser,
  });

  @override
  State<FleetDashboardScreen> createState() => _FleetDashboardScreenState();
}

/// Which requests the list shows.
enum _Filter { active, needsYou, done }

class _FleetDashboardScreenState extends State<FleetDashboardScreen> with FleetThemeListener {
  List requests = [];
  bool loading = true;

  final _searchController = TextEditingController();
  String _search = '';
  _Filter _filter = _Filter.active;

  @override
  void initState() {
    super.initState();
    PushNotificationService.loginAsFleet(widget.fleetUser['id'].toString());
    fetchRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchRequests() async {
    try {
      final response = await Supabase.instance.client
          .from('fleet_pickup_requests')
          .select()
          .eq('fleet_user_id', widget.fleetUser['id'])
          .order('created_at', ascending: false);

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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: F.card,
        surfaceTintColor: F.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Log out of fleet?', style: TextStyle(color: F.txt, fontWeight: FontWeight.w900)),
        content: Text('You can log in again any time from the menu.',
            style: TextStyle(color: F.mut, fontSize: 16, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: F.mut, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Log out', style: TextStyle(color: F.red, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ],
      ),
    );
    if (ok != true) return;

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

  Future<void> _requestPickup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FleetOrderSheet(fleetUser: widget.fleetUser)),
    );
    fetchRequests();
  }

  Future<void> _open(Map request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FleetRequestViewScreen(request: Map<String, dynamic>.from(request)),
      ),
    );
    fetchRequests();
  }

  // ── What a request needs from the fleet ─────────────────────────────
  bool _isDone(Map r) => F.stepOf(r['status']?.toString()) == 3 && r['payment_status'] != 'awaiting_payment';
  bool _toPay(Map r) => r['payment_status'] == 'awaiting_payment';
  bool _toApprove(Map r) =>
      r['customer_approval'] == null &&
      (r['admin_comment'] ?? '').toString().trim().isNotEmpty &&
      F.stepOf(r['status']?.toString()) < 3;
  bool _newMessage(Map r) => r['fleet_has_unread_chat'] == true;
  bool _newUpdate(Map r) => r['has_unread_update'] == true;
  bool _needsYou(Map r) => _toPay(r) || _toApprove(r) || _newMessage(r) || _newUpdate(r);

  bool _matches(Map r) {
    final q = G.squash(_search);
    if (q.isEmpty) return true;
    return [r['car_number'], r['vehicle_model'], r['status']].any((f) => G.squash(f?.toString()).contains(q));
  }

  String _money(dynamic v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null) return '';
    final s = n.round().toString();
    // Indian grouping: 1,23,456
    if (s.length <= 3) return '₹$s';
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '₹${parts.join(',')},$last3';
  }

  @override
  Widget build(BuildContext context) {
    final all = requests.cast<Map>();
    final active = all.where((r) => !_isDone(r)).toList();
    final needs = all.where(_needsYou).toList();
    final done = all.where(_isDone).toList();
    final base = switch (_filter) {
      _Filter.active => active,
      _Filter.needsYou => needs,
      _Filter.done => done,
    };
    // Searching looks through every request, not just the chosen box.
    final shown = _search.trim().isEmpty ? base : all.where(_matches).toList();
    // Things that need the fleet first.
    shown.sort((a, b) => (_needsYou(b) ? 1 : 0) - (_needsYou(a) ? 1 : 0));

    final company = (widget.fleetUser['company_name'] ?? 'Fleet').toString();

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: F.bg,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(company),
                      _searchBar(),
                      if (_search.trim().isEmpty) _filterBoxes(active.length, needs.length, done.length),
                      if (_search.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            '${shown.length} found for “${_search.trim()}”',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: F.mut, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      Expanded(
                        child: loading
                            ? Center(child: CircularProgressIndicator(color: F.accent))
                            : RefreshIndicator(
                                color: F.accent,
                                onRefresh: fetchRequests,
                                child: shown.isEmpty
                                    ? ListView(
                                        physics: const AlwaysScrollableScrollPhysics(),
                                        children: [_empty()],
                                      )
                                    : ListView.builder(
                                        physics: const AlwaysScrollableScrollPhysics(),
                                        padding: EdgeInsets.fromLTRB(
                                            16, 4, 16, 110 + MediaQuery.viewPaddingOf(context).bottom),
                                        itemCount: shown.length,
                                        itemBuilder: (context, i) => _card(shown[i]),
                                      ),
                              ),
                      ),
                    ],
                  ),
                  // Always-there main action.
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
                    child: SizedBox(
                      height: 62,
                      child: ElevatedButton.icon(
                        onPressed: _requestPickup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: F.yellow,
                          foregroundColor: F.navy,
                          elevation: 6,
                          shadowColor: Colors.black.withOpacity(0.25),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 28),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('REQUEST PICKUP',
                              maxLines: 1, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                        ),
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

  Widget _header(String company) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          FleetIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back to home', onTap: _goToClientHome),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: F.txt, fontSize: 21, fontWeight: FontWeight.w900),
                ),
                Text(
                  'Fleet dashboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const FleetThemeButton(),
          const SizedBox(width: 8),
          FleetIconButton(icon: Icons.logout_rounded, tooltip: 'Log out', onTap: _logout),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _search = v),
        textInputAction: TextInputAction.search,
        cursorColor: F.accent,
        style: TextStyle(color: F.txt, fontSize: 17, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: 'Search car number or model',
          hintStyle: TextStyle(color: F.faint, fontSize: 16, fontWeight: FontWeight.w600),
          prefixIcon: Icon(Icons.search_rounded, color: F.accent, size: 26),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.close_rounded, color: F.mut),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                ),
          filled: true,
          fillColor: F.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: F.accent, width: 2)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: F.accent, width: 2)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: F.accent, width: 2.6)),
        ),
      ),
    );
  }

  Widget _filterBoxes(int active, int needs, int done) {
    Widget box(_Filter f, int n, String label, {bool alert = false}) {
      final on = _filter == f;
      final onBg = F.dark ? F.yellow : F.navy;
      final onFg = F.dark ? F.navy : Colors.white;
      return Expanded(
        child: Material(
          color: on ? onBg : F.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _filter = f),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: on ? onBg : (alert && n > 0 ? F.redSolid : F.line), width: alert && n > 0 && !on ? 2.0 : 1.0),
              ),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('$n',
                        maxLines: 1,
                        style: TextStyle(
                          color: on ? onFg : (alert && n > 0 ? F.red : F.txt),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        )),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        maxLines: 1,
                        style: TextStyle(
                          color: on ? onFg.withOpacity(0.85) : F.mut,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        )),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          box(_Filter.active, active, 'Active'),
          const SizedBox(width: 8),
          box(_Filter.needsYou, needs, 'Needs you', alert: true),
          const SizedBox(width: 8),
          box(_Filter.done, done, 'Done'),
        ],
      ),
    );
  }

  Widget _empty() {
    final searching = _search.trim().isNotEmpty;
    final (title, sub) = searching
        ? ('Nothing matches “${_search.trim()}”', 'Try the car number or the model.')
        : switch (_filter) {
            _Filter.active => ('No active pickups', 'Tap REQUEST PICKUP to send a vehicle to us.'),
            _Filter.needsYou => ('All caught up', 'Nothing needs you right now.'),
            _Filter.done => ('No finished jobs yet', 'Completed vehicles show up here.'),
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off_rounded : (_filter == _Filter.needsYou ? Icons.task_alt_rounded : Icons.local_shipping_rounded),
            color: F.faint,
            size: 56,
          ),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center, style: TextStyle(color: F.txt, fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: F.mut, fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.4)),
        ],
      ),
    );
  }

  /// The model name with the searched words marked in yellow.
  Widget _highlight(String text, TextStyle style) {
    final q = _search.trim().toLowerCase();
    final lower = text.toLowerCase();
    if (q.isEmpty || !lower.contains(q)) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
    }
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final j = lower.indexOf(q, i);
      if (j < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (j > i) spans.add(TextSpan(text: text.substring(i, j)));
      spans.add(TextSpan(
        text: text.substring(j, j + q.length),
        style: const TextStyle(backgroundColor: F.yellow, color: F.navy),
      ));
      i = j + q.length;
    }
    return Text.rich(TextSpan(style: style, children: spans), maxLines: 2, overflow: TextOverflow.ellipsis);
  }

  Widget _card(Map r) {
    final step = F.stepOf(r['status']?.toString());
    final (fg, bg) = F.stepColors(step);
    final model = (r['vehicle_model'] ?? '').toString().trim();
    final when = G.when(r['created_at']);
    final urgent = _toPay(r) || _toApprove(r);
    final tags = <Widget>[
      FleetPill(F.statusLabel(r['status']?.toString()), fg: fg, bg: bg),
      if (_toApprove(r)) FleetPill('Approve work', fg: Colors.white, bg: F.redSolid, icon: Icons.warning_amber_rounded),
      if (_toPay(r))
        FleetPill('Pay ${_money(r['total_amount'])}'.trim(), fg: F.amber, bg: F.amberBg, icon: Icons.payments_rounded),
      if (_newMessage(r)) FleetPill('New message', fg: Colors.white, bg: F.redSolid, icon: Icons.chat_bubble_rounded),
      if (_newUpdate(r) && !_toApprove(r))
        FleetPill('New update', fg: F.blue, bg: F.blueBg, icon: Icons.notifications_active_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(r),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: F.box(border: urgent ? F.redSolid : null, width: urgent ? 2.0 : 1.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GaragePlate(r['car_number']?.toString()),
                const SizedBox(height: 10),
                _highlight(
                  model.isEmpty ? 'Vehicle' : model,
                  TextStyle(color: F.txt, fontSize: 19, fontWeight: FontWeight.w900, height: 1.2),
                ),
                if (when.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Requested $when',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: F.mut, fontSize: 15, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 14),
                FleetProgressBar(step: step),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: tags)),
                    const SizedBox(width: 8),
                    Text('Open ›', maxLines: 1, style: TextStyle(color: F.accent, fontSize: 16, fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
