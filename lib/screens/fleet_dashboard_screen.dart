import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/booking_api.dart';
import '../services/payment_service_factory.dart';
import 'fleet_order_sheet.dart';
import 'fleet_quotation_sheet.dart';
import 'fleet_quotation_view_screen.dart';
import 'fleet_request_view_screen.dart';
import 'fleet_washing_sheet.dart';
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
      // Pulls Service pickups + Quotations + Washing in parallel, then
      // merges them into one list sorted by created_at. Each item carries
      // its own `_kind` so the card and open-handler know which screen to
      // open and the status pill to use.
      final client = Supabase.instance.client;
      final fleetId = widget.fleetUser['id'];
      final results = await Future.wait([
        client.from('fleet_pickup_requests').select().eq('fleet_user_id', fleetId).order('created_at', ascending: false),
        client.from('fleet_quotation_requests').select().eq('fleet_user_id', fleetId).order('created_at', ascending: false),
        client.from('fleet_washing_requests').select().eq('fleet_user_id', fleetId).order('created_at', ascending: false),
      ]);
      final merged = <Map<String, dynamic>>[];
      for (final r in (results[0] as List)) merged.add({...r as Map, '_kind': 'service'});
      for (final r in (results[1] as List)) merged.add({...r as Map, '_kind': 'quotation'});
      for (final r in (results[2] as List)) merged.add({...r as Map, '_kind': 'washing'});
      merged.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));

      if (!mounted) return;
      setState(() { requests = merged; loading = false; });
    } catch (e) {
      // Without this, a failed initial load left `loading` stuck true
      // forever, and a failed pull-to-refresh threw unhandled.
      if (!mounted) return;
      setState(() => loading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not load your requests. Please check your connection and try again.',
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

  /// Tapping the big yellow REQUEST button at the bottom opens this
  /// chooser. Three Yellow Board services: Service pickup, Washing (₹699
  /// doorstep), and Quotation (photo + description → we price it).
  Future<void> _requestAny() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: F.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 44, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: F.line, borderRadius: BorderRadius.circular(2))),
            Text('What do you need?', style: TextStyle(color: F.txt, fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            _requestOption(ctx, 'service',  Icons.local_shipping_rounded, 'Request service',
              'Pickup, work at garage, drop back'),
            const SizedBox(height: 10),
            _requestOption(ctx, 'washing',  Icons.local_car_wash_rounded, 'Request washing',
              'Doorstep wash · from ₹699'),
            const SizedBox(height: 10),
            _requestOption(ctx, 'quotation', Icons.request_quote_rounded, 'Request quotation',
              'Photo + description → we price it'),
          ]),
        ),
      ),
    );
    if (!mounted || kind == null) return;
    if (kind == 'service') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => FleetOrderSheet(fleetUser: widget.fleetUser)));
    } else if (kind == 'washing') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => FleetWashingSheet(fleetUser: widget.fleetUser)));
    } else if (kind == 'quotation') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => FleetQuotationSheet(fleetUser: widget.fleetUser)));
    }
    fetchRequests();
  }

  Widget _requestOption(BuildContext ctx, String key, IconData icon, String title, String subtitle) => Material(
    color: F.sunken, borderRadius: BorderRadius.circular(16),
    child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => Navigator.pop(ctx, key),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(color: F.yellow.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: F.accent, size: 24)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: F.txt, fontSize: 16.5, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3)),
          ])),
          Icon(Icons.chevron_right_rounded, color: F.mut, size: 24),
        ]),
      )),
  );

  Future<void> _open(Map request) async {
    final kind = request['_kind']?.toString();
    if (kind == 'quotation') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FleetQuotationViewScreen(
          quotation: Map<String, dynamic>.from(request), fleetUser: widget.fleetUser)),
      );
    } else if (kind == 'washing') {
      // Minimal view for now — see your bill, tap Pay now (Razorpay).
      await _openWashing(Map<String, dynamic>.from(request));
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FleetRequestViewScreen(request: Map<String, dynamic>.from(request))),
      );
    }
    fetchRequests();
  }

  /// Washing requests are short, so instead of a whole screen the fleet
  /// gets a simple sheet with the price and a Pay now button that opens
  /// Razorpay. Once paid, the washer sees it in their dashboard.
  Future<void> _openWashing(Map<String, dynamic> w) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: F.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FleetWashingDetailSheet(wash: w, fleetUser: widget.fleetUser),
    );
  }

  // ── What a request needs from the fleet ─────────────────────────────
  bool _isDone(Map r) {
    switch (r['_kind']) {
      case 'quotation':
        return r['status'] == 'assigned' || r['status'] == 'declined';
      case 'washing':
        return r['status'] == 'done';
      default:
        return F.stepOf(r['status']?.toString()) == 3 && r['payment_status'] != 'awaiting_payment';
    }
  }
  bool _toPay(Map r) {
    if (r['_kind'] == 'washing') return r['payment_status'] == 'awaiting_payment';
    return r['payment_status'] == 'awaiting_payment';
  }
  bool _toAccept(Map r) => r['_kind'] == 'quotation' && r['status'] == 'priced';
  bool _toApprove(Map r) {
    if (r['_kind'] != 'service') return false;
    return r['customer_approval'] == null &&
        (r['admin_comment'] ?? '').toString().trim().isNotEmpty &&
        F.stepOf(r['status']?.toString()) < 3;
  }
  bool _newMessage(Map r) => r['fleet_has_unread_chat'] == true;
  bool _newUpdate(Map r) => r['has_unread_update'] == true;
  bool _needsYou(Map r) => _toAccept(r) || _toPay(r) || _toApprove(r) || _newMessage(r) || _newUpdate(r);

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
                        onPressed: _requestAny,
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
                          child: Text('NEW REQUEST',
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
            _Filter.active => ('No active requests', 'Tap NEW REQUEST — service, washing or a quotation.'),
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
    final kind = r['_kind']?.toString() ?? 'service';
    final model = (r['vehicle_model'] ?? r['vehicle_brand'] ?? (kind == 'quotation' ? 'Vehicle' : '')).toString().trim();
    final when = G.when(r['created_at']);
    final urgent = _toPay(r) || _toApprove(r) || _toAccept(r);

    // Kind pill (first in the row).
    final (kindLabel, kindFg, kindBg) = switch (kind) {
      'quotation' => ('Quotation', F.navy, F.yellow),
      'washing'   => ('Washing',   F.navy, const Color(0xFFE2E8F0)),
      _           => ('Service',   F.navy, const Color(0xFFBFDBFE)),
    };

    // Per-kind status pill.
    FleetPill statusPill() {
      if (kind == 'quotation') {
        final st = (r['status'] ?? 'pending').toString();
        return FleetPill(st.toUpperCase(), fg: Colors.white, bg: switch (st) {
          'priced' => F.accent,
          'accepted' => F.accent,
          'assigned' => F.accent,
          'declined' => F.redSolid,
          _ => F.amber,
        });
      }
      if (kind == 'washing') {
        final paid = r['payment_status'] == 'paid';
        final st = (r['status'] ?? '').toString();
        return FleetPill(
          st == 'done' ? 'DONE' : st == 'in_progress' ? 'WASHING' : paid ? 'ASSIGNED' : 'AWAITING PAYMENT',
          fg: Colors.white, bg: paid ? F.accent : F.amber);
      }
      return FleetPill(F.statusLabel(r['status']?.toString()), fg: fg, bg: bg);
    }

    final tags = <Widget>[
      FleetPill(kindLabel, fg: kindFg, bg: kindBg),
      statusPill(),
      if (_toAccept(r))
        FleetPill('Accept price', fg: Colors.white, bg: F.accent, icon: Icons.check_circle_rounded),
      if (_toApprove(r)) FleetPill('Approve work', fg: Colors.white, bg: F.redSolid, icon: Icons.warning_amber_rounded),
      if (_toPay(r))
        FleetPill('Pay ${_money(kind == 'washing' ? r['amount'] : r['total_amount'])}'.trim(),
          fg: F.amber, bg: F.amberBg, icon: Icons.payments_rounded),
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
                if ((r['car_number'] ?? '').toString().trim().isNotEmpty)
                  GaragePlate(r['car_number']?.toString()),
                if ((r['car_number'] ?? '').toString().trim().isNotEmpty) const SizedBox(height: 10),
                _highlight(
                  model.isEmpty ? 'Vehicle' : model,
                  TextStyle(color: F.txt, fontSize: 19, fontWeight: FontWeight.w900, height: 1.2),
                ),
                if (kind == 'quotation' && (r['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(r['description'].toString(),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: F.mut, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.4)),
                ],
                if (when.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Requested $when',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: F.mut, fontSize: 15, fontWeight: FontWeight.w600)),
                ],
                if (kind == 'service') ...[
                  const SizedBox(height: 14),
                  FleetProgressBar(step: step),
                ],
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

/// Short detail sheet for a Yellow Board wash. Shows the bill and a
/// Pay now button that opens Razorpay. After the payment lands, the
/// washer sees the wash in their own dashboard like a doorstep booking.
class FleetWashingDetailSheet extends StatefulWidget {
  final Map<String, dynamic> wash;
  final Map<String, dynamic> fleetUser;
  const FleetWashingDetailSheet({super.key, required this.wash, required this.fleetUser});

  @override
  State<FleetWashingDetailSheet> createState() => _FleetWashingDetailSheetState();
}

class _FleetWashingDetailSheetState extends State<FleetWashingDetailSheet> with FleetThemeListener {
  Map<String, dynamic> _w = {};
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _w = Map<String, dynamic>.from(widget.wash);
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final row = await Supabase.instance.client
          .from('fleet_washing_requests')
          .select()
          .eq('id', _w['id'])
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _w = Map<String, dynamic>.from(row));
    } catch (_) {}
  }

  Future<void> _payNow() async {
    setState(() => _paying = true);
    try {
      final start = await BookingApi.fleetWashingPayStart(
        id: _w['id'].toString(),
        fleetUserId: widget.fleetUser['id'],
      );
      if (start.orderId == null || start.keyId == null) {
        throw const BookingApiException('invalid_order', 'Could not start the payment. Please try again.');
      }
      final result = await getPaymentService().openCheckout(
        orderId: start.orderId!,
        keyId: start.keyId!,
        amountInPaise: start.amountPaise ?? 0,
        name: (widget.fleetUser['company_name'] ?? 'Yellow Board wash').toString(),
        email: (widget.fleetUser['username'] ?? '').toString(),
        contact: (widget.fleetUser['phone'] ?? '').toString(),
      );
      if (!result.success) {
        throw BookingApiException('payment_cancelled', result.errorMessage ?? 'Payment was cancelled.');
      }
      await BookingApi.fleetWashingPayConfirm(
        orderId: result.orderId ?? start.orderId!,
        paymentId: result.paymentId ?? '',
        signature: result.signature ?? '',
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paid. The washer will reach out shortly.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(context, error: e,
          customMessage: e is BookingApiException ? e.message : 'Payment failed. Please try again.');
      }
    }
    if (mounted) setState(() => _paying = false);
  }

  @override
  Widget build(BuildContext context) {
    final paid = _w['payment_status'] == 'paid';
    final amount = _w['amount'];
    final amtText = amount == null ? '₹699' : '₹${num.tryParse('$amount')?.round().toString() ?? '699'}';
    final washerAssigned = _w['washer_id'] != null;
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 44, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: F.line, borderRadius: BorderRadius.circular(2))),
            Center(child: Text('Yellow Board wash',
              style: TextStyle(color: F.txt, fontSize: 19, fontWeight: FontWeight.w900))),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: F.box(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text([_w['vehicle_brand'], _w['vehicle_model']].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                if ((_w['car_number'] ?? '').toString().isNotEmpty)
                  Text(_w['car_number'].toString(),
                    style: TextStyle(color: F.txt, fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                Text('BILL', style: TextStyle(color: F.mut, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                const SizedBox(height: 2),
                Text(amtText,
                  style: TextStyle(color: F.txt, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.1)),
                const SizedBox(height: 10),
                if (paid)
                  Row(children: [
                    Icon(Icons.check_circle_rounded, color: const Color(0xFF059669), size: 20),
                    const SizedBox(width: 6),
                    Text(_w['status'] == 'done' ? 'Washed and done.'
                        : _w['status'] == 'in_progress' ? 'Washing in progress.'
                        : washerAssigned ? 'Paid — the washer is on their way.' : 'Paid — assigning a washer.',
                      style: TextStyle(color: F.mut, fontSize: 15, fontWeight: FontWeight.w700)),
                  ])
                else
                  Text(washerAssigned
                      ? "A washer is ready — pay to start the wash."
                      : "We'll assign a washer once you've paid.",
                    style: TextStyle(color: F.mut, fontSize: 15, fontWeight: FontWeight.w700, height: 1.4)),
              ]),
            ),
            const SizedBox(height: 14),
            if (!paid)
              SizedBox(
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _paying ? null : _payNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: F.yellow, foregroundColor: F.navy,
                    disabledBackgroundColor: F.yellow.withOpacity(0.6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: _paying
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: F.navy))
                    : const Icon(Icons.payments_rounded),
                  label: Text(_paying ? 'Opening…' : 'Pay $amtText now',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
