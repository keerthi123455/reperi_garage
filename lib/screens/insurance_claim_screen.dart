import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

class InsuranceClaimScreen extends StatefulWidget {
  final String vehicleId;
  final String carModel;
  final String carBrand;
  final String carNumber;

  const InsuranceClaimScreen({
    super.key,
    required this.vehicleId,
    required this.carModel,
    required this.carBrand,
    required this.carNumber,
  });

  @override
  State<InsuranceClaimScreen> createState() => _InsuranceClaimScreenState();
}

class _InsuranceClaimScreenState extends State<InsuranceClaimScreen> {
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

  // Upload state
  bool isUploading = false;
  String uploadStatus = '';

  // Constant for insurance admin
  static const String INSURANCE_ADMIN_USERNAME = 'newexpert_care';

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

  /// Pick PDF file for documents using file_selector
  Future<void> _pickPdfFile(String documentType) async {
    try {
      const XTypeGroup pdfTypeGroup = XTypeGroup(
        label: 'PDFs',
        extensions: <String>['pdf'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[pdfTypeGroup],
      );

      if (file != null) {
        final pickedFile = File(file.path);
        
        setState(() {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  /// Pick image file for damage photo using image_picker
  Future<void> _pickImageFile() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          damagePhotoFile = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  /// Upload file to Supabase storage and return public URL
  Future<String?> _uploadFile(File file, String folderPath, String fileName) async {
    try {
      final bytes = await file.readAsBytes();
      final path = '$folderPath/$fileName';

      await _supabase.storage
          .from('insurance-documents')
          .uploadBinary(path, bytes);

      final publicUrl = _supabase.storage
          .from('insurance-documents')
          .getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      throw Exception('Upload failed: $e');
    }
  }

  /// Submit insurance claim
  Future<void> _submitClaim() async {
    // Validation
    if (rcCopyFile == null ||
        drivingLicenseFile == null ||
        aadhaarFile == null ||
        panFile == null ||
        insuranceCopyFile == null ||
        damagePhotoFile == null ||
        _damageDescriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload all documents and add description'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isUploading = true;
      uploadStatus = 'Uploading documents...';
    });

    try {
      // Get current user
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final claimId = DateTime.now().millisecondsSinceEpoch.toString();

      // Upload all files
      setState(() => uploadStatus = 'Uploading RC Copy...');
      final rcUrl = await _uploadFile(
          rcCopyFile!, 'rc-copies', 'claim-$claimId-rc.pdf');

      setState(() => uploadStatus = 'Uploading Driving License...');
      final licenseUrl = await _uploadFile(
          drivingLicenseFile!, 'driving-licenses', 'claim-$claimId-license.pdf');

      setState(() => uploadStatus = 'Uploading Aadhaar...');
      final aadhaarUrl = await _uploadFile(
          aadhaarFile!, 'aadhaar', 'claim-$claimId-aadhaar.pdf');

      setState(() => uploadStatus = 'Uploading PAN...');
      final panUrl = await _uploadFile(
          panFile!, 'pan', 'claim-$claimId-pan.pdf');

      setState(() => uploadStatus = 'Uploading Insurance Copy...');
      final insuranceUrl = await _uploadFile(
          insuranceCopyFile!, 'insurance-copies', 'claim-$claimId-insurance.pdf');

      setState(() => uploadStatus = 'Uploading Damage Photo...');
      final photoUrl = await _uploadFile(
          damagePhotoFile!, 'damage-photos', 'claim-$claimId-damage.jpg');

      // Save claim to database
      setState(() => uploadStatus = 'Saving claim details...');
      await _supabase.from('insurance_claims').insert({
        'user_id': user.id,
        'vehicle_id': widget.vehicleId,
        'assigned_to_admin_id': INSURANCE_ADMIN_USERNAME,
        'claim_status': 'submitted',
        'damage_description': _damageDescriptionController.text.trim(),
        'rc_copy_url': rcUrl,
        'driving_license_url': licenseUrl,
        'owner_aadhaar_url': aadhaarUrl,
        'owner_pan_url': panUrl,
        'insurance_copy_url': insuranceUrl,
        'damage_photo_url': photoUrl,
        'has_unread_update': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Insurance claim submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting claim: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isUploading = false;
          uploadStatus = '';
        });
      }
    }
  }

  /// Build document upload tile
  Widget _buildDocumentTile(
    String title,
    File? selectedFile,
    String documentType,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceRaised,
        elevation: 0,
        title: Text(
          'File Insurance Claim',
          style: TextStyle(
            color: AppColors.txt,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.txt),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          isUploading
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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

                  const SizedBox(height: 24),

                  // Documents Section
                  Text(
                    'Required documents',
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // RC Copy
                  GestureDetector(
                    onTap: () => _pickPdfFile('rc'),
                    child: _buildDocumentTile(
                      '📄 RC Copy',
                      rcCopyFile,
                      'rc',
                      Icons.description,
                    ),
                  ),

                  // Driving License
                  GestureDetector(
                    onTap: () => _pickPdfFile('license'),
                    child: _buildDocumentTile(
                      '📄 Driving License',
                      drivingLicenseFile,
                      'license',
                      Icons.credit_card,
                    ),
                  ),

                  // Owner Aadhaar
                  GestureDetector(
                    onTap: () => _pickPdfFile('aadhaar'),
                    child: _buildDocumentTile(
                      '📄 Owner Aadhaar',
                      aadhaarFile,
                      'aadhaar',
                      Icons.badge,
                    ),
                  ),

                  // Owner PAN
                  GestureDetector(
                    onTap: () => _pickPdfFile('pan'),
                    child: _buildDocumentTile(
                      '📄 Owner PAN',
                      panFile,
                      'pan',
                      Icons.assignment,
                    ),
                  ),

                  // Insurance Copy
                  GestureDetector(
                    onTap: () => _pickPdfFile('insurance'),
                    child: _buildDocumentTile(
                      '📄 Insurance Copy',
                      insuranceCopyFile,
                      'insurance',
                      Icons.security,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Damage Photo
                  Text(
                    'Damage photo',
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 12),

                  GestureDetector(
                    onTap: _pickImageFile,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: damagePhotoFile != null
                              ? const Color(0xFFD4A017)
                              : AppColors.line,
                          width: 1.5,
                        ),
                      ),
                      child: damagePhotoFile != null
                          ? Column(
                              children: [
                                Image.file(
                                  damagePhotoFile!,
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  damagePhotoFile!.path.split('/').last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFD4A017),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Icon(
                                  Icons.image_not_supported,
                                  color: AppColors.mut,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Tap to upload damage photo',
                                  style: TextStyle(
                                    color: AppColors.mut,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  // Damage Description
                  Text(
                    'Describe the damage',
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _damageDescriptionController,
                    maxLines: 5,
                    maxLength: 500,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Describe the damage, accident details, location, etc.',
                      hintStyle: TextStyle(
                        color: AppColors.mut,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceRaised,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.line,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.line,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFFD4A017),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyBar(),
          ),
        ],
      ),
    );
  }

  // ── STICKY BOTTOM BAR ────────────────────────────────────────────
  Widget _buildStickyBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border(top: BorderSide(color: AppColors.line)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: GestureDetector(
          onTap: isUploading ? null : _submitClaim,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: isUploading
                  ? const Color(0xFFD4A017).withOpacity(0.5)
                  : const Color(0xFFD4A017),
              borderRadius: BorderRadius.circular(16),
              boxShadow: isUploading
                  ? []
                  : [
                      BoxShadow(
                        color: const Color(0xFFD4A017).withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isUploading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.onAccentDark,
                    ),
                  )
                else
                  Icon(Icons.check_circle, color: AppColors.onAccentDark, size: 20),
                const SizedBox(width: 10),
                Text(
                  isUploading ? 'Uploading...' : 'Submit Claim',
                  style: TextStyle(
                    color: AppColors.onAccentDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}