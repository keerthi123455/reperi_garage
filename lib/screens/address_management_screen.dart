import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:reperi_garage/services/address_service.dart';

class AddressManagementScreen extends StatefulWidget {
  const AddressManagementScreen({super.key});

  @override
  State<AddressManagementScreen> createState() =>
      _AddressManagementScreenState();
}

class _AddressManagementScreenState extends State<AddressManagementScreen> {
  late AddressService _addressService;
  List<Map<String, dynamic>> addresses = [];
  bool loading = true;
  String? selectedAddressId;

  @override
  void initState() {
    super.initState();
    _addressService = AddressService();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    setState(() => loading = true);
    try {
      final addrs = await _addressService.getUserAddresses();
      final defaultAddr = await _addressService.getDefaultAddress();

      if (mounted) {
        setState(() {
          addresses = addrs;
          selectedAddressId = defaultAddr?['id'];
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading addresses: $e')),
        );
      }
    }
  }

  void _showAddAddressSheet() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    bool isDetectingLocation = false;
    double? detectedLat;
    double? detectedLng;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 28,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Add Address',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Address Name
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Address name (e.g., Home, Office)',
                        hintStyle: TextStyle(color: Colors.grey.shade600),
                        prefixIcon:
                            const Icon(Icons.label, color: Color(0xFFD4A017)),
                        filled: true,
                        fillColor: Colors.grey.shade900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Address Field
                    TextField(
                      controller: addressController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Full address',
                        hintStyle: TextStyle(color: Colors.grey.shade600),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Icon(Icons.location_on,
                              color: Color(0xFFD4A017)),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Detect Location Button
                    if (detectedLat == null)
                      GestureDetector(
                        onTap: isDetectingLocation
                            ? null
                            : () async {
                                setSheetState(() => isDetectingLocation = true);
                                try {
                                  // Request permission if needed
                                  await Geolocator.requestPermission();
                                  
                                  final position =
                                      await Geolocator.getCurrentPosition(
                                    locationSettings: const LocationSettings(
                                      accuracy: LocationAccuracy.high,
                                      timeLimit: Duration(seconds: 10),
                                    ),
                                  );

                                  List<Placemark> placemarks =
                                      await placemarkFromCoordinates(
                                    position.latitude,
                                    position.longitude,
                                  );

                                  String fullAddress =
                                      '${placemarks[0].street}, ${placemarks[0].locality}, ${placemarks[0].postalCode}, ${placemarks[0].country}';

                                  setSheetState(() {
                                    addressController.text = fullAddress;
                                    detectedLat = position.latitude;
                                    detectedLng = position.longitude;
                                    isDetectingLocation = false;
                                  });
                                } catch (e) {
                                  setSheetState(
                                      () => isDetectingLocation = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade900,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFD4A017)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isDetectingLocation)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFFD4A017)),
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.location_searching,
                                  color: Color(0xFFD4A017),
                                ),
                              const SizedBox(width: 10),
                              Text(
                                isDetectingLocation
                                    ? 'Detecting...'
                                    : 'Detect Location',
                                style: const TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Location detected',
                                style: TextStyle(
                                  color: Colors.green.shade300,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setSheetState(() {
                                  detectedLat = null;
                                  detectedLng = null;
                                });
                              },
                              child: const Text(
                                'Change',
                                style: TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    // Save Button
                    GestureDetector(
                      onTap: (nameController.text.trim().isEmpty ||
                              addressController.text.trim().isEmpty ||
                              detectedLat == null)
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              final success = await _addressService.addAddress(
                                name: nameController.text.trim(),
                                address: addressController.text.trim(),
                                latitude: detectedLat!,
                                longitude: detectedLng!,
                                isDefault: addresses.isEmpty,
                              );

                              if (success) {
                                await _loadAddresses();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Address added successfully'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to add address'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: (nameController.text.trim().isEmpty ||
                                  addressController.text.trim().isEmpty ||
                                  detectedLat == null)
                              ? Colors.grey.shade700
                              : const Color(0xFFD4A017),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            'Save Address',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: (nameController.text.trim().isEmpty ||
                                      addressController.text.trim().isEmpty ||
                                      detectedLat == null)
                                  ? Colors.grey.shade600
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Saved Addresses',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4A017)),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: addresses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_off_rounded,
                                size: 80,
                                color: Colors.grey.shade700,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No saved addresses',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add your first address to get started',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          itemCount: addresses.length,
                          itemBuilder: (_, index) {
                            final addr = addresses[index];
                            final isSelected = addr['id'] == selectedAddressId;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFD4A017)
                                      : Colors.grey.shade800,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Radio<bool>(
                                            value: true,
                                            groupValue: isSelected,
                                            onChanged: (_) async {
                                              await _addressService
                                                  .setAsDefault(addr['id']);
                                              await _loadAddresses();
                                            },
                                            fillColor: const MaterialStatePropertyAll(
                                              Color(0xFFD4A017),
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                addr['name'] ?? 'Unknown',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if (isSelected)
                                                Container(
                                                  margin:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFFD4A017)
                                                            .withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: const Text(
                                                    'DEFAULT',
                                                    style: TextStyle(
                                                      color: Color(0xFFD4A017),
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      GestureDetector(
                                        onTap: () async {
                                          final confirmed =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor:
                                                  Colors.grey.shade900,
                                              title: const Text(
                                                'Delete Address?',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              content: const Text(
                                                'This action cannot be undone.',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx,
                                                          false),
                                                  child: const Text('Cancel',
                                                      style: TextStyle(
                                                        color: Colors.grey,
                                                      )),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text('Delete',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                      )),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirmed == true) {
                                            final success = await _addressService
                                                .deleteAddress(addr['id']);
                                            if (success) {
                                              await _loadAddresses();
                                            }
                                          }
                                        },
                                        child: Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.red.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    addr['address'] ?? '',
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GestureDetector(
                    onTap: _showAddAddressSheet,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, color: Colors.black),
                          SizedBox(width: 8),
                          Text(
                            'Add New Address',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}