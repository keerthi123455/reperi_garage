import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import 'guest_sheets.dart';
import 'slot_picker.dart';

/// The customer's apartment offer washes (₹1 / ₹199 / ₹999), read from the
/// `offer_bookings` table. They're booked per apartment, not per vehicle,
/// so this loads by the logged-in user rather than by vehicle.
///
/// Drop [OfferBookingsSection] into any list: it shows nothing at all when
/// the customer has no offer bookings, so other customers never see it.
class OfferBookingsSection extends StatefulWidget {
  const OfferBookingsSection({super.key, this.showEmpty = false});

  /// When true, shows a friendly "no offer washes yet" card instead of
  /// nothing (used by [OfferBookingsScreen]).
  final bool showEmpty;

  @override
  State<OfferBookingsSection> createState() => _OfferBookingsSectionState();
}

class _OfferBookingsSectionState extends State<OfferBookingsSection> {
  static const _gold = Color(0xFFD4A017);

  List<Map<String, dynamic>> _rows = const [];
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Status changes (washer marks it completed) show up on their own.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      // Guest — nothing to load (stops the spinner).
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final res = await Supabase.instance.client
          .from('offer_bookings')
          .select('*')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(res as List);
        _loaded = true;
      });
    } catch (e) {
      // Never break the screen this sits in.
      debugPrint('Error fetching offer bookings: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return widget.showEmpty
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _gold)),
            )
          : const SizedBox.shrink();
    }
    // Guest on the My Bookings page: invite them to sign up.
    if (widget.showEmpty && Supabase.instance.client.auth.currentUser == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your bookings live here',
                style: TextStyle(color: AppColors.txt, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                "You're browsing as a guest. Sign up to book and track your services.",
                style: TextStyle(color: AppColors.mut, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    if (await requireAccount(context, title: 'Welcome to Reperi')) _load();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD23F),
                    foregroundColor: const Color(0xFF16213E),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Sign up / Log in', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      if (!widget.showEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: _card(
          child: Text(
            'No offer washes yet. Tap the offer button on the home screen to book one.',
            style: TextStyle(color: AppColors.mut, fontSize: 14, height: 1.4),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'Offer Washes',
          style: TextStyle(
            color: AppColors.txt,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 24),
        ..._rows.map(_bookingCard),
      ],
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );

  static bool _isDone(String status) =>
      RegExp(r'^(completed|delivered)$', caseSensitive: false).hasMatch(status);

  static String _prettyName(String raw) {
    // "BUCKET WASH (OFFER)" → "Bucket Wash"
    final cleaned = raw.replaceAll(RegExp(r'\(offer\)', caseSensitive: false), '').trim();
    return cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  static String _date(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final status = (b['booking_status'] ?? 'Booked').toString();
    final done = _isDone(status);
    final apartment = (b['pickup_address_name'] ?? b['pickup_address'] ?? '').toString();
    final price = b['package_price']?.toString();
    final title = _prettyName((b['package_name'] ?? 'Offer Wash').toString());

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? 'Offer Wash' : title,
            style: TextStyle(color: AppColors.txt, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (price != null)
            Text(
              '₹$price',
              style: const TextStyle(color: _gold, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          if (apartment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.apartment_rounded, color: AppColors.mut, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(apartment, style: TextStyle(color: AppColors.txt, fontSize: 14)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(_date(b['created_at']), style: TextStyle(color: AppColors.mut, fontSize: 13)),
          BookingSlotBadge(record: b),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: done ? const Color(0xFF2E7D32) : _gold,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              done ? 'COMPLETED' : status.toUpperCase(),
              style: TextStyle(
                color: done ? Colors.white : AppColors.onAccentDark,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            done
                ? 'Your car has been washed. Thank you!'
                : 'Our washer will come to your apartment. We\'ll notify you when it\'s done.',
            style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.4),
          ),
          _photos(b),
        ],
      ),
    );
  }

  /// Before / During / After photos the washer uploads from the washer
  /// dashboard. Hidden until at least one exists.
  Widget _photos(Map<String, dynamic> b) {
    const stages = [
      ('before_photo_url', 'Before'),
      ('during_photo_url', 'During'),
      ('after_photo_url', 'After'),
    ];
    final any = stages.any((st) => (b[st.$1] ?? '').toString().isNotEmpty);
    if (!any) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wash photos',
              style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < stages.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _photoTile((b[stages[i].$1] ?? '').toString(), stages[i].$2)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoTile(String url, String label) {
    final has = url.isNotEmpty;
    return Column(
      children: [
        GestureDetector(
          onTap: has ? () => _openPhoto(url, label) : null,
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: has
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, child, p) => p == null
                          ? child
                          : Container(
                              color: AppColors.chipBg,
                              alignment: Alignment.center,
                              child: const SizedBox(
                                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _gold)),
                            ),
                      errorBuilder: (c, e, st) => Container(
                        color: AppColors.chipBg,
                        alignment: Alignment.center,
                        child: Icon(Icons.broken_image_outlined, color: AppColors.mut),
                      ),
                    )
                  : Container(
                      color: AppColors.chipBg,
                      alignment: Alignment.center,
                      child: Icon(Icons.hourglass_empty_rounded, color: AppColors.mut, size: 22),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: has ? AppColors.txt : AppColors.mut, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }

  void _openPhoto(String url, String label) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.network(url, fit: BoxFit.contain)),
              ),
            ),
            Positioned(
              top: 44,
              left: 20,
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Positioned(
              top: 34,
              right: 12,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Standalone "Offer Washes" page — opened from the drawer's My Bookings
/// when the customer has no vehicle yet (offer washes don't need one).
class OfferBookingsScreen extends StatelessWidget {
  const OfferBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceRaised,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.txt),
        title: const Text(
          'My Bookings',
          style: TextStyle(color: Color(0xFFD4A017), fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: const [OfferBookingsSection(showEmpty: true)],
        ),
      ),
    );
  }
}
