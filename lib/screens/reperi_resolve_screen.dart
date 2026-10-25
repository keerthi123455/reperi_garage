import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import '../widgets/call_expert_button.dart';
import '../widgets/error_display.dart';
import '../widgets/resolve_requests_list.dart';
import '../widgets/requirements.dart';

/// ReperiResolve — "Problem after a service? Show us, get a fixed price."
///
/// The customer:
///   1. adds photos / a short video of the problem,
///   2. taps what's wrong (chips) and/or types a line,
///   3. optionally adds the dealer's quote,
/// then taps "Send". Everything is saved to `resolve_requests` (files go to
/// the private `resolve-media` bucket). Your team types a price into that
/// row; the customer is notified and can accept it right here.
class ReperiResolveScreen extends StatefulWidget {
  const ReperiResolveScreen({super.key, this.vehicleId, this.vehicleLabel});

  final String? vehicleId;

  /// e.g. "Hyundai Creta · KA01AB1234" — shown on the screen and saved
  /// with the request so your team knows which car it is.
  final String? vehicleLabel;

  @override
  State<ReperiResolveScreen> createState() => _ReperiResolveScreenState();
}

class _Picked {
  _Picked(this.file, this.isVideo, this.bytes);
  final XFile file;
  final bool isVideo;
  final Uint8List bytes;
}

class _ReperiResolveScreenState extends State<ReperiResolveScreen> {
  static const _gold = Color(0xFFD4A017);
  static const _green = Color(0xFF2E9E5B);
  static const _maxItems = 6;
  static const _maxBytes = 50 * 1024 * 1024; // 50 MB per file
  static const _bucket = 'resolve-media';

  static const _problems = <String>[
    'Water leak',
    'Brake noise',
    'Rattle / noise',
    'AC problem',
    'Warning light',
    'Electrical',
    'Other',
  ];

  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  final _desc = TextEditingController();
  final _quoteAmount = TextEditingController();

  final List<_Picked> _media = [];
  final Set<String> _chips = {};
  _Picked? _quotePhoto;

  bool _sending = false;
  String _progress = '';
  bool _sent = false;

  List<Map<String, dynamic>> _requests = const [];

  @override
  void initState() {
    super.initState();
    _desc.addListener(() => setState(() {}));
    _loadRequests();
  }

