import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../utils/secure_storage_path.dart';
import '../widgets/error_display.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';
import '../widgets/catalog_gate.dart';

class ClaimScreen extends StatefulWidget {
  final String vehicleId;
  final String carModel;
  final String carBrand;
  final String carNumber;

  /// This screen represents a single service with no sub-packages to
  /// select between, so there's nothing further to highlight — accepted
  /// only so callers that pass it (see buildPackageScreenFor) compile.
  final String? highlightPackage;

  const ClaimScreen({
    super.key,
    required this.vehicleId,
    required this.carModel,
    required this.carBrand,
    required this.carNumber,
    this.highlightPackage,
  });

  @override
  State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  /// Filled in by PaymentScreen when this screen was opened before the
  /// customer had a vehicle (see PaymentScreen.onVehicleResolved), so the
  /// booking saved below is attached to the right vehicle.
  String? _resolvedVehicleId;
  String get _vehicleId => _resolvedVehicleId ?? widget.vehicleId;

  final _supabase = Supabase.instance.client;
  final _damageDescriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  // File storage
  File? rcCopyFile;
  File? drivingLicenseFile;
  File? aadhaarFile;
  File? panFile;
  File? insuranceCopyFile;
  File? damagePhotoFile;

  // Upload state — drives the full-screen progress overlay shown only
  // after payment succeeds, while the picked files are actually uploaded.
  bool isUploading = false;

  String uploadStatus = '';

  // Explicit consent for sharing sensitive ID documents (Aadhaar, PAN,
  // driving license, RC copy) with the insurer/garage partner — required
  // at the point of collection, not just covered by the privacy policy
  // elsewhere in the app.
  bool _consentGiven = false;

  // The claim service in the Supabase `services` table. Its price is shown
  // here and charged by the server, which also assigns the claims garage
  // and delivery partner (services.admin_pool / delivery_pool).
  static const String _serviceKey = 'claim_assistance';
  static String get _price => CatalogService.byKey(_serviceKey)?.priceText ?? '';

  // Same support number home_screen.dart's _callSupport already calls —
  // reused here for the circular call button below.
  static const String _supportPhone = '9353094672';

