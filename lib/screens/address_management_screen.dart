import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:reperi_garage/services/address_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/error_display.dart';

// Brand gold — a fixed accent, not a themed surface, so it stays literal
// across light and dark mode like it does on the other package screens.
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
  OverlayEntry? _currentOverlay;

  @override
  void initState() {
    super.initState();
    _addressService = AddressService();
    _loadAddresses();
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
    _currentOverlay?.remove();
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    setState(() => loading = true);
    try {
      final addrs = await _addressService.getUserAddresses(rethrowOnError: true);
      final defaultAddr = await _addressService.getDefaultAddress(rethrowOnError: true);

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
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage:
              'Could not load your addresses. Please check your connection and try again.',
          onRetry: _loadAddresses,
        );
      }
    }
  }

  void _showOverlayMessage(String message, {bool isError = false}) {
    // Remove existing overlay if any
    _currentOverlay?.remove();

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isError
                    ? Colors.red.shade700
                    : Colors.green.shade600,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: (isError ? Colors.red : Colors.green)
                        .withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    isError ? Icons.error_rounded : Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    _currentOverlay = overlayEntry;

    // Auto-remove after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
      _currentOverlay = null;
    });
  }

  void _showAddAddressSheet() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final detailsController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _AddressInputSheet(
          context: ctx,
          nameController: nameController,
          addressController: addressController,
          detailsController: detailsController,
          addressService: _addressService,
          onSaved: () {
            _loadAddresses();
            Navigator.pop(ctx);
            _showOverlayMessage('Address saved successfully', isError: false);
          },
          onError: (error) {
            Navigator.pop(ctx);
            ErrorDisplay.showPremiumError(
              context,
              error: error,
              customMessage: 'Could not save this address. Please try again.',
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Addresses',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.txt,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Manage your service locations',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.mut,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: goldAccent.withOpacity(0.1),
                          ),
                          child: Icon(
                            Icons.location_off_rounded,
                            size: 40,
                            color: goldAccent.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No addresses yet',
                          style: TextStyle(
                            color: AppColors.txt,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add one below using your current location — '
                          'we\'ll use it for pickup and drop-off.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.mut,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
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
                                ? goldAccent.withOpacity(0.2)
                                : Colors.black.withOpacity(0.3),
                            blurRadius: isSelected ? 16 : 8,
                            offset: Offset(0, isSelected ? 8 : 4),
                            spreadRadius: isSelected ? 2 : 0,
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(16),
                          border: isSelected
                              ? Border.all(
                                  color: goldAccent,
                                  width: 2,
                                )
                              : Border.all(
                                  color: AppColors.line,
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
                                        try {
                                          await _addressService
                                              .setAsDefault(addr['id']);
                                          await _loadAddresses();
                                        } catch (e) {
                                          if (!mounted) return;
                                          ErrorDisplay.showPremiumError(
                                            context,
                                            error: e,
                                            customMessage:
                                                'Could not set default address. Please try again.',
                                          );
                                        }
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
                                          style: TextStyle(
                                            color: AppColors.txt,
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
                                                  goldAccent.withOpacity(0.2),
                                                  goldLight.withOpacity(0.15),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: goldAccent.withOpacity(0.3),
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
                                        backgroundColor: AppColors.surfaceRaised,
                                        title: Text(
                                          'Delete Address?',
                                          style: TextStyle(
                                            color: AppColors.txt,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        content: Text(
                                          'This action cannot be undone.',
                                          style: TextStyle(
                                            color: AppColors.mut,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: Text('Cancel',
                                                style: TextStyle(
                                                  color: AppColors.mut,
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
                                      try {
                                        final success = await _addressService
                                            .deleteAddress(addr['id']);
                                        if (success) {
                                          await _loadAddresses();
                                          if (mounted) {
                                            _showOverlayMessage(
                                                'Address deleted successfully',
                                                isError: false);
                                          }
                                        } else {
                                          if (mounted) {
                                            _showOverlayMessage(
                                                'Could not delete address. Please try again.',
                                                isError: true);
                                          }
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          _showOverlayMessage(
                                              'Could not delete address. Please try again.',
                                              isError: true);
                                        }
                                      }
                                    }
                                  },
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.red.shade500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              addr['address'] ?? '',
                              style: TextStyle(
                                color: AppColors.mut,
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
                color: goldAccent.withOpacity(0.35),
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
                    color: Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded,
                        color: AppColors.onAccentDark, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Add New Address',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.onAccentDark,
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

  /// House/flat/door number and landmark — the part reverse-geocoding
  /// can never know, since it only describes the street/area a GPS point
  /// falls on. Kept as its own field so it's clearly optional and doesn't
  /// get confused with the detected address, but is merged into the one
  /// `address` string the database actually stores.
  final TextEditingController detailsController;

  final AddressService addressService;
  final VoidCallback onSaved;
  final Function(dynamic) onError;

  const _AddressInputSheet({
    required this.context,
    required this.nameController,
    required this.addressController,
    required this.detailsController,
    required this.addressService,
    required this.onSaved,
    required this.onError,
  });

  @override
  State<_AddressInputSheet> createState() => _AddressInputSheetState();
}

class _AddressInputSheetState extends State<_AddressInputSheet> {
  double? selectedLat;
  double? selectedLng;
  bool isDetectingLocation = false;

  // Manual entry — a second way to set the location besides GPS detection,
  // for when the customer isn't standing at the pickup address (e.g.
  // booking for a relative's place, or their own live GPS point falls
  // outside the service area and they need to pick a real in-area
  // address instead). Kept as a plain toggle rather than a full
  // TabBar/TabController — same visual effect, less machinery.
  bool _useManualEntry = false;
  bool isGeocoding = false;
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _streetController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
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
          setState(() => isDetectingLocation = false);
          _showDetectionMessage(
              'Location permission is required', isError: true);
        }
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
          setState(() => isDetectingLocation = false);
          _showDetectionMessage(
              'Could not determine address from location', isError: true);
        }
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
        _showDetectionMessage('Location detected successfully', isError: false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isDetectingLocation = false);
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not detect your location. Please try again.',
          onRetry: _detectLocation,
        );
      }
    }
  }

  void _showDetectionMessage(String message, {required bool isError}) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isError
                  ? Colors.red.shade700
                  : Colors.green.shade600,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: (isError ? Colors.red : Colors.green)
                      .withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_rounded : Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    Future.delayed(const Duration(seconds: 2, milliseconds: 500), () {
      overlayEntry.remove();
    });
  }

  Future<void> _showSimpleDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(title, style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800)),
          content: Text(message, style: TextStyle(color: AppColors.mut, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK', style: TextStyle(color: goldAccent, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  /// Turns the manual Street/City/PIN Code fields into real coordinates —
  /// the same `geocoding` package already used elsewhere in this file for
  /// the reverse direction (coordinates → address on Detect Location).
  /// Returns null (after showing why) if the fields are incomplete or
  /// nothing could be found for them.
  Future<({double lat, double lng, String address})?> _geocodeManualAddress() async {
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final pincode = _pincodeController.text.trim();

    if (street.isEmpty || city.isEmpty || !RegExp(r'^\d{6}$').hasMatch(pincode)) {
      await _showSimpleDialog(
        'Incomplete Address',
        'Please fill in the street/area, city, and a valid 6-digit PIN code.',
      );
      return null;
    }

    setState(() => isGeocoding = true);
    try {
      // The PIN code is what actually narrows this down to the right
      // area — without it, a common street name could match a
      // same-named street in a completely different city.
      final results = await locationFromAddress('$street, $city, $pincode, India');
      if (results.isEmpty) {
        if (mounted) setState(() => isGeocoding = false);
        await _showSimpleDialog(
          "Couldn't Find That Address",
          'Try adding more detail (a nearby landmark or a fuller street name), '
              'or double check the PIN code.',
        );
        return null;
      }
      if (mounted) setState(() => isGeocoding = false);
      return (
        lat: results.first.latitude,
        lng: results.first.longitude,
        address: '$street, $city - $pincode',
      );
    } catch (e) {
      if (mounted) setState(() => isGeocoding = false);
      await _showSimpleDialog(
        "Couldn't Find That Address",
        'Something went wrong looking that address up. Please check your '
            'connection and try again.',
      );
      return null;
    }
  }

  Widget _locationModeTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? goldAccent.withOpacity(0.14) : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? goldAccent : AppColors.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? goldAccent : AppColors.mut),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? goldAccent : AppColors.mut,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Save address to database
  Future<void> _saveAddress() async {
    FocusScope.of(context).unfocus();
    final name = widget.nameController.text.trim();
    final details = widget.detailsController.text.trim();

    if (name.isEmpty) {
      await _showSimpleDialog('Incomplete Address', 'Please enter an address name.');
      return;
    }

    String resolvedAddress;
    double lat;
    double lng;

    if (_useManualEntry) {
      final geocoded = await _geocodeManualAddress();
      if (geocoded == null) return; // dialog already shown
      resolvedAddress = geocoded.address;
      lat = geocoded.lat;
      lng = geocoded.lng;
    } else {
      if (selectedLat == null || selectedLng == null) {
        await _showSimpleDialog('Incomplete Address', 'Please detect your location first.');
        return;
      }
      resolvedAddress = widget.addressController.text.trim();
      lat = selectedLat!;
      lng = selectedLng!;
    }

    // House/flat/door number and landmark, when given, lead the address
    // so it reads naturally: "Flat 302, ABC Apartments, <street, locality,
    // pincode>" rather than being tacked on at the end.
    final address = details.isEmpty ? resolvedAddress : '$details, $resolvedAddress';

    try {
      await widget.addressService.addAddress(
        name: name,
        address: address,
        latitude: lat,
        longitude: lng,
        // A freshly added address is what the customer just told us they
        // want to use right now — it should be the one their next
        // booking picks up, not silently sit unselected until they find
        // the radio button on the address list themselves.
        isDefault: true,
      );

      if (!mounted) return;

      // Call parent callback to show success message and close sheet
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;

      // Let the parent close this sheet and show a plain-English error.
      widget.onError(e);
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
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 40,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Add Address',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Detect your current location, or enter an address manually.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.mut,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // ===== ADDRESS NAME FIELD =====
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: widget.nameController,
                  style: TextStyle(
                    color: AppColors.txt,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Address name (e.g., Home, Office)',
                    hintStyle: TextStyle(
                      color: AppColors.mut,
                      fontSize: 14,
                    ),
                    prefixIcon:
                        const Icon(Icons.label, color: goldAccent, size: 22),
                    filled: true,
                    fillColor: AppColors.surfaceRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: AppColors.line,
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

              // ===== HOUSE / FLAT / DOOR NO. FIELD =====
              Text(
                'House / flat / door no. & landmark (optional)',
                style: TextStyle(
                  color: AppColors.mut,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: widget.detailsController,
                  style: TextStyle(
                    color: AppColors.txt,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'e.g. Flat 302, ABC Apartments, near XYZ Mall',
                    hintStyle: TextStyle(color: AppColors.mut, fontSize: 13),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(Icons.home_work_outlined,
                          color: goldAccent, size: 22),
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: AppColors.line, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: goldAccent, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ===== LOCATION =====
              Text(
                'Location',
                style: TextStyle(
                  color: AppColors.mut,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Two ways to set the location: detect it live, or type it
              // — for whenever the customer isn't standing at the pickup
              // spot themselves (booking for someone else, or their own
              // live location happens to be out of the service area).
              Row(
                children: [
                  Expanded(
                    child: _locationModeTab(
                      label: 'Detect Location',
                      icon: Icons.my_location,
                      selected: !_useManualEntry,
                      onTap: () => setState(() => _useManualEntry = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _locationModeTab(
                      label: 'Enter Address',
                      icon: Icons.edit_location_alt_outlined,
                      selected: _useManualEntry,
                      onTap: () => setState(() => _useManualEntry = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_useManualEntry)
                _ManualAddressTab(
                  streetController: _streetController,
                  cityController: _cityController,
                  pincodeController: _pincodeController,
                )
              else
                _DetectLocationTab(
                  isDetecting: isDetectingLocation,
                  isLocationDetected:
                      selectedLat != null && selectedLng != null,
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
              const SizedBox(height: 24),

              // ===== LOCATION DETECTED INDICATOR (Detect mode only —
              // manual mode confirms by actually saving, since the
              // address isn't geocoded until Save is tapped) =====
              if (!_useManualEntry && selectedLat != null && selectedLng != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.1),
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
              if (!_useManualEntry && selectedLat != null && selectedLng != null)
                const SizedBox(height: 16),
              const SizedBox(height: 20),

              // ===== SAVE BUTTON =====
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: goldAccent.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: GestureDetector(
                  onTap: isGeocoding ? null : _saveAddress,
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
                        color: Colors.white.withOpacity(0.15),
                        width: 1.5,
                      ),
                    ),
                    child: isGeocoding
                        ? const Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                              ),
                            ),
                          )
                        : Text(
                            'Save Address',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: AppColors.onAccentDark,
                            ),
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

// ===== DETECT LOCATION =====
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
                  color: AppColors.mut,
                ),
                const SizedBox(height: 16),
                Text(
                  'Tap to detect your location',
                  style: TextStyle(
                    color: AppColors.mut,
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
                  color: goldAccent.withOpacity(0.2),
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
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: goldAccent.withOpacity(0.4),
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
                color: goldAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: goldAccent.withOpacity(0.3),
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
                        color: AppColors.mut,
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

// ===== MANUAL ADDRESS ENTRY =====
// Street + City + a dedicated PIN Code field — the PIN code is what
// actually narrows a forward-geocode lookup down to the right area (a
// street name alone is rarely unique across the country), so it gets its
// own field rather than being just another word buried in one free-text
// box. Nothing is geocoded here as you type; that happens once, when
// Save Address is tapped (see _geocodeManualAddress in the parent).
class _ManualAddressTab extends StatelessWidget {
  final TextEditingController streetController;
  final TextEditingController cityController;
  final TextEditingController pincodeController;

  const _ManualAddressTab({
    required this.streetController,
    required this.cityController,
    required this.pincodeController,
  });

  InputDecoration _decoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.mut, fontSize: 13),
      prefixIcon: Icon(icon, color: goldAccent, size: 20),
      filled: true,
      fillColor: AppColors.surfaceRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.line, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: goldAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: streetController,
          style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w500),
          decoration: _decoration(hint: 'Street / area (e.g. MG Road)', icon: Icons.signpost_outlined),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: cityController,
                style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w500),
                decoration: _decoration(hint: 'City', icon: Icons.location_city_outlined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: pincodeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w500),
                decoration: _decoration(hint: 'PIN Code', icon: Icons.pin_drop_outlined)
                    .copyWith(counterText: ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'The PIN code helps us find the exact location.',
          style: TextStyle(color: AppColors.mut, fontSize: 11.5),
        ),
      ],
    );
  }
}