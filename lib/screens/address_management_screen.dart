import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:reperi_garage/services/address_service.dart';

// Premium color palette
const Color darkBg = Color(0xFF0A0A0A);
const Color cardBg = Color(0xFF111111);
const Color goldAccent = Color(0xFFD4A017);
const Color goldLight = Color(0xFFE8B923);
const Color goldDark = Color(0xFFA68410);

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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _AddressInputSheet(
          context: ctx,
          nameController: nameController,
          addressController: addressController,
          addressService: _addressService,
          onSaved: () {
  _loadAddresses();
  Navigator.pop(ctx);

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Address saved successfully'),
      backgroundColor: Colors.green,
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
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Addresses',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Manage your service locations',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4A017)),
              ),
            )
          : addresses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_off,
                        size: 64,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No addresses yet',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: addresses.length,
                  itemBuilder: (context, index) {
                    final addr = addresses[index];
                    final isSelected = selectedAddressId == addr['id'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected
                                ? goldAccent.withValues(alpha: 0.2)
                                : Colors.black.withValues(alpha: 0.3),
                            blurRadius: isSelected ? 16 : 8,
                            offset: Offset(0, isSelected ? 8 : 4),
                            spreadRadius: isSelected ? 2 : 0,
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(16),
                          border: isSelected
                              ? Border.all(
                                  color: goldAccent,
                                  width: 2,
                                )
                              : Border.all(
                                  color: Colors.grey.shade800,
                                  width: 1,
                                ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                        goldAccent,
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
                                                const EdgeInsets.only(top: 6),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  goldAccent.withValues(
                                                      alpha: 0.2),
                                                  goldLight.withValues(
                                                      alpha: 0.15),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: goldAccent.withValues(
                                                    alpha: 0.3),
                                                width: 0.5,
                                              ),
                                            ),
                                            child: const Text(
                                              'DEFAULT',
                                              style: TextStyle(
                                                color: goldAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    final confirmed = await showDialog<bool>(
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
                                                Navigator.pop(ctx, false),
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
                      ),
                    );
                  },
                ),
      floatingActionButton: null,
      bottomNavigationBar: Padding(
        padding:
            const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 48),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: goldAccent.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _showAddAddressSheet,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [goldAccent, goldLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.black, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Add New Address',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressInputSheet extends StatefulWidget {
  final BuildContext context;
  final TextEditingController nameController;
  final TextEditingController addressController;
  final AddressService addressService;
  final VoidCallback onSaved;

  const _AddressInputSheet({
    required this.context,
    required this.nameController,
    required this.addressController,
    required this.addressService,
    required this.onSaved,
  });

  @override
  State<_AddressInputSheet> createState() => _AddressInputSheetState();
}