  @override
  void initState() {
    super.initState();
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _damageDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _callSupport() async {
    try {
      await launchUrl(Uri.parse('tel:$_supportPhone'));
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not start the call. Please try again.',
        );
      }
    }
  }

  /// Pick PDF file for documents using file_selector
  Future<void> _pickPdfFile(String documentType, void Function(void Function()) setSheetState) async {
    try {
      const XTypeGroup pdfTypeGroup = XTypeGroup(
        label: 'PDFs',
        extensions: <String>['pdf'],
        // iOS's document picker filters by UTType, not file extension —
        // without this, file_selector_ios can fail to resolve a type
        // filter at all and throw. com.adobe.pdf is Apple's own built-in
        // UTI for PDF, so this doesn't need any Info.plist declaration.
        uniformTypeIdentifiers: <String>['com.adobe.pdf'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[pdfTypeGroup],
      );

      if (file != null) {
        final pickedFile = File(file.path);

        setSheetState(() {
          if (documentType == 'rc') {
            rcCopyFile = pickedFile;
          } else if (documentType == 'license') {
            drivingLicenseFile = pickedFile;
          } else if (documentType == 'aadhaar') {
            aadhaarFile = pickedFile;
          } else if (documentType == 'pan') {
            panFile = pickedFile;
          } else if (documentType == 'insurance') {
            insuranceCopyFile = pickedFile;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not select that file. Please try again.',
        );
      }
    }
  }

  /// Clears a wrongly-attached document/photo so the customer can pick the
  /// right one again, without needing to close and reopen the whole sheet.
  void _removeFile(String documentType, void Function(void Function()) setSheetState) {
    setSheetState(() {
      switch (documentType) {
        case 'rc':
          rcCopyFile = null;
          break;
        case 'license':
          drivingLicenseFile = null;
          break;
        case 'aadhaar':
          aadhaarFile = null;
          break;
        case 'pan':
          panFile = null;
          break;
        case 'insurance':
          insuranceCopyFile = null;
          break;
        case 'damage':
          damagePhotoFile = null;
          break;
      }
    });
  }

  Future<ImageSource?> _showDamagePhotoSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF262626),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Add Damage Photo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFFD4A017)),
                title: const Text('Take Photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: Color(0xFFD4A017)),
                title: const Text('Choose from Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  /// Pick image file for damage photo using image_picker
  Future<void> _pickImageFile(void Function(void Function()) setSheetState) async {
    try {
      final source = await _showDamagePhotoSourceSheet();
      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image != null) {
        setSheetState(() => damagePhotoFile = File(image.path));
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not select that photo. Please try again.',
        );
      }
    }
  }

  /// Uploads a file to the (private) 'insurance-documents' bucket and
  /// returns its storage PATH — not a public URL. These are government ID
  /// documents (Aadhaar, PAN, RC, driving license) plus the insurance copy
  /// and damage photo, so a permanent public link would let anyone who
  /// ever got hold of it view them indefinitely. Storing just the path
  /// means access is only ever granted via a short-lived signed URL,
  /// minted on demand right when someone actually opens the document (see
  /// claim_details_screen.dart's _downloadDocument) rather than
  /// baked in forever at upload time.
  Future<String?> _uploadFile(File file, String folderPath, String fileName) async {
    final path = '$folderPath/$fileName';
    final bytes = await file.readAsBytes();

    // Up to 3 tries per file — these uploads happen AFTER the customer has
    // paid, so a single dropped request on a weak connection shouldn't be
    // enough to lose their claim.
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _supabase.storage
            .from('insurance-documents')
            .uploadBinary(path, bytes);
        return path;
      } on StorageException catch (e) {
        // Same claim id on a RETRY means the same path — if an earlier
        // attempt already got this file up, it's already done.
        final msg = e.message.toLowerCase();
        if (e.statusCode == '409' ||
            msg.contains('already exists') ||
            msg.contains('duplicate')) {
          return path;
        }
        lastError = e;
      } catch (e) {
        lastError = e;
      }
      debugPrint('Claim upload failed ($path, attempt $attempt/3): $lastError');
      if (attempt < 3) await Future.delayed(Duration(seconds: attempt * 2));
    }
    throw Exception('Upload failed ($path): $lastError');
  }

  bool get _allDocsReady =>
      rcCopyFile != null &&
      drivingLicenseFile != null &&
      aadhaarFile != null &&
      panFile != null &&
      insuranceCopyFile != null &&
      damagePhotoFile != null &&
      _damageDescriptionController.text.trim().isNotEmpty;

  // ── Pre-payment preparation ──────────────────────────────────────────
  // Everything that can realistically fail (six file uploads, admin and
  // delivery-partner lookups) now happens BEFORE PaymentScreen opens. If
  // any of it fails, the customer sees an error and has paid nothing.
  // After payment, the only work left is one claim_table insert.
  String? _preparedClaimId;
  Map<String, String>? _uploadedPaths;
  String? _uploadedSignature; // which picked files _uploadedPaths belong to

  /// Identifies the exact set of picked files, so already-uploaded files
  /// are reused only if the customer hasn't swapped any of them since.
  String get _pickedFilesSignature => [
        rcCopyFile?.path,
        drivingLicenseFile?.path,
        aadhaarFile?.path,
        panFile?.path,
        insuranceCopyFile?.path,
        damagePhotoFile?.path,
      ].join('|');

  /// Uploads every document. Throws on any failure — the caller then stops
  /// BEFORE payment.
  Future<void> _prepareClaimBeforePayment() async {
    final signature = _pickedFilesSignature;
    final alreadyUploaded = _uploadedPaths != null &&
        _uploadedSignature == signature &&
        _preparedClaimId != null;

    if (!alreadyUploaded) {
      final claimId =
          '${DateTime.now().millisecondsSinceEpoch}-${secureStorageToken()}';

      if (mounted) setState(() => uploadStatus = 'Uploading RC Copy...');
      final rc = await _uploadFile(rcCopyFile!, 'rc-copies', 'claim-$claimId-rc.pdf');

      if (mounted) setState(() => uploadStatus = 'Uploading Driving License...');
      final license = await _uploadFile(
          drivingLicenseFile!, 'driving-licenses', 'claim-$claimId-license.pdf');

      if (mounted) setState(() => uploadStatus = 'Uploading Aadhaar...');
      final aadhaar = await _uploadFile(aadhaarFile!, 'aadhaar', 'claim-$claimId-aadhaar.pdf');

      if (mounted) setState(() => uploadStatus = 'Uploading PAN...');
      final pan = await _uploadFile(panFile!, 'pan', 'claim-$claimId-pan.pdf');

      if (mounted) setState(() => uploadStatus = 'Uploading Insurance Copy...');
      final insurance = await _uploadFile(
          insuranceCopyFile!, 'insurance-copies', 'claim-$claimId-insurance.pdf');

      if (mounted) setState(() => uploadStatus = 'Uploading Damage Photo...');
      final photo = await _uploadFile(
          damagePhotoFile!, 'damage-photos', 'claim-$claimId-damage.jpg');

      _preparedClaimId = claimId;
      _uploadedPaths = {
        'rc': rc!,
        'license': license!,
        'aadhaar': aadhaar!,
        'pan': pan!,
        'insurance': insurance!,
        'photo': photo!,
      };
      _uploadedSignature = signature;
    }
  }

  /// Validates the form, uploads everything, and only then opens
  /// PaymentScreen. Payment is never offered unless the documents are
  /// safely stored.
  Future<void> _confirmAndPay() async {
    // The description field is very likely still focused (this is the
    // SUBMIT CLAIM button right below it) — unfocus explicitly so the
    // keyboard doesn't get stuck on screen through the navigation.
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_allDocsReady) {
      // showPremiumToast renders above the open bottom sheet (a plain
      // SnackBar would render behind it).
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Please upload all documents and add a description',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFE5484D),
      );
      return;
    }

    if (!_consentGiven) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Please confirm you consent to sharing these documents to submit your claim',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFE5484D),
      );
      return;
    }

    if (_supabase.auth.currentUser == null) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Please sign in again to submit your claim',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFE5484D),
      );
      return;
    }

    Navigator.pop(context); // close the upload sheet

    setState(() {
      isUploading = true;
      uploadStatus = 'Uploading documents...';
    });

    try {
      await _prepareClaimBeforePayment();
    } catch (e) {
      debugPrint('Claim preparation failed (no payment taken): $e');
      if (!mounted) return;
      setState(() {
        isUploading = false;
        uploadStatus = '';
      });
      // Picked files stay selected, so SUBMIT CLAIM can simply be tapped
      // again once the connection is back.
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage:
            'We couldn\'t upload your documents, so no payment was taken. '
            'Please check your connection and tap SUBMIT CLAIM again.',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      isUploading = false;
      uploadStatus = '';
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: CatalogService.byKey(_serviceKey)?.name ?? 'Claim Assistance Service',
          duration: CatalogService.byKey(_serviceKey)?.duration ?? 'Doorstep pickup & drop',
          vehicleId: _vehicleId,
          onVehicleResolved: (id) => _resolvedVehicleId = id,
          // Online only, with doorstep pickup & drop — both set on the
          // service row. The server saves the claim with these documents
          // after the payment is verified.
          serviceKeys: const [_serviceKey],
          bookingOptions: {
            'claim': {
              'description': _damageDescriptionController.text.trim(),
              'rc': _uploadedPaths!['rc'],
              'license': _uploadedPaths!['license'],
              'aadhaar': _uploadedPaths!['aadhaar'],
              'pan': _uploadedPaths!['pan'],
              'insurance': _uploadedPaths!['insurance'],
              'photo': _uploadedPaths!['photo'],
            },
          },
          bookingSection: 'claim',
        ),
      ),
    );
  }


  /// One-time privacy notice shown before the upload sheet opens — the
  /// "pop up" explaining what the documents are used for, rather than
  /// burying that only in the small consent-checkbox text.
  Future<void> _showPrivacyNoticeThenOpenUploadSheet() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(Icons.privacy_tip_rounded, color: const Color(0xFFD4A017), size: 32),
        title: Text(
          'Your documents, protected',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w900, fontSize: 16),
        ),
        content: Text(
          'Everything you upload here — your RC copy, driving license, Aadhaar, '
          'PAN, insurance copy, and damage photo — is used only to get your '
          'claim submitted and processed. Nothing is shared or used '
          'for any other purpose.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A017),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'GOT IT',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );

    if (mounted) _showUploadSheet();
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => _UploadSheetContent(
          state: this,
          setSheetState: setSheetState,
        ),
      ),
    );
  }

  /// Build document upload tile. [onRemove], when a file is already
  /// selected, adds a small delete button so the wrong attachment can be
  /// cleared without re-picking over it or closing the whole sheet.
  Widget _buildDocumentTile(
    String title,
    File? selectedFile,
    VoidCallback onTap,
    IconData icon, {
    VoidCallback? onRemove,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selectedFile != null
                ? const Color(0xFFD4A017)
                : AppColors.line,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFD4A017), size: 24),
            const SizedBox(width: 12),
            // Expanded absorbs whatever width is left after the fixed-size
            // icons on the trailing side — adding the extra delete button
            // below doesn't risk an overflow, this column just gets a
            // little narrower and the filename still ellipsizes.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedFile != null
                        ? selectedFile.path.split('/').last
                        : 'Upload PDF',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selectedFile != null
                          ? const Color(0xFFD4A017)
                          : AppColors.mut,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD4A017).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                selectedFile != null ? Icons.check_circle : Icons.cloud_upload,
                color: selectedFile != null
                    ? const Color(0xFFD4A017)
                    : AppColors.mut,
                size: 20,
              ),
            ),
            if (selectedFile != null && onRemove != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CatalogGate(builder: (context) {
    if (CatalogService.byKey(_serviceKey) == null) {
      return const CatalogEmpty(message: 'Claim assistance isn\'t available right now. Please call us for help.');
    }

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceRaised,
        elevation: 0,
        title: Text(
          'File a Claim',
          style: TextStyle(
            color: AppColors.txt,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.txt),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _callSupport,
        backgroundColor: const Color(0xFFD4A017),
        shape: const CircleBorder(),
        child: const Icon(Icons.call_rounded, color: Colors.black, size: 26),
      ),
      body: isUploading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: Color(0xFFD4A017),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    uploadStatus,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HowItWorksCard(price: _price),
                  const SizedBox(height: 20),

                  // Vehicle Info Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFD4A017).withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vehicle details',
                          style: TextStyle(
                            color: Color(0xFFD4A017),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.carBrand} ${widget.carModel}',
                          style: TextStyle(
                            color: AppColors.txt,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.carNumber.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton.icon(
                      onPressed: _showPrivacyNoticeThenOpenUploadSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A017),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.upload_file_rounded, color: Colors.black),
                      label: const Text(
                        'UPLOAD DOCUMENTS & FILE CLAIM',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      'Need help? Tap the call button below to talk to us.',
                      style: TextStyle(color: AppColors.mut, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
    );
    });
  }
}

