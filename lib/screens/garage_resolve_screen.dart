import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/secure_storage_path.dart';

/// Garage app: one ReperiResolve request assigned to this garage from the
/// CRM. Shows what the customer sent (photos, videos, dealer quote, text)
/// and lets the garage send back photos + a price + a note. The customer
/// is notified and can accept the price in their app.
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
  static const Color _red = Color(0xFFE5484D);
  static const int _maxPhotos = 6;

  late Map r = Map.of(widget.request);
  final _price = TextEditingController();
  final _note = TextEditingController();
  final List<Uint8List> _newPhotos = [];
  bool _sending = false;
  String? _error;

  /// Signed links, made once per file.
  final Map<String, Future<String?>> _links = {};

  @override
  void initState() {
    super.initState();
    if (r['quoted_price'] != null) _price.text = _plain(r['quoted_price']);
    _note.text = (r['quote_note'] ?? '').toString();
  }

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _status => (r['status'] ?? 'Submitted').toString();
  bool get _closed => _status == 'Closed' || _status == 'Cancelled';

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

  Future<void> _pick(ImageSource source) async {
    if (_newPhotos.length >= _maxPhotos) return;
    try {
      final picker = ImagePicker();
      if (source == ImageSource.gallery) {
        final files = await picker.pickMultiImage(imageQuality: 70, maxWidth: 1600);
        for (final f in files.take(_maxPhotos - _newPhotos.length)) {
          _newPhotos.add(await f.readAsBytes());
        }
      } else {
        final f = await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1600);
        if (f != null) _newPhotos.add(await f.readAsBytes());
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t open the camera / gallery.');
    }
  }

  Future<void> _send() async {
    final price = num.tryParse(_price.text.trim());
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter the price in rupees.');
      return;
    }
    final hasOldPhotos = (r['garage_photos'] as List?)?.isNotEmpty ?? false;
    if (_newPhotos.isEmpty && !hasOldPhotos) {
      setState(() => _error = 'Add at least one photo so the customer can see the problem.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final paths = <String>[];
      for (var i = 0; i < _newPhotos.length; i++) {
        final path = 'resolve-${DateTime.now().millisecondsSinceEpoch}-${secureStorageToken()}-$i';
        await client.storage.from('booking-images').uploadBinary(
              path,
              _newPhotos[i],
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
        paths.add(path);
      }
      await client.rpc('garage_quote_resolve', params: {
        'p_id': '${r['id']}',
        'p_admin_id': widget.adminId,
        'p_price': price,
        'p_note': _note.text.trim(),
        'p_photos': paths,
      });
      _newPhotos.clear();
      await _reload();
      if (!mounted) return;
      setState(() => _sending = false);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent — the customer has been notified')),
      );
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Couldn\'t send. Please try again.';
        });
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  _label('SENT TO THE CUSTOMER'),
                  _box(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('₹${_plain(r['quoted_price'])}',
                            style: const TextStyle(color: _gold, fontSize: 28, fontWeight: FontWeight.w900)),
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
                            child: const Text('✅ Customer accepted this price — call them to fix a time.',
                                style: TextStyle(color: _green, fontWeight: FontWeight.w800, height: 1.35)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // ── Send photos + price ──
                if (!_closed) ...[
                  _label(r['quoted_price'] != null ? 'UPDATE PHOTOS & PRICE' : 'SEND PHOTOS & PRICE'),
                  _box(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('1. Add photos of the problem',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 10),
                        _newPhotoGrid(),
                        if (garagePhotos.isNotEmpty && _newPhotos.isEmpty) ...[
                          const SizedBox(height: 6),
                          const Text('No new photos → the photos already sent stay.',
                              style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                        const SizedBox(height: 16),
                        const Text('2. Your price',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _price,
                          enabled: !_sending,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                          decoration: _dec('Total price incl. parts & labour', prefix: '₹ '),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _note,
                          enabled: !_sending,
                          minLines: 2,
                          maxLines: 5,
                          maxLength: 1000,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(color: Colors.white),
                          decoration: _dec('Note: what you\'ll fix, parts, time needed'),
                        ),
                        if (_error != null) ...[
                          Text(_error!, style: const TextStyle(color: _red, fontSize: 13, height: 1.35)),
                          const SizedBox(height: 8),
                        ],
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _sending ? null : _send,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              disabledBackgroundColor: _gold.withOpacity(0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _sending
                                ? const SizedBox(
                                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      r['quoted_price'] != null ? 'UPDATE & NOTIFY CUSTOMER' : 'SEND TO CUSTOMER',
                                      maxLines: 1,
                                      style: const TextStyle(
                                          color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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

  Widget _newPhotoGrid() {
    final tiles = <Widget>[
      for (var i = 0; i < _newPhotos.length; i++)
        Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_newPhotos[i], fit: BoxFit.cover)),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: _sending ? null : () => setState(() => _newPhotos.removeAt(i)),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        ),
      if (_newPhotos.length < _maxPhotos && !kIsWeb) _addTile(Icons.photo_camera_rounded, 'Camera', ImageSource.camera),
      if (_newPhotos.length < _maxPhotos) _addTile(Icons.photo_library_rounded, 'Gallery', ImageSource.gallery),
    ];
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }

  Widget _addTile(IconData icon, String label, ImageSource src) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _sending ? null : () => _pick(src),
        child: Container(
          decoration: BoxDecoration(
            color: _gold.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withOpacity(0.5), width: 1.4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _gold, size: 26),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
            ],
          ),
        ),
      );

  InputDecoration _dec(String hint, {String? prefix}) => InputDecoration(
        hintText: hint,
        prefixText: prefix,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
        prefixStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        counterStyle: const TextStyle(color: Colors.white38),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
