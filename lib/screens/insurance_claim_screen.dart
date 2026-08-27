import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

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
  void dispose() {
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
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selectedFile != null
              ? const Color(0xFFD4A017)
              : Colors.grey.withOpacity(0.3),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
                        : Colors.grey,
                    fontSize: 11,
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
                  : Colors.grey,
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
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        title: const Text(
          'File Insurance Claim',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isUploading ? null : _submitClaim,
        backgroundColor: isUploading 
            ? const Color(0xFFD4A017).withOpacity(0.5)
            : const Color(0xFFD4A017),
        label: Text(
          isUploading ? 'UPLOADING...' : 'SUBMIT CLAIM',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        icon: Icon(
          isUploading ? Icons.cloud_upload : Icons.check_circle,
          color: Colors.black,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vehicle Info Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFD4A017).withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vehicle Details',
                          style: TextStyle(
                            color: Color(0xFFD4A017),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.carBrand} ${widget.carModel}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
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
                              fontSize: 11,
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
                  const Text(
                    'Required Documents',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
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
                  const Text(
                    'Damage Photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const SizedBox(height: 12),

                  GestureDetector(
                    onTap: _pickImageFile,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: damagePhotoFile != null
                              ? const Color(0xFFD4A017)
                              : Colors.grey.withOpacity(0.3),
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
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Tap to upload damage photo',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  // Damage Description
                  const Text(
                    'Describe the Damage',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _damageDescriptionController,
                    maxLines: 5,
                    maxLength: 500,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Describe the damage, accident details, location, etc.',
                      hintStyle: TextStyle(
                        color: Colors.grey.withOpacity(0.6),
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.grey.withOpacity(0.3),
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
    );
  }
}