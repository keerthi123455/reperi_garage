import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/secure_storage_path.dart';

/// Garage side of add-on services, for the booking details screen:
/// a blue "ADD-ON SERVICE" button (yellow text) that opens a sheet to send
/// the customer a photo + description + price, and the list of add-ons
/// already sent with their status (waiting / paid / rejected + reason).
/// Hidden for roadside assistance bookings.
class GarageAddonsSection extends StatefulWidget {
  const GarageAddonsSection({super.key, required this.booking});

  final Map booking;

  @override
  State<GarageAddonsSection> createState() => _GarageAddonsSectionState();
}

const Color _kBlue = Color(0xFF1E5EFF);
const Color _kBlueDark = Color(0xFF123A9E);
const Color _kYellow = Color(0xFFFFD23F);
const Color _kCard = Color(0xFF1C1C1C);
const Color _kGreen = Color(0xFF2FB36A);
const Color _kRed = Color(0xFFE5484D);

class _GarageAddonsSectionState extends State<GarageAddonsSection> {
  List<Map<String, dynamic>> _addons = const [];
  String? _adminId;
  Timer? _poll;

  bool get _isRoadside =>
      (widget.booking['package_name'] ?? '').toString().toLowerCase().startsWith('roadside assistance');

  bool get _closed {
    final s = (widget.booking['booking_status'] ?? '').toString();
    return s == 'Delivered' || s == 'Completed' || s == 'Cancelled';
  }

  @override
  void initState() {
    super.initState();
    if (_isRoadside) return;
    _init();
    // Picks up the customer's approve/pay or reject while the screen is open.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _adminId = prefs.getString('admin_id');
    } catch (_) {}
    _adminId ??= widget.booking['assigned_to_admin_id']?.toString();
    await _load();
  }

  Future<void> _load() async {
    final adminId = _adminId;
    if (adminId == null || !mounted) return;
    try {
      final rows = await Supabase.instance.client.rpc('garage_list_addons', params: {
        'p_booking_id': widget.booking['id'].toString(),
        'p_admin_id': adminId,
      });
      if (!mounted) return;
      setState(() => _addons = List<Map<String, dynamic>>.from(rows as List));
    } catch (e) {
      debugPrint('garage_list_addons failed: $e');
    }
  }

  Future<void> _openSheet() async {
    HapticFeedback.selectionClick();
    final adminId = _adminId;
    if (adminId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in again to send add-ons.')),
      );
      return;
    }
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddonSheet(bookingId: widget.booking['id'].toString(), adminId: adminId),
    );
    if (sent == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add-on sent — customer notified to approve & pay')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRoadside) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_closed) _button(),
        if (_addons.isNotEmpty) ...[
          const SizedBox(height: 10),
          _list(),
        ],
      ],
    );
  }

  Widget _button() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openSheet,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_kBlue, _kBlueDark]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kYellow.withOpacity(0.6), width: 1.2),
            boxShadow: [BoxShadow(color: _kBlue.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.add_circle_rounded, color: _kYellow, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ADD-ON SERVICE',
                      maxLines: 1,
                      style: TextStyle(color: _kYellow, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: _kYellow),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list() {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _addons.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Colors.white10),
            _row(_addons[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> a) {
    final status = (a['status'] ?? '').toString();
    final (String pill, Color color) = switch (status) {
      'Paid' => ('PAID', _kGreen),
      'Rejected' => ('REJECTED', _kRed),
      'Approved' => ('PAYING…', _kYellow),
      _ => ('WAITING', _kYellow),
    };
    final price = (a['package_price'] ?? '₹${a['price'] ?? ''}').toString();
    final reason = (a['reject_reason'] ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  (a['package_name'] ?? '').toString(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.3),
                ),
              ),
              const SizedBox(width: 8),
              Text(price, style: const TextStyle(color: Color(0xFFD4A017), fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(pill,
                    style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
              ),
            ],
          ),
          if (status == 'Rejected' && reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Customer: "$reason"', style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.35)),
          ] else if ((a['description'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(a['description'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

/// Photo + what's needed + description + price → sends to the customer.
class _AddonSheet extends StatefulWidget {
  const _AddonSheet({required this.bookingId, required this.adminId});

  final String bookingId;
  final String adminId;

  @override
  State<_AddonSheet> createState() => _AddonSheetState();
}

class _AddonSheetState extends State<_AddonSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  Uint8List? _photo;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final img = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600);
      if (img == null) return;
      final bytes = await img.readAsBytes();
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t open the camera / gallery.');
    }
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final price = int.tryParse(_price.text.trim());
    final problem = title.isEmpty
        ? 'Say what the add-on is.'
        : (price == null || price <= 0)
            ? 'Enter the price in rupees.'
            : _photo == null
                ? 'Add a photo so the customer can see it.'
                : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final path = 'addon-${DateTime.now().millisecondsSinceEpoch}-${secureStorageToken()}';
      await client.storage.from('booking-images').uploadBinary(path, _photo!);
      await client.rpc('garage_request_addon', params: {
        'p_booking_id': widget.bookingId,
        'p_admin_id': widget.adminId,
        'p_title': title,
        'p_description': _desc.text.trim(),
        'p_price': price,
        'p_image_path': path,
      });
      if (mounted) Navigator.of(context).pop(true);
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
          _error = 'Couldn\'t send the add-on. Please try again.';
        });
      }
    }
  }

  InputDecoration _dec(String label, {String? hint, String? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        labelStyle: const TextStyle(color: Colors.white60),
        hintStyle: const TextStyle(color: Colors.white30),
        prefixStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        counterStyle: const TextStyle(color: Colors.white38),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kYellow),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final keyboard = kIsWeb ? 0.0 : MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        decoration: const BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('ADD-ON SERVICE',
                    style: TextStyle(color: _kYellow, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 4),
                const Text(
                  'The customer gets a notification and approves & pays this amount in the app.',
                  style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                _photoBox(),
                const SizedBox(height: 14),
                TextField(
                  controller: _title,
                  enabled: !_sending,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dec('What\'s needed', hint: 'e.g. Front brake pads replacement'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _desc,
                  enabled: !_sending,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dec('Description', hint: 'Why it\'s needed, what you\'ll do'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _price,
                  enabled: !_sending,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  decoration: _dec('Price (total, incl. parts & labour)', prefix: '₹ '),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: _kRed, fontSize: 13, height: 1.35)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBlue,
                      disabledBackgroundColor: _kBlue.withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: _kYellow))
                        : const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('SEND TO CUSTOMER',
                                maxLines: 1,
                                style: TextStyle(
                                    color: _kYellow, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoBox() {
    if (_photo != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(aspectRatio: 16 / 10, child: Image.memory(_photo!, fit: BoxFit.cover)),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _sending ? null : () => setState(() => _photo = null),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    Widget pickTile(IconData icon, String label, ImageSource src) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _pick(src),
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kYellow.withOpacity(0.35)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: _kYellow, size: 26),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        maxLines: 1,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        );
    return Row(
      children: [
        pickTile(Icons.photo_camera_rounded, 'Take photo', ImageSource.camera),
        const SizedBox(width: 10),
        pickTile(Icons.photo_library_rounded, 'Gallery', ImageSource.gallery),
      ],
    );
  }
}
