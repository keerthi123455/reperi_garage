import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/booking_api.dart';
import '../theme/fleet_theme.dart';
import '../utils/secure_storage_path.dart';
import '../widgets/error_display.dart';

class FleetOrderSheet extends StatefulWidget {
  final Map<String, dynamic> fleetUser;

  const FleetOrderSheet({
    super.key,
    required this.fleetUser,
  });

  @override
  State<FleetOrderSheet> createState() => _FleetOrderSheetState();
}

class _FleetOrderSheetState extends State<FleetOrderSheet> with FleetThemeListener {
  final _vehicleModelController = TextEditingController();

  final _carNumberController = TextEditingController();

  // ── Web-safe image state ──
  // dart:io File does NOT work on Flutter Web.
  // We store raw bytes instead, which works on every platform.
  Uint8List? _imageBytes;

  bool _loading = false;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _vehicleModelController.dispose();
    _carNumberController.dispose();
    super.dispose();
  }

  // Note: on web, ImageSource.camera opens the browser's webcam capture UI if
  // a camera is available and permission is granted; gallery always works.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 70);
      if (picked == null) return;
      // readAsBytes() works identically on web, mobile, and desktop.
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(context, error: e, customMessage: 'Could not open the photo. Please try again.');
      }
    }
  }

  Future<void> _submit() async {

    if (_vehicleModelController.text.trim().isEmpty ||
        _carNumberController.text.trim().isEmpty ||
        _imageBytes == null) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _carNumberController.text.trim().isEmpty
                ? 'Enter the vehicle number'
                : _vehicleModelController.text.trim().isEmpty
                    ? 'Enter the vehicle model'
                    : 'Add a photo of the vehicle',
          ),
        ),
      );

      return;
    }

    setState(() {
      _loading = true;
    });

    try {

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}-${secureStorageToken()}.jpg';

      // uploadBinary works with raw bytes on every platform,
      // unlike upload() which expects a dart:io File (web-incompatible).
      await Supabase.instance.client.storage
          .from('booking-images')
          .uploadBinary(
            'fleet/$fileName',
            _imageBytes!,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
            ),
          );

      // Store the storage PATH, not a permanent public URL — the
      // booking-images bucket is private, so the display side mints a
      // short-lived signed URL on demand (see fleet_request_details_screen
      // .dart and fleet_request_view_screen.dart).
      final imageUrl = 'fleet/$fileName';

      // Through the booking server: it picks the garage and the delivery
      // partner (CRM → Assignment rules) and creates the request.
      await BookingApi.fleetPickupCreate(
        fleetUserId: widget.fleetUser['id'],
        companyName: widget.fleetUser['company_name']?.toString(),
        username: widget.fleetUser['username']?.toString(),
        vehicleModel: _vehicleModelController.text.trim(),
        carNumber: _carNumberController.text.trim().toUpperCase(),
        vehiclePhotoPath: imageUrl,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Service requested — we\'ll update you here'),
        ),
      );

      Navigator.pop(context);

    } catch (e) {

      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: e is BookingApiException ? e.message : 'Could not submit your service request. Please try again.',
        );
      }

    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    child: Row(
                      children: [
                        FleetIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Request service',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: F.txt, fontSize: 21, fontWeight: FontWeight.w900),
                          ),
                        ),
                        const FleetThemeButton(),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "We'll collect the vehicle, inspect it and send you photos and a price before any work.",
                            style: TextStyle(color: F.mut, fontSize: 16, fontWeight: FontWeight.w600, height: 1.45),
                          ),
                          _label('VEHICLE NUMBER'),
                          _plateField(),
                          _label('VEHICLE MODEL'),
                          TextField(
                            controller: _vehicleModelController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            cursorColor: F.accent,
                            style: TextStyle(color: F.txt, fontSize: 18, fontWeight: FontWeight.w700),
                            decoration: F.input('e.g. Tata Ace Gold'),
                          ),
                          _label('VEHICLE PHOTO'),
                          _photo(),
                          const SizedBox(height: 8),
                          Text(
                            'A clear photo of the front helps us find the vehicle.',
                            style: TextStyle(color: F.mut, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.4),
                          ),
                          const SizedBox(height: 26),
                          SizedBox(
                            height: 62,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: F.yellow,
                                foregroundColor: F.navy,
                                disabledBackgroundColor: F.yellow.withOpacity(0.6),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              ),
                              onPressed: _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(color: F.navy, strokeWidth: 2.6),
                                    )
                                  : const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('REQUEST SERVICE',
                                          maxLines: 1,
                                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                                    ),
                            ),
                          ),
                        ],
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

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      );

  /// Number typed straight onto an Indian-style plate.
  Widget _plateField() {
    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF111111), width: 2.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 26,
            color: const Color(0xFF1A4FB5),
            alignment: Alignment.center,
            child: const RotatedBox(
              quarterTurns: 3,
              child: Text('IND', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ),
          Expanded(
            child: Center(
              child: TextField(
                controller: _carNumberController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
                  LengthLimitingTextInputFormatter(14),
                  TextInputFormatter.withFunction(
                    (oldV, newV) => newV.copyWith(text: newV.text.toUpperCase()),
                  ),
                ],
                textInputAction: TextInputAction.next,
                cursorColor: const Color(0xFF111111),
                style: const TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
                decoration: const InputDecoration(
                  hintText: 'KA 01 AB 1234',
                  hintStyle: TextStyle(color: Color(0xFFB8B8B8), fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo() {
    if (_imageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Image.memory(_imageBytes!, height: 220, width: double.infinity, fit: BoxFit.cover),
            Positioned(
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  _overlayButton(Icons.photo_camera_rounded, 'Retake', () => _pickImage(ImageSource.camera)),
                  const SizedBox(width: 8),
                  _overlayButton(Icons.photo_library_rounded, 'Gallery', () => _pickImage(ImageSource.gallery)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    Widget choice(IconData icon, String label, ImageSource src) => Expanded(
          child: Material(
            color: F.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _pickImage(src),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: F.line),
                ),
                child: Column(
                  children: [
                    Icon(icon, color: F.accent, size: 34),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label,
                          maxLines: 1, style: TextStyle(color: F.accent, fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: F.sunken,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: F.accent.withOpacity(0.6), width: 2),
      ),
      child: Row(
        children: [
          choice(Icons.photo_camera_rounded, 'Take photo', ImageSource.camera),
          const SizedBox(width: 10),
          choice(Icons.photo_library_rounded, 'From gallery', ImageSource.gallery),
        ],
      ),
    );
  }

  Widget _overlayButton(IconData icon, String label, VoidCallback onTap) => Material(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      );
}