/// The "how this works" explainer shown at the top of the screen — what
/// the customer described wanting before anything else: pickup, pay,
/// garage handles the rest, updates along the way.
class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.price});
  final String price;

  static const _steps = [
    (
      Icons.local_shipping_rounded,
      'We come to you',
      'Our delivery partner picks up your vehicle from your doorstep.',
    ),
    (
      Icons.payments_rounded,
      'You just pay the service fee',
      'A flat, one-time fee — the rest is on us.',
    ),
    (
      Icons.build_circle_rounded,
      'Our garage takes it from there',
      'Our partner garage handles the inspection, paperwork, and repair.',
    ),
    (
      Icons.notifications_active_rounded,
      'Stay in the loop',
      'You\'ll get real-time updates and notifications at every step.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'How it works',
                style: TextStyle(color: AppColors.txt, fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A017),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  price,
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == _steps.length - 1 ? 0 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_steps[i].$1, color: AppColors.txt, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _steps[i].$2,
                          style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _steps[i].$3,
                          style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The doc-upload/photo/description sheet opened from UPLOAD DOCUMENTS &
/// FILE CLAIM. A StatefulWidget (not a plain function-returning one)
/// purely so its own [dispose] can force the keyboard down — see the note
/// there for why that's the one reliable place to do it. The actual file
/// state still lives on _ClaimScreenState; [setSheetState] is what makes
/// picking a file inside this sheet actually repaint it (a modal bottom
/// sheet's route isn't a descendant of the screen's Element tree, so the
/// screen's own setState alone wouldn't rebuild this content).
class _UploadSheetContent extends StatefulWidget {
  const _UploadSheetContent({required this.state, required this.setSheetState});

  final _ClaimScreenState state;
  final void Function(void Function()) setSheetState;

  @override
  State<_UploadSheetContent> createState() => _UploadSheetContentState();
}

class _UploadSheetContentState extends State<_UploadSheetContent> {
  /// Opens the damage-description dialog seeded with whatever's already
  /// saved — typing and tapping X discards the draft and leaves the saved
  /// description untouched; OK (once the field isn't empty) commits the
  /// draft into the claim screen's own
  /// [_ClaimScreenState._damageDescriptionController].
  ///
  /// The dialog itself is [_DamageDescriptionDialog], a dedicated
  /// StatefulWidget rather than an inline StatefulBuilder — see its own
  /// dispose() for why the keyboard-dismiss has to live there instead of
  /// right before each button's Navigator.pop.
  Future<void> _openDamageDescriptionDialog() async {
    final state = widget.state;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _DamageDescriptionDialog(
        initialText: state._damageDescriptionController.text,
      ),
    );
    if (result != null) {
      state._damageDescriptionController.text = result;
    }
    if (!mounted) return;
    widget.setSheetState(() {});
  }

  @override
  void dispose() {
    // Whatever closed this sheet — the X button, SUBMIT CLAIM's own pop,
    // swiping it down, tapping the barrier outside it, or the Android back
    // button — this widget gets disposed either way, so this is the one
    // place guaranteed to run regardless of which path was taken. Trying
    // to catch every individual close gesture one at a time (as tried
    // before) kept missing cases; this can't miss any of them.
    FocusManager.instance.primaryFocus?.unfocus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final setSheetState = widget.setSheetState;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9 - bottomInset),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Text(
                    'Documents & Claim Details',
                    style: TextStyle(color: AppColors.txt, fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.close_rounded, color: AppColors.txt, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              // Tapping anywhere in the body that isn't a text field,
              // button, or document tile (its own tap targets still win —
              // see the note on nested GestureDetectors in
              // _buildDocumentTile) dismisses the keyboard, same as
              // services_screen.dart's search bar.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Required documents',
                      style: TextStyle(color: AppColors.txt, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    state._buildDocumentTile(
                      '📄 RC Copy',
                      state.rcCopyFile,
                      () => state._pickPdfFile('rc', setSheetState),
                      Icons.description,
                      onRemove: () => state._removeFile('rc', setSheetState),
                    ),
                    state._buildDocumentTile(
                      '📄 Driving License',
                      state.drivingLicenseFile,
                      () => state._pickPdfFile('license', setSheetState),
                      Icons.credit_card,
                      onRemove: () => state._removeFile('license', setSheetState),
                    ),
                    state._buildDocumentTile(
                      '📄 Owner Aadhaar',
                      state.aadhaarFile,
                      () => state._pickPdfFile('aadhaar', setSheetState),
                      Icons.badge,
                      onRemove: () => state._removeFile('aadhaar', setSheetState),
                    ),
                    state._buildDocumentTile(
                      '📄 Owner PAN',
                      state.panFile,
                      () => state._pickPdfFile('pan', setSheetState),
                      Icons.assignment,
                      onRemove: () => state._removeFile('pan', setSheetState),
                    ),
                    state._buildDocumentTile(
                      '📄 Insurance Copy',
                      state.insuranceCopyFile,
                      () => state._pickPdfFile('insurance', setSheetState),
                      Icons.security,
                      onRemove: () => state._removeFile('insurance', setSheetState),
                    ),

                    const SizedBox(height: 16),
                    Text(
                      'Damage photo',
                      style: TextStyle(color: AppColors.txt, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => state._pickImageFile(setSheetState),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSunken,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: state.damagePhotoFile != null ? const Color(0xFFD4A017) : AppColors.line,
                            width: 1.5,
                          ),
                        ),
                        child: state.damagePhotoFile != null
                            ? Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      state.damagePhotoFile!,
                                      height: 160,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Row + Expanded so a long filename
                                  // ellipsizes instead of pushing the
                                  // delete button off-screen or overflowing.
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          state.damagePhotoFile!.path.split('/').last,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Color(0xFFD4A017), fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => state._removeFile('damage', setSheetState),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Icon(Icons.add_a_photo_rounded, color: AppColors.mut, size: 34),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Tap to upload damage photo',
                                    style: TextStyle(color: AppColors.mut, fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Describe the damage',
                          style: TextStyle(color: AppColors.txt, fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        TextButton.icon(
                          onPressed: _openDamageDescriptionDialog,
                          icon: Icon(
                            state._damageDescriptionController.text.trim().isEmpty
                                ? Icons.add_circle_outline
                                : Icons.edit_outlined,
                            size: 18,
                            color: const Color(0xFFD4A017),
                          ),
                          label: Text(
                            state._damageDescriptionController.text.trim().isEmpty
                                ? 'Add Description'
                                : 'Edit',
                            style: const TextStyle(
                              color: Color(0xFFD4A017),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (state._damageDescriptionController.text.trim().isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSunken,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Text(
                          state._damageDescriptionController.text.trim(),
                          style: TextStyle(color: AppColors.txt.withOpacity(0.85), fontSize: 13.5, height: 1.4),
                        ),
                      ),

                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () => setSheetState(() => state._consentGiven = !state._consentGiven),
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: state._consentGiven,
                            onChanged: (v) => setSheetState(() => state._consentGiven = v ?? false),
                            activeColor: const Color(0xFFD4A017),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'I consent to sharing these documents with the insurer and garage '
                                'partner solely to process this claim.',
                                style: TextStyle(color: AppColors.mut, fontSize: 12, height: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: state._confirmAndPay,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4A017),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text(
                          'SUBMIT CLAIM',
                          style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// The "Describe the damage" popup — its own StatefulWidget rather than an
/// inline StatefulBuilder, specifically so it gets a dispose() lifecycle
/// hook. Calling FocusManager.instance.primaryFocus?.unfocus() right
/// before each button's Navigator.pop (X or OK) races the pop's own
/// teardown of this route and crashed with a
/// "'_dependents.isEmpty': is not true" assertion on every close,
/// regardless of button or field content. dispose() always runs exactly
/// once, strictly after the route has actually been removed, so there's
/// no teardown left to race — same reasoning _UploadSheetContentState's
/// own dispose() above already uses for the outer sheet.
///
/// X always pops with no result (discarding the draft, whatever it says).
/// OK pops with the draft text only once it's non-empty; otherwise it
/// shows an inline error instead of closing.
class _DamageDescriptionDialog extends StatefulWidget {
  const _DamageDescriptionDialog({required this.initialText});

  final String initialText;

  @override
  State<_DamageDescriptionDialog> createState() => _DamageDescriptionDialogState();
}

class _DamageDescriptionDialogState extends State<_DamageDescriptionDialog> {
  late final _draftController = TextEditingController(text: widget.initialText);
  String? _fieldError;

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _draftController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_draftController.text.trim().isEmpty) {
      setState(() => _fieldError = 'Please enter description of the incident');
      return;
    }
    Navigator.pop(context, _draftController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Describe the damage',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700),
            ),
          ),
          // X always exits — no validation, whatever's typed (or not
          // typed) is discarded either way.
          IconButton(
            icon: Icon(Icons.close, color: AppColors.mut),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: TextField(
        controller: _draftController,
        autofocus: true,
        maxLines: 4,
        maxLength: 500,
        style: TextStyle(color: AppColors.txt),
        decoration: InputDecoration(
          hintText: 'Describe the damage, accident details, location, etc.',
          hintStyle: TextStyle(color: AppColors.mut, fontSize: 13.5),
          errorText: _fieldError,
          filled: true,
          fillColor: AppColors.surfaceSunken,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD4A017)),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A017),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'OK',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}
