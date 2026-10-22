import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/booking_tracking_screen.dart';
import '../theme/app_colors.dart';
import 'error_display.dart';

const _gold = Color(0xFFD4A017);
const _green = Color(0xFF2E9E5B);

/// The customer's ReperiResolve (after-service issue) requests for one
/// vehicle — shown on the vehicle's bookings page. Shows nothing when there
/// are none. Includes requests saved without a vehicle too.
class ResolveRequestsSection extends StatefulWidget {
  const ResolveRequestsSection({super.key, this.vehicleId});

  final String? vehicleId;

  @override
  State<ResolveRequestsSection> createState() => _ResolveRequestsSectionState();
}

class _ResolveRequestsSectionState extends State<ResolveRequestsSection> {
  List<Map<String, dynamic>> _rows = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // A price sent from the CRM shows up without leaving the screen.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      var q = Supabase.instance.client.from('resolve_requests').select('*').eq('user_id', uid);
      final vid = widget.vehicleId;
      if (vid != null && vid.isNotEmpty) {
        q = q.or('vehicle_id.eq.$vid,vehicle_id.is.null');
      }
      final res = await q.order('created_at', ascending: false).limit(20);
      if (!mounted) return;
      setState(() => _rows = List<Map<String, dynamic>>.from(res as List));
    } catch (e) {
      debugPrint('Error loading ReperiResolve requests: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'After-Service Issues',
          style: TextStyle(color: AppColors.txt, fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 24),
        ..._rows.map((r) => ResolveRequestCard(
              key: ValueKey('${r['id']}-${r['quoted_at']}-${r['status']}'),
              request: r,
              onChanged: _load,
            )),
      ],
    );
  }
}

/// One ReperiResolve request: what the customer reported, and — once your
/// team has replied from the CRM — the price, message and photo, with an
/// "Accept this price" button.
class ResolveRequestCard extends StatefulWidget {
  const ResolveRequestCard({super.key, required this.request, this.onChanged});

  final Map<String, dynamic> request;
  final VoidCallback? onChanged;

  @override
  State<ResolveRequestCard> createState() => _ResolveRequestCardState();
}

class _ResolveRequestCardState extends State<ResolveRequestCard> {
  String? _imageUrl;
  bool _accepting = false;

  Map<String, dynamic> get r => widget.request;

  /// The repair booking made once the price is accepted and a garage is
  /// assigned — shown as a sub-order that opens the normal tracking screen.
  Map<String, dynamic>? _booking;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    final id = (r['booking_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final row = await Supabase.instance.client.from('bookings').select('*').eq('id', id).maybeSingle();
      if (mounted && row != null) setState(() => _booking = row);
    } catch (e) {
      debugPrint('Could not load repair booking: $e');
    }
  }