  @override
  void dispose() {
    _desc.dispose();
    _quoteAmount.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────

  Future<void> _loadRequests() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final res = await _supabase
          .from('resolve_requests')
          .select('*')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      setState(() => _requests = List<Map<String, dynamic>>.from(res as List));
    } catch (e) {
      debugPrint('Error loading ReperiResolve requests: $e');
    }
  }

  bool get _canSend =>
      !_sending && (_media.isNotEmpty || _chips.isNotEmpty || _desc.text.trim().isNotEmpty);

  static String _ext(XFile f, bool isVideo) {
    final name = f.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) return name.substring(dot + 1);
    return isVideo ? 'mp4' : 'jpg';
  }

  static String _mime(String ext, bool isVideo) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      default:
        return isVideo ? 'video/mp4' : 'image/jpeg';
    }
  }

  Future<String> _upload(String folder, String name, _Picked p) async {
    final ext = _ext(p.file, p.isVideo);
    final path = '$folder/$name.$ext';
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _supabase.storage.from(_bucket).uploadBinary(
              path,
              p.bytes,
              fileOptions: FileOptions(contentType: _mime(ext, p.isVideo), upsert: true),
            );
        return path;
      } catch (e) {
        lastError = e;
        if (attempt < 3) await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw Exception('Upload failed: $lastError');
  }

  Future<void> _send() async {
    if (!_canSend) return;
    // Guest: sign up right here — everything they added stays on screen.
    // Your photos and text stay right here while you sign up.
    if (!await ensureReady(context, contact: true)) return;
    if (!mounted) return;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _progress = 'Sending…';
    });
    try {
      final folder = '$uid/${DateTime.now().millisecondsSinceEpoch}';
      final media = <Map<String, String>>[];
      for (var i = 0; i < _media.length; i++) {
        if (mounted) setState(() => _progress = 'Uploading ${i + 1} of ${_media.length}…');
        final path = await _upload(folder, 'm$i', _media[i]);
        media.add({'path': path, 'type': _media[i].isVideo ? 'video' : 'image'});
      }
      String? quotePath;
      if (_quotePhoto != null) {
        if (mounted) setState(() => _progress = 'Uploading quote…');
        quotePath = await _upload(folder, 'quote', _quotePhoto!);
      }

      // Name + phone so your team can call back without looking them up.
      Map<String, dynamic>? profile;
      try {
        profile = await _supabase.from('profiles').select('name, phone').eq('id', uid).maybeSingle();
      } catch (_) {}

      final amount = double.tryParse(_quoteAmount.text.replaceAll(RegExp(r'[^0-9.]'), ''));
      await _supabase.from('resolve_requests').insert({
        'user_id': uid,
        if (widget.vehicleId != null && widget.vehicleId!.isNotEmpty) 'vehicle_id': widget.vehicleId,
        if (widget.vehicleLabel != null) 'vehicle_label': widget.vehicleLabel,
        'customer_name': profile?['name'],
        'customer_phone': profile?['phone'],
        'categories': _chips.toList(),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'media': media,
        if (amount != null && amount > 0) 'dealer_quote_amount': amount,
        if (quotePath != null) 'dealer_quote_path': quotePath,
      });

      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
        _media.clear();
        _chips.clear();
        _desc.clear();
        _quoteAmount.clear();
        _quotePhoto = null;
      });
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: "Couldn't send your request. Please check your internet and try again.",
      );
    }
  }

  // ── Picking ────────────────────────────────────────────────────────────

  Future<void> _addMedia() async {
    if (_media.length >= _maxItems) {
      _toast('You can add up to $_maxItems photos or videos.');
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetTile(ctx, Icons.photo_camera_rounded, 'Take a photo', 'camera'),
              _sheetTile(ctx, Icons.photo_library_rounded, 'Choose photos', 'photos'),
              _sheetTile(ctx, Icons.videocam_rounded, 'Record a video', 'record',
                  subtitle: 'Best for noises — up to 1 minute'),
              _sheetTile(ctx, Icons.video_library_rounded, 'Choose a video', 'video'),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'camera') {
        final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
        if (f != null) await _addFile(f, false);
      } else if (choice == 'photos') {
        final files = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 1600);
        for (final f in files.take(_maxItems - _media.length)) {
          await _addFile(f, false);
        }
      } else if (choice == 'record') {
        final f = await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 1));
        if (f != null) await _addFile(f, true);
      } else {
        final f = await _picker.pickVideo(source: ImageSource.gallery);
        if (f != null) await _addFile(f, true);
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(context, error: e, customMessage: 'Could not add that file. Please try again.');
      }
    }
  }

  Future<void> _addFile(XFile f, bool isVideo) async {
    if (await f.length() > _maxBytes) {
      _toast(isVideo ? 'That video is too big. Please keep it under 1 minute.' : 'That photo is too big.');
      return;
    }
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() => _media.add(_Picked(f, isVideo, bytes)));
  }

  Future<void> _pickQuotePhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: _gold),
              title: Text('Take a photo of the quote', style: TextStyle(color: AppColors.txt)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: _gold),
              title: Text('Choose from gallery', style: TextStyle(color: AppColors.txt)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ]),
        ),
      ),
    );
    if (src == null) return;
    try {
      final f = await _picker.pickImage(source: src, imageQuality: 80, maxWidth: 1800);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (mounted) setState(() => _quotePhoto = _Picked(f, false, bytes));
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(context, error: e, customMessage: 'Could not add that photo. Please try again.');
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceRaised,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.txt),
        title: const Text('ReperiResolve', style: TextStyle(color: _gold, fontWeight: FontWeight.w900)),
      ),
      body: _sent ? _sentView() : _formView(),
      bottomNavigationBar: _sent ? null : _sendBar(),
      // Green "Call an expert" hub: in the send bar's right corner while
      // filling the form; in the screen's bottom-right corner once sent.
      floatingActionButton: _sent ? const CallExpertButton() : null,
      floatingActionButtonLocation: kCallExpertLocation,
    );
  }

  Widget _formView() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Problem after a service?',
              style: TextStyle(color: AppColors.txt, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text("Show us what's wrong. We'll send you a fixed price to fix it.",
              style: TextStyle(color: AppColors.mut, fontSize: 14.5, height: 1.4)),
          const SizedBox(height: 18),
          _howItWorks(),
          if (_requests.isNotEmpty) ...[
            const SizedBox(height: 26),
            _sectionTitle('Your requests'),
            const SizedBox(height: 12),
            ..._requests.map((r) => ResolveRequestCard(
                  key: ValueKey('${r['id']}-${r['quoted_at']}-${r['status']}'),
                  request: r,
                  onChanged: _loadRequests,
                )),
            const SizedBox(height: 10),
            _sectionTitle('New request'),
          ],
          const SizedBox(height: 18),
          _step(
            1,
            'Show us the problem',
            'Add photos or a short video. For noises, a video with sound helps most.',
            _mediaGrid(),
          ),
          _step(
            2,
            "What's wrong?",
            'Tap all that apply, and add a line if you like.',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 8, runSpacing: 8, children: _problems.map(_chip).toList()),
                const SizedBox(height: 14),
                _field(
                  controller: _desc,
                  hint: 'e.g. Water comes in from the driver door when it rains',
                  maxLines: 3,
                ),
              ],
            ),
          ),
          _step(
            3,
            'Got a dealer quote?',
            "Optional. Add it and we'll try to beat it.",
            Row(
              children: [
                Expanded(
                  child: _field(
                    controller: _quoteAmount,
                    hint: 'Amount',
                    prefix: '₹ ',
                    keyboard: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                _quotePhoto == null
                    ? OutlinedButton.icon(
                        onPressed: _pickQuotePhoto,
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        label: const Text('Add photo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gold,
                          side: const BorderSide(color: _gold),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      )
                    : _thumb(_quotePhoto!, size: 54, onRemove: () => setState(() => _quotePhoto = null)),
              ],
            ),
          ),
          if (widget.vehicleLabel != null && widget.vehicleLabel!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.directions_car_rounded, size: 16, color: AppColors.mut),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('For: ${widget.vehicleLabel}',
                        style: TextStyle(color: AppColors.mut, fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _howItWorks() {
    Widget item(IconData icon, String label) => Expanded(
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _gold, size: 22),
              ),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.txt, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    Widget arrow() => Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.mut),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          item(Icons.photo_camera_rounded, 'Show us'),
          arrow(),
          item(Icons.edit_note_rounded, 'Tell us'),
          arrow(),
          item(Icons.currency_rupee_rounded, 'Get a price'),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) =>
      Text(t, style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w900));

  Widget _step(int n, String title, String sub, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                child: Text('$n',
                    style: TextStyle(color: AppColors.onAccentDark, fontWeight: FontWeight.w900, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: TextStyle(color: AppColors.txt, fontSize: 16.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(sub, style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.35)),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _mediaGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < _media.length; i++)
          _thumb(_media[i], onRemove: () => setState(() => _media.removeAt(i))),
        if (_media.length < _maxItems)
          InkWell(
            onTap: _addMedia,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gold.withOpacity(0.6), width: 1.4),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, color: _gold, size: 26),
                  SizedBox(height: 4),
                  Text('Add', style: TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 12.5)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _thumb(_Picked p, {double size = 84, required VoidCallback onRemove}) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: p.isVideo
                  ? Container(
                      color: const Color(0xFF1B1B1F),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30),
                          SizedBox(height: 2),
                          Text('Video', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    )
                  : Image.memory(p.bytes, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: _sending ? null : onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    final on = _chips.contains(label);
    return GestureDetector(
      onTap: () => setState(() => on ? _chips.remove(label) : _chips.add(label)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? _gold : AppColors.chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? _gold : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? AppColors.onAccentDark : AppColors.txt,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    String? prefix,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: 1,
      keyboardType: keyboard ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      style: TextStyle(color: AppColors.txt, fontSize: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.mut, fontSize: 13.5),
        prefixText: prefix,
        prefixStyle: TextStyle(color: AppColors.txt, fontSize: 14.5, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: AppColors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.line)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _gold, width: 1.4)),
      ),
    );
  }

  Widget _sendBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
            Expanded(
              child: SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _canSend ? _send : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: AppColors.onAccentDark,
                  disabledBackgroundColor: _gold.withOpacity(0.35),
                  disabledForegroundColor: AppColors.onAccentDark.withOpacity(0.6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _sending
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF12100B)),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(_progress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                        ],
                      )
                    : const Text('Send & get my price',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
            ),
                const SizedBox(width: 12),
                const CallExpertButton(showLabel: false),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _canSend ? 'Free — no payment now' : 'Add a photo, video or a few words to continue',
              style: TextStyle(color: AppColors.mut, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sentView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: _green.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: _green, size: 48),
          ),
        ),
        const SizedBox(height: 22),
        Text('Request sent!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.txt, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text(
          "Our team will look at it and send you a fixed price soon. "
          "You'll get a notification, and you can accept the price right here.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mut, fontSize: 14.5, height: 1.45),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: AppColors.onAccentDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => _sent = false),
          child: const Text('See my requests', style: TextStyle(color: _gold, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  Widget _sheetTile(BuildContext ctx, IconData icon, String title, String value, {String? subtitle}) {
    return ListTile(
      leading: Icon(icon, color: _gold),
      title: Text(title, style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700)),
      subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: AppColors.mut, fontSize: 12)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }
}
