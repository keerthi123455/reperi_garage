import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/booking_api.dart';
import '../theme/fleet_theme.dart';
import '../utils/secure_storage_path.dart';
import '../widgets/error_display.dart';

/// Yellow Board → Request Quotation.
///
/// Required: one photo and a description. Brand and model are optional.
/// Submits a `fleet_quotation_requests` row — CRM then sets a price,
/// fleet accepts, CRM assigns a garage, which creates the fleet pickup.
class FleetQuotationSheet extends StatefulWidget {
  final Map<String, dynamic> fleetUser;
  const FleetQuotationSheet({super.key, required this.fleetUser});

  @override
  State<FleetQuotationSheet> createState() => _FleetQuotationSheetState();
}

class _FleetQuotationSheetState extends State<FleetQuotationSheet> with FleetThemeListener {
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _descriptionController = TextEditingController();
  Uint8List? _imageBytes;
  bool _loading = false;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 70);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
    } catch (e) {
      if (mounted) ErrorDisplay.showPremiumError(context, error: e, customMessage: 'Could not open the photo. Please try again.');
    }
  }

  Future<void> _submit() async {
    final desc = _descriptionController.text.trim();
    if (_imageBytes == null || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_imageBytes == null ? 'Add a photo of the vehicle' : 'Describe the problem'),
      ));
      return;
    }

    setState(() => _loading = true);
    try {
      // Upload under <fleet_user_id>/… so the storage policy accepts it.
      final fleetId = widget.fleetUser['id'].toString();
      final name = '${DateTime.now().millisecondsSinceEpoch}-${secureStorageToken()}.jpg';
      final path = '$fleetId/$name';
      await Supabase.instance.client.storage.from('fleet-quotations').uploadBinary(
            path, _imageBytes!, fileOptions: const FileOptions(contentType: 'image/jpeg'));

      await BookingApi.fleetQuotationCreate(
        fleetUserId: widget.fleetUser['id'],
        companyName: widget.fleetUser['company_name']?.toString(),
        username: widget.fleetUser['username']?.toString(),
        vehicleBrand: _brandController.text.trim(),
        vehicleModel: _modelController.text.trim(),
        photoPath: path,
        description: desc,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Quotation sent — we'll price it shortly")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: e is BookingApiException ? e.message : 'Could not submit the quotation. Please try again.',
        );
      }
    }
    if (mounted) setState(() => _loading = false);
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
                    child: Row(children: [
                      FleetIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.maybePop(context)),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Request quotation',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: F.txt, fontSize: 21, fontWeight: FontWeight.w900))),
                      const FleetThemeButton(),
                    ]),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "Send a photo and tell us the problem. We'll come back with a price — nothing to pay yet.",
                            style: TextStyle(color: F.mut, fontSize: 16, fontWeight: FontWeight.w600, height: 1.45),
                          ),
                          _label('PHOTO'),
                          _photo(),
                          _label('DESCRIBE THE PROBLEM'),
                          TextField(
                            controller: _descriptionController,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.newline,
                            keyboardType: TextInputType.multiline,
                            minLines: 4, maxLines: 8,
                            maxLength: 2000,
                            cursorColor: F.accent,
                            style: TextStyle(color: F.txt, fontSize: 16.5, fontWeight: FontWeight.w600, height: 1.4),
                            decoration: F.input('e.g. AC not cooling and brake pads making noise…'),
                          ),
                          _label('BRAND (OPTIONAL)'),
                          TextField(
                            controller: _brandController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            cursorColor: F.accent,
                            style: TextStyle(color: F.txt, fontSize: 18, fontWeight: FontWeight.w700),
                            decoration: F.input('e.g. Toyota'),
                          ),
                          _label('MODEL (OPTIONAL)'),
                          TextField(
                            controller: _modelController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            cursorColor: F.accent,
                            style: TextStyle(color: F.txt, fontSize: 18, fontWeight: FontWeight.w700),
                            decoration: F.input('e.g. Innova Crysta'),
                          ),
                          const SizedBox(height: 26),
                          SizedBox(
                            height: 62,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: F.yellow, foregroundColor: F.navy,
                                disabledBackgroundColor: F.yellow.withOpacity(0.6),
                                elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              ),
                              onPressed: _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: F.navy, strokeWidth: 2.6))
                                  : const FittedBox(fit: BoxFit.scaleDown,
                                      child: Text('SEND QUOTATION',
                                        maxLines: 1, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 0.4))),
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
    child: Text(t, style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)));

  Widget _photo() {
    if (_imageBytes != null) {
      return ClipRRect(borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          Image.memory(_imageBytes!, height: 220, width: double.infinity, fit: BoxFit.cover),
          Positioned(right: 10, bottom: 10, child: Row(children: [
            _overlayButton(Icons.photo_camera_rounded, 'Retake', () => _pickImage(ImageSource.camera)),
            const SizedBox(width: 8),
            _overlayButton(Icons.photo_library_rounded, 'Gallery', () => _pickImage(ImageSource.gallery)),
          ])),
        ]));
    }
    Widget choice(IconData icon, String label, ImageSource src) => Expanded(
      child: Material(color: F.card, borderRadius: BorderRadius.circular(14),
        child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => _pickImage(src),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: F.line)),
            child: Column(children: [
              Icon(icon, color: F.accent, size: 34),
              const SizedBox(height: 8),
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1,
                style: TextStyle(color: F.accent, fontSize: 16, fontWeight: FontWeight.w900))),
            ])))));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: F.sunken, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: F.accent.withOpacity(0.6), width: 2)),
      child: Row(children: [
        choice(Icons.photo_camera_rounded, 'Take photo', ImageSource.camera),
        const SizedBox(width: 10),
        choice(Icons.photo_library_rounded, 'From gallery', ImageSource.gallery),
      ]),
    );
  }

  Widget _overlayButton(IconData icon, String label, VoidCallback onTap) => Material(
    color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12),
    child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
        ]))));
}