class _AddressInputSheetState extends State<_AddressInputSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  double? selectedLat;
  double? selectedLng;
  bool isDetectingLocation = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Detect location and populate address field
  Future<void> _detectLocation() async {
    setState(() => isDetectingLocation = true);
    try {
      // Request permission
      final permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => isDetectingLocation = false);
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Get placemark from coordinates
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not determine address from location'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => isDetectingLocation = false);
        return;
      }

      // Build full address string
      final placemark = placemarks[0];
      final fullAddress =
          '${placemark.street ?? ''}, ${placemark.locality ?? ''}, ${placemark.postalCode ?? ''}, ${placemark.country ?? ''}'
              .replaceAll(RegExp(', +'), ', ')
              .replaceAll(RegExp('^, |, \$'), '');

      // Update UI with detected location
      if (mounted) {
        setState(() {
          widget.addressController.text = fullAddress;
          selectedLat = position.latitude;
          selectedLng = position.longitude;
          isDetectingLocation = false;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location detected successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isDetectingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error detecting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Save address to database
  Future<void> _saveAddress() async {
    FocusScope.of(context).unfocus();
  final name = widget.nameController.text.trim();
  final address = widget.addressController.text.trim();

  // Validate BEFORE attempting to save anything.
  if (name.isEmpty || address.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade900,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Incomplete Address',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            name.isEmpty && address.isEmpty
                ? 'Please enter an address name and your full address.'
                : name.isEmpty
                    ? 'Please enter an address name.'
                    : 'Please enter your full address.',
            style: const TextStyle(
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: goldAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    return;
  }

  try {
    await widget.addressService.addAddress(
      name: name,
      address: address,
      latitude: selectedLat ?? 0.0,
      longitude: selectedLng ?? 0.0,
    );

    if (!mounted) return;

    // Close the bottom sheet first.
    widget.onSaved();

    // Do NOT show the success SnackBar from inside the bottom sheet.
    // The parent screen can show it after the sheet closes.
  } catch (e) {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade900,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Could Not Save Address',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Something went wrong while saving your address.\n\n$e',
            style: const TextStyle(
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: goldAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  padding: EdgeInsets.only(
    bottom: MediaQuery.of(context).viewInsets.bottom,
  ),
  child: Container(
    padding: const EdgeInsets.fromLTRB(
      24,
      28,
      24,
      20,
    ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SingleChildScrollView(
  keyboardDismissBehavior:
      ScrollViewKeyboardDismissBehavior.onDrag,
  padding: const EdgeInsets.only(bottom: 20),
  child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
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

            // ===== ADDRESS NAME FIELD =====
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: widget.nameController,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Address name (e.g., Home, Office)',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                  prefixIcon:
                      const Icon(Icons.label, color: goldAccent, size: 22),
                  filled: true,
                  fillColor: Colors.grey.shade900,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.grey.shade800,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: goldAccent,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ===== TAB BAR =====
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.grey.shade800,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(4),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: goldAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey.shade400,
                labelPadding: EdgeInsets.zero,
                splashFactory: NoSplash.splashFactory,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Type Address'),
                  Tab(text: 'Detect Location'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ===== TAB CONTENT =====
            SizedBox(
              height: 220,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Manual Entry
                  _ManualEntryTab(
                    addressController: widget.addressController,
                  ),

                  // Tab 2: Detect Location
                  _DetectLocationTab(
                    isDetecting: isDetectingLocation,
                    isLocationDetected: selectedLat != null && selectedLng != null,
                    addressText: widget.addressController.text,
                    onDetect: _detectLocation,
                    onReset: () {
                      setState(() {
                        selectedLat = null;
                        selectedLng = null;
                        widget.addressController.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ===== LOCATION DETECTED INDICATOR =====
            if (selectedLat != null && selectedLng != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green.shade400,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Location detected & ready',
                      style: TextStyle(
                        color: Colors.green.shade300,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            if (selectedLat != null && selectedLng != null)
              const SizedBox(height: 16),
            const SizedBox(height: 20),

            // ===== SAVE BUTTON =====
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: goldAccent.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: GestureDetector(
                onTap: _saveAddress,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [goldAccent, goldLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                  ),
                  child: const Text(
                    'Save Address',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

// ===== TAB 1: MANUAL ENTRY =====
class _ManualEntryTab extends StatefulWidget {
  final TextEditingController addressController;

  const _ManualEntryTab({
    required this.addressController,
  });

  @override
  State<_ManualEntryTab> createState() => _ManualEntryTabState();
}

class _ManualEntryTabState extends State<_ManualEntryTab> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: widget.addressController,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Enter full address\n(e.g., 123 Main St, City, ZIP)',
              hintStyle: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Icon(Icons.location_on, color: goldAccent, size: 22),
              ),
              filled: true,
              fillColor: Colors.grey.shade900,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.grey.shade800,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: goldAccent,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ===== TAB 2: DETECT LOCATION =====
class _DetectLocationTab extends StatelessWidget {
  final bool isDetecting;
  final bool isLocationDetected;
  final String addressText;
  final VoidCallback onDetect;
  final VoidCallback onReset;

  const _DetectLocationTab({
    required this.isDetecting,
    required this.isLocationDetected,
    required this.addressText,
    required this.onDetect,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show message when location not detected
          if (!isLocationDetected)
            Column(
              children: [
                Icon(
                  Icons.location_searching,
                  size: 64,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(height: 16),
                Text(
                  'Tap to detect your location',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),

          // Detect Location Button
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: goldAccent.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: GestureDetector(
              onTap: isDetecting ? null : onDetect,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: goldAccent.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isDetecting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(goldAccent),
                        ),
                      )
                    else
                      const Icon(
                        Icons.my_location,
                        color: goldAccent,
                        size: 22,
                      ),
                    const SizedBox(width: 12),
                    Text(
                      isDetecting ? 'Detecting...' : 'Detect Location',
                      style: const TextStyle(
                        color: goldAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Show detected address when available
          if (isLocationDetected) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: goldAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: goldAccent.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    color: goldAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      addressText,
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}