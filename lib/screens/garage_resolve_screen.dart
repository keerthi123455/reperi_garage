import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'booking_details_screen.dart';

/// Garage app: a ReperiResolve request whose price (sent from the CRM) the
/// customer has accepted. Shows what the customer sent (photos, videos,
/// dealer quote, text) and the agreed price, and opens the repair booking —
/// where the normal pickup, photos, stages and Work done happen.
class GarageResolveScreen extends StatefulWidget {
  const GarageResolveScreen({super.key, required this.request, required this.adminId});

  final Map request;
  final String adminId;

  @override
  State<GarageResolveScreen> createState() => _GarageResolveScreenState();
}

class _GarageResolveScreenState extends State<GarageResolveScreen> {
  static const Color _bg = Color(0xFF141414);
  static const Color _card = Color(0xFF1C1C1C);
  static const Color _gold = Color(0xFFD4A017);
  static const Color _green = Color(0xFF2FB36A);

  late Map r = Map.of(widget.request);

  /// Signed links, made once per file.
  final Map<String, Future<String?>> _links = {};

  String get _status => (r['status'] ?? 'Submitted').toString();

  static String _plain(dynamic v) {
    final n = num.tryParse('$v');
    if (n == null) return '$v';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  Future<String?> _link(String bucket, String path) => _links.putIfAbsent('$bucket/$path', () async {
        try {
          return await Supabase.instance.client.storage.from(bucket).createSignedUrl(path, 3600);
        } catch (_) {
          return null;
        }
      });

  Future<void> _reload() async {
    try {
      final rows = await Supabase.instance.client
          .rpc('garage_resolve_requests', params: {'p_admin_id': widget.adminId});
      final match = (rows as List).cast<Map>().where((x) => '${x['id']}' == '${r['id']}');
      if (match.isNotEmpty && mounted) setState(() => r = Map.of(match.first));
    } catch (_) {}
  }

  /// The normal garage booking screen for the repair (photos, stages, OTPs).
  Future<void> _openBooking() async {
    final id = (r['booking_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final b = await Supabase.instance.client.from('bookings').select('*').eq('id', id).maybeSingle();
      if (!mounted) return;
      if (b == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking not found — pull to refresh.')));
        return;
      }
      await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailsScreen(booking: b)));
      _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open the booking.')));
      }
    }
  }

  Future<void> _openUrl(String? url) async {
    if (url == null) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _viewImage(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(maxScale: 5, child: Center(child: Image.network(url, fit: BoxFit.contain))),
            ),
            Positioned(
              top: 40,
              right: 16,
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

  @override
  Widget build(BuildContext context) {
    final cats = (r['categories'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final desc = (r['description'] ?? '').toString().trim();
    final media = ((r['media'] as List?) ?? const []).whereType<Map>().toList();
    final garagePhotos = ((r['garage_photos'] as List?) ?? const []).map((e) => '$e').toList();
    final phone = (r['customer_phone'] ?? '').toString().trim();
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('ReperiResolve', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            color: _gold,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 8, 16, 96 + bottom),
              children: [
                // ── Summary ──
                _box(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              cats.isNotEmpty ? cats.join(' · ') : 'Problem reported',
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _statusPill(),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _info(Icons.directions_car_rounded, (r['vehicle_label'] ?? 'Vehicle').toString()),
                      _info(Icons.person_rounded, (r['customer_name'] ?? 'Customer').toString()),
                      if (r['dealer_quote_amount'] != null)
                        _info(Icons.receipt_long_rounded, 'Dealer quoted ₹${_plain(r['dealer_quote_amount'])}'),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _green,
                              side: const BorderSide(color: _green),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => _openUrl('tel:$phone'),
                            icon: const Icon(Icons.call_rounded, size: 18),
                            label: Text('Call customer · $phone', overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (desc.isNotEmpty) ...[
                  _label('CUSTOMER SAYS'),
                  _box(child: Text(desc, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.45))),
                ],

                // ── Customer files ──
                _label('PHOTOS & VIDEOS FROM THE CUSTOMER'),
                if (media.isEmpty && (r['dealer_quote_path'] ?? '').toString().isEmpty)
                  _box(child: const Text('No files sent', style: TextStyle(color: Colors.white54)))
                else
                  _grid([
                    for (final m in media)
                      _fileTile('resolve-media', '${m['path']}', isVideo: m['type'] == 'video'),
                    if ((r['dealer_quote_path'] ?? '').toString().isNotEmpty)
                      _fileTile('resolve-media', '${r['dealer_quote_path']}', caption: 'Dealer quote'),
                  ]),

                // ── What was sent ──
                if (r['quoted_price'] != null) ...[
                  _label('AGREED WITH THE CUSTOMER'),
                  _box(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('₹${_plain(r['quoted_price'])}',
                            style: const TextStyle(color: _gold, fontSize: 28, fontWeight: FontWeight.w900)),
                        Text(
                          'Customer pays ₹${_plain((num.tryParse('${r['quoted_price']}') ?? 0) + (num.tryParse('${r['pickup_fee'] ?? 100}') ?? 100))} incl. pickup & drop',
                          style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                        ),
                        if ((r['quote_note'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('${r['quote_note']}', style: const TextStyle(color: Colors.white70, height: 1.4)),
                        ],
                        if (garagePhotos.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _grid([for (final p in garagePhotos) _fileTile('booking-images', p)], padded: false),
                        ],
                        if (_status == 'Accepted') ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: _green.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              (r['booking_id'] ?? '').toString().isEmpty
                                  ? '✅ Customer accepted this price — call them to fix a time.'
                                  : '✅ Customer accepted — a pickup & drop repair booking is now in your CLIENT list. Our delivery partner brings the car; then photos, stages and Work done like any booking.',
                              style: const TextStyle(color: _green, fontWeight: FontWeight.w800, height: 1.35),
                            ),
                          ),
                          if ((r['booking_id'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _openBooking,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _green,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                icon: const Icon(Icons.build_rounded, size: 20),
                                label: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('OPEN REPAIR BOOKING',
                                      maxLines: 1, style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],

                // Prices are sent from the CRM; the garage only sees this once the
                // customer has accepted, and does the work on the repair booking.
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── pieces ──
  Widget _statusPill() {
    final (String t, Color c) = switch (_status) {
      'Quoted' => ('PRICE SENT', const Color(0xFF4D8DFF)),
      'Accepted' => ('ACCEPTED', _green),
      'Closed' => ('CLOSED', Colors.white54),
      'Cancelled' => ('CANCELLED', Colors.white54),
      _ => ('NEEDS PRICE', _gold),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
    );
  }

  Widget _box({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: child,
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(t,
            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: _gold),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.3))),
          ],
        ),
      );

  Widget _grid(List<Widget> tiles, {bool padded = true}) {
    final g = GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
    return padded ? _box(child: g) : g;
  }

  Widget _fileTile(String bucket, String path, {bool isVideo = false, String? caption}) {
    return FutureBuilder<String?>(
      future: _link(bucket, path),
      builder: (context, snap) {
        final url = snap.data;
        Widget inner;
        if (isVideo) {
          inner = Container(
            color: Colors.white10,
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 34),
                SizedBox(height: 4),
                Text('Play video', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ),
          );
        } else if (url == null) {
          inner = Container(
            color: Colors.white10,
            alignment: Alignment.center,
            child: snap.connectionState == ConnectionState.done
                ? const Icon(Icons.broken_image_outlined, color: Colors.white38)
                : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _gold)),
          );
        } else {
          inner = Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.white10));
        }
        return GestureDetector(
          onTap: url == null ? null : () => isVideo ? _openUrl(url) : _viewImage(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                inner,
                if (caption != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(caption,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
