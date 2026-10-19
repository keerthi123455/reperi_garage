import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _loadImage();
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

  void _openImage() {
    final url = _imageUrl;
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

  @override
  Widget build(BuildContext context) {
    final status = (r['status'] ?? 'Submitted').toString();
    final cats = (r['categories'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final desc = (r['description'] ?? '').toString();
    final title = cats.isNotEmpty ? cats.join(' · ') : (desc.isNotEmpty ? desc : 'After-service issue');
    final price = r['quoted_price'];
    final note = (r['quote_note'] ?? '').toString();
    final mediaCount = (r['media'] as List?)?.length ?? 0;
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
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
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(note, style: TextStyle(color: AppColors.txt, fontSize: 14, height: 1.45)),
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
          if (status == 'Accepted') ...[
            const SizedBox(height: 12),
            Text("Thanks! Our team will call you to fix a time.",
                style: TextStyle(color: AppColors.txt, fontSize: 13.5)),
          ],
        ],
      ),
    );
  }
}