  void _openBooking() {
    final b = _booking;
    if (b == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookingTrackingScreen(booking: b)),
    ).then((_) => _loadBooking());
  }

  Widget _subOrder() {
    final b = _booking!;
    final status = (b['booking_status'] ?? 'Pending').toString();
    final hasUpdate = b['has_unread_update'] == true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openBooking,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _gold.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withOpacity(0.55)),
          ),
          child: Row(
            children: [
              Icon(Icons.subdirectory_arrow_right_rounded, color: AppColors.mut, size: 20),
              const SizedBox(width: 6),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: _gold.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.build_rounded, color: _gold, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Repair booking',
                        style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      status == 'Pending' ? 'Garage assigned · tap to track' : '$status · tap to see photos & updates',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.3),
                    ),
                  ],
                ),
              ),
              if (hasUpdate) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8)),
                  child: const Text('NEW',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: _gold),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadImage() async {
    final path = (r['quote_image_path'] ?? '').toString();
    if (path.isEmpty) return;
    try {
      final url = await Supabase.instance.client.storage.from('resolve-media').createSignedUrl(path, 3600);
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      debugPrint('Could not load quote photo: $e');
    }
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      await Supabase.instance.client.rpc('accept_resolve_quote', params: {'p_id': r['id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Price accepted! We'll call you to fix a time.")),
      );
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(context, error: e, customMessage: "Couldn't accept the price. Please try again.");
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  /// Signed links for the customer's own files and the garage's photos,
  /// made once per file.
  final Map<String, Future<String?>> _links = {};
  Future<String?> _link(String bucket, String path) => _links.putIfAbsent('$bucket/$path', () async {
        try {
          return await Supabase.instance.client.storage.from(bucket).createSignedUrl(path, 3600);
        } catch (_) {
          return null;
        }
      });

  void _openImage([String? override]) {
    final url = override ?? _imageUrl;
    if (url == null) return;
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

  static String _money(dynamic v) {
    final n = num.tryParse(v.toString());
    if (n == null) return v.toString();
    final whole = n == n.roundToDouble();
    final s = whole ? n.toInt().toString() : n.toStringAsFixed(2);
    // Indian grouping: 1,23,456
    final parts = s.split('.');
    var d = parts[0];
    if (d.length > 3) {
      final last3 = d.substring(d.length - 3);
      var rest = d.substring(0, d.length - 3);
      final buf = <String>[];
      while (rest.length > 2) {
        buf.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) buf.insert(0, rest);
      d = '${buf.join(',')},$last3';
    }
    return parts.length > 1 ? '$d.${parts[1]}' : d;
  }

  static String _date(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  /// Small square thumbnails; tap a photo to zoom, a video to play it.
  Widget _thumbs(List<(String, String, bool)> files) {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final (bucket, path, isVideo) in files)
          FutureBuilder<String?>(
            future: _link(bucket, path),
            builder: (context, snap) {
              final url = snap.data;
              return GestureDetector(
                onTap: url == null
                    ? null
                    : () => isVideo
                        ? launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
                        : _openImage(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: isVideo || url == null
                      ? Container(
                          color: AppColors.chipBg,
                          alignment: Alignment.center,
                          child: isVideo
                              ? Icon(Icons.play_circle_fill_rounded, color: AppColors.txt, size: 28)
                              : (snap.connectionState == ConnectionState.done
                                  ? Icon(Icons.broken_image_outlined, color: AppColors.mut)
                                  : const SizedBox(
                                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _gold))),
                        )
                      : Image.network(url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: AppColors.chipBg)),
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = (r['status'] ?? 'Submitted').toString();
    final cats = (r['categories'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final desc = (r['description'] ?? '').toString();
    final title = cats.isNotEmpty ? cats.join(' · ') : (desc.isNotEmpty ? desc : 'After-service issue');
    // Customer pays the repair price + the pickup & drop fee (always included).
    final base = num.tryParse('${r['quoted_price']}');
    final fee = num.tryParse('${r['pickup_fee'] ?? ''}') ?? 0;
    final price = r['quoted_price'] == null ? null : (base ?? 0) + fee;
    final note = (r['quote_note'] ?? '').toString();
    final media = ((r['media'] as List?) ?? const []).whereType<Map>().toList();
    final mediaCount = media.length;
    final garagePhotos = ((r['garage_photos'] as List?) ?? const []).map((e) => '$e').toList();
    final hasPrice = price != null && (status == 'Quoted' || status == 'Accepted' || status == 'Closed');

    final (String label, Color color) = switch (status) {
      'Quoted' => ('Price ready', _green),
      'Accepted' => ("Accepted — we'll call you", _gold),
      'Closed' => ('Done', AppColors.mut),
      'Cancelled' => ('Cancelled', AppColors.mut),
      _ => ('Waiting for price', _gold),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: status == 'Quoted' ? _green.withOpacity(0.6) : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.txt, fontSize: 17, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          if (cats.isNotEmpty && desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.mut, fontSize: 13.5, height: 1.35)),
          ],
          const SizedBox(height: 8),
          Text(
            [
              _date(r['created_at']),
              if (mediaCount > 0) '$mediaCount file${mediaCount == 1 ? '' : 's'} sent',
              if (r['dealer_quote_amount'] != null) 'Dealer quote ₹${_money(r['dealer_quote_amount'])}',
            ].join(' · '),
            style: TextStyle(color: AppColors.mut, fontSize: 12.5),
          ),
          if (media.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('YOUR PHOTOS & VIDEOS',
                style: TextStyle(color: AppColors.mut, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            _thumbs([for (final m in media) ('resolve-media', '${m['path']}', m['type'] == 'video')]),
          ],
          if (!hasPrice && status == 'Submitted') ...[
            const SizedBox(height: 12),
            Text("We're checking your photos and will send a fixed price soon.",
                style: TextStyle(color: AppColors.txt, fontSize: 13.5, height: 1.35)),
          ],
          if (hasPrice) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OUR PRICE',
                      style: TextStyle(
                          color: AppColors.mut, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text('₹${_money(price)}',
                          style: const TextStyle(color: _gold, fontSize: 30, fontWeight: FontWeight.w900)),
                      if (r['dealer_quote_amount'] != null &&
                          (num.tryParse(r['dealer_quote_amount'].toString()) ?? 0) >
                              (num.tryParse(price.toString()) ?? 0)) ...[
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Save ₹${_money((num.parse(r['dealer_quote_amount'].toString()) - num.parse(price.toString())))}',
                            style: const TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (fee > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.local_shipping_rounded, size: 15, color: AppColors.mut),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Repair ₹${_money(base ?? 0)} + pickup & drop ₹${_money(fee)} — we collect and return your vehicle',
                            style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(note, style: TextStyle(color: AppColors.txt, fontSize: 14, height: 1.45)),
                  ],
                  if (garagePhotos.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('PHOTOS FROM THE GARAGE',
                        style: TextStyle(color: AppColors.mut, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    _thumbs([for (final p in garagePhotos) ('booking-images', p, false)]),
                  ],
                  if (_imageUrl != null) ...[
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _openImage,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: Image.network(
                            _imageUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (c, child, p) => p == null
                                ? child
                                : Container(
                                    color: AppColors.chipBg,
                                    alignment: Alignment.center,
                                    child: const CircularProgressIndicator(strokeWidth: 2, color: _gold),
                                  ),
                            errorBuilder: (c, e, s) => Container(
                              color: AppColors.chipBg,
                              alignment: Alignment.center,
                              child: Icon(Icons.broken_image_outlined, color: AppColors.mut),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Tap the photo to zoom', style: TextStyle(color: AppColors.mut, fontSize: 11.5)),
                  ],
                ],
              ),
            ),
          ],
          if (status == 'Quoted') ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _accepting ? null : _accept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _green.withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _accepting
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Accept this price', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
          ],
          if (status == 'Accepted' && _booking == null) ...[
            const SizedBox(height: 12),
            Text("Thanks! Our team will call you to fix a time.",
                style: TextStyle(color: AppColors.txt, fontSize: 13.5)),
          ],
          if (_booking != null) ...[
            const SizedBox(height: 14),
            _subOrder(),
          ],
        ],
      ),
    );
  }
}
