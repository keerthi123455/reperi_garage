import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/booking_api.dart';
import '../theme/fleet_theme.dart';
import '../theme/garage_theme.dart' show G;
import '../widgets/error_display.dart';

/// Yellow Board → open a quotation request.
///
/// Pending — "We'll share a price shortly".
/// Priced — Accept + Call Reperi.
/// Accepted — "We're assigning a garage".
/// Assigned — tells the fleet their service booking is open (fleet_booking_id).
/// Declined — Reperi said no, with reason if any.
class FleetQuotationViewScreen extends StatefulWidget {
  final Map<String, dynamic> quotation;
  final Map<String, dynamic> fleetUser;
  const FleetQuotationViewScreen({super.key, required this.quotation, required this.fleetUser});

  @override
  State<FleetQuotationViewScreen> createState() => _FleetQuotationViewScreenState();
}

class _FleetQuotationViewScreenState extends State<FleetQuotationViewScreen> with FleetThemeListener {
  static const String _supportPhone = '7022149521';
  Map<String, dynamic> _q = {};
  bool _loading = false;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _q = Map<String, dynamic>.from(widget.quotation);
    _refresh();
    _signPhoto();
  }

  Future<void> _refresh() async {
    try {
      final row = await Supabase.instance.client
          .from('fleet_quotation_requests')
          .select()
          .eq('id', _q['id'])
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _q = Map<String, dynamic>.from(row));
    } catch (_) {}
  }

  Future<void> _signPhoto() async {
    final p = _q['photo_path']?.toString();
    if (p == null || p.isEmpty) return;
    try {
      final url = await Supabase.instance.client.storage.from('fleet-quotations').createSignedUrl(p, 600);
      if (!mounted) return;
      setState(() => _photoUrl = url);
    } catch (_) {}
  }

  Future<void> _accept() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept this price?'),
        content: Text('₹${_q['price']} for this quotation. We will assign a garage and pick up the vehicle.',
          style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accept')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await BookingApi.fleetQuotationAccept(id: _q['id'].toString(), fleetUserId: widget.fleetUser['id']);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Accepted. We're assigning a garage now.")),
        );
      }
    } catch (e) {
      if (mounted) ErrorDisplay.showPremiumError(context, error: e,
        customMessage: e is BookingApiException ? e.message : "Couldn't accept — please try again.");
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _callReperi() async {
    final uri = Uri.parse('tel:$_supportPhone');
    try {
      if (!await launchUrl(uri)) throw 'no dialer';
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call Reperi on $_supportPhone')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (_q['status'] ?? 'pending').toString();
    final price = _q['price'];
    final priceText = price == null ? null : '₹${num.tryParse('$price')?.round().toString()}';

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: F.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Row(children: [
                      FleetIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.maybePop(context)),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Quotation request',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: F.txt, fontSize: 21, fontWeight: FontWeight.w900))),
                      IconButton(onPressed: _refresh, icon: Icon(Icons.refresh_rounded, color: F.accent)),
                    ]),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      color: F.accent,
                      onRefresh: _refresh,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        children: [
                          _card(status, priceText),
                          const SizedBox(height: 16),
                          _descriptionCard(),
                          if (_photoUrl != null) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.network(_photoUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _photoFallback()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (status == 'priced')
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                        child: Row(children: [
                          Expanded(child: SizedBox(
                            height: 58,
                            child: OutlinedButton.icon(
                              onPressed: _callReperi,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: F.accent, width: 2),
                                foregroundColor: F.accent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              ),
                              icon: const Icon(Icons.call_rounded),
                              label: const Text('Call Reperi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            ),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: SizedBox(
                            height: 58,
                            child: ElevatedButton.icon(
                              onPressed: _loading ? null : _accept,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              ),
                              icon: _loading
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                : const Icon(Icons.check_rounded),
                              label: const Text('Accept', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            ),
                          )),
                        ]),
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

  Widget _card(String status, String? priceText) {
    final (bannerText, bannerColor) = switch (status) {
      'pending'  => ("We'll share a price shortly.", F.amber),
      'priced'   => ('Our price is ready — accept or call us.', F.accent),
      'accepted' => ("Accepted. We're assigning a garage now.", F.accent),
      'assigned' => ('A garage is booked. Open the service in your list.', F.accent),
      'declined' => ("We couldn't price this one. Call us if needed.", F.redSolid),
      _          => ('Status: $status', F.mut),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: F.box(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FleetPill(status.toUpperCase(), fg: Colors.white, bg: bannerColor),
          const SizedBox(width: 8),
          if (_q['created_at'] != null)
            Expanded(child: Text(G.when(_q['created_at']),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 14),
        Text([_q['vehicle_brand'], _q['vehicle_model']].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w700)),
        if (priceText != null) ...[
          const SizedBox(height: 10),
          Text('OUR PRICE', style: TextStyle(color: F.mut, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          const SizedBox(height: 2),
          Text(priceText,
            style: TextStyle(color: F.txt, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.1)),
        ],
        const SizedBox(height: 10),
        Text(bannerText, style: TextStyle(color: F.mut, fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.4)),
        if (status == 'declined' && (_q['declined_reason']?.toString().isNotEmpty ?? false)) ...[
          const SizedBox(height: 6),
          Text('"${_q['declined_reason']}"',
            style: TextStyle(color: F.mut, fontSize: 14.5, fontStyle: FontStyle.italic)),
        ],
        if (status == 'assigned' && _q['fleet_booking_id'] != null) ...[
          const SizedBox(height: 10),
          Text('Booking #${_q['fleet_booking_id'].toString().substring(0, 8)}',
            style: TextStyle(color: F.accent, fontSize: 14, fontWeight: FontWeight.w900)),
        ],
      ]),
    );
  }

  Widget _descriptionCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: F.box(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('YOU TOLD US', style: TextStyle(color: F.mut, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      const SizedBox(height: 6),
      Text(_q['description']?.toString() ?? '',
        style: TextStyle(color: F.txt, fontSize: 16, fontWeight: FontWeight.w600, height: 1.5)),
    ]),
  );

  Widget _photoFallback() => Container(
    height: 220, color: F.sunken, alignment: Alignment.center,
    child: Icon(Icons.image_not_supported_rounded, color: F.mut, size: 48),
  );
}
