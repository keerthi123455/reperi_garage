import 'dart:math' as math;

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

// =====================================================================
// BOTTOM TOAST
// A small, calm pill that slides up from the bottom of the screen —
// replaces the old bright green / red banners that dropped in at the
// top. Uses the app's own toast surface so it follows light/dark mode,
// sits above the keyboard and the home indicator, and never blocks taps
// underneath it (so it can't get in the way of the Save button).
// =====================================================================

OverlayEntry? _activeToast;

void _showBottomToast(BuildContext context, String message,
    {bool isError = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _removeActiveToast();

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _BottomToast(
      message: message,
      isError: isError,
      onDone: () {
        if (identical(_activeToast, entry)) _removeActiveToast();
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

void _removeActiveToast() {
  final entry = _activeToast;
  _activeToast = null;
  if (entry != null && entry.mounted) entry.remove();
}

class _BottomToast extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDone;

  const _BottomToast({
    required this.message,
    required this.isError,
    required this.onDone,
  });

  @override
  State<_BottomToast> createState() => _BottomToastState();
}

class _BottomToastState extends State<_BottomToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 2600), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom =
        math.max(media.viewInsets.bottom, media.padding.bottom) + 24;
    final accent = widget.isError ? const Color(0xFFE5484D) : goldAccent;

    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _curve,
          builder: (context, child) => Opacity(
            opacity: _curve.value,
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - _curve.value)),
              child: child,
            ),
          ),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.toastBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withOpacity(AppColors.isDark ? 0.45 : 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isError
                            ? Icons.priority_high_rounded
                            : Icons.check_rounded,
                        color: accent,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.txt,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
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

// =====================================================================
// SHARED LITTLE PIECES
// =====================================================================

/// One text-field look for the whole screen — soft filled box, no
/// shadows, gold outline only while typing.
InputDecoration _fieldDecoration({
  required String hint,
  required IconData icon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.mut, fontSize: 13.5),
    prefixIcon: Icon(icon, color: goldAccent, size: 20),
    filled: true,
    fillColor: AppColors.isDark
        ? Colors.white.withOpacity(0.04)
        : const Color(0xFFF3F3F1),
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
      borderSide: const BorderSide(color: goldAccent, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

Widget _sectionLabel(String text, {String? trailing}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: AppColors.mut,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Text(
            trailing,
            style: TextStyle(
              color: AppColors.mut.withOpacity(0.7),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    ),
  );
}

/// Solid gold primary button used for "Add New Address" and "Save
/// Address" — one consistent look, soft shadow instead of a heavy glow.
class _GoldButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onTap;

  const _GoldButton({
    required this.label,
    this.icon,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [goldAccent, goldLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: goldAccent.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.onAccentDark),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: AppColors.onAccentDark, size: 22),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onAccentDark,
                          letterSpacing: 0.3,
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

// =====================================================================
// ADDRESS LIST SCREEN
// =====================================================================

class AddressManagementScreen extends StatefulWidget {
  const AddressManagementScreen({super.key, this.returnAfterSave = false});

  /// When true (opened from PaymentScreen), this screen closes itself as
  /// soon as a new address is saved, returning the customer to checkout.
  final bool returnAfterSave;

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
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    setState(() => loading = true);
    try {
      final addrs =
          await _addressService.getUserAddresses(rethrowOnError: true);
      final defaultAddr =
          await _addressService.getDefaultAddress(rethrowOnError: true);

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

  Future<void> _setDefault(Map<String, dynamic> addr) async {
    try {
      await _addressService.setAsDefault(addr['id']);
      await _loadAddresses();
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not set default address. Please try again.',
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> addr) async {
    final name = (addr['name'] ?? '').toString().trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete this address?',
          style: TextStyle(
            color: AppColors.txt,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Text(
          name.isEmpty
              ? 'This can\'t be undone.'
              : '"$name" will be removed. This can\'t be undone.',
          style: TextStyle(color: AppColors.mut, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                  color: AppColors.mut,
                  fontWeight: FontWeight.w600,
                )),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                  color: Color(0xFFE5484D),
                  fontWeight: FontWeight.w800,
                )),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await _addressService.deleteAddress(addr['id']);
        if (success) {
          await _loadAddresses();
          if (mounted) {
            _showBottomToast(context, 'Address deleted');
          }
        } else {
          if (mounted) {
            _showBottomToast(
                context, 'Could not delete address. Please try again.',
                isError: true);
          }
        }
      } catch (e) {
        if (mounted) {
          _showBottomToast(
              context, 'Could not delete address. Please try again.',
              isError: true);
        }
      }
    }
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
            if (widget.returnAfterSave) {
              Navigator.pop(context, true); // back to checkout
              return;
            }
            _showBottomToast(context, 'Address saved');
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

  IconData _iconFor(String? name) {
    final n = (name ?? '').toLowerCase();
    if (n.contains('home') || n.contains('house')) return Icons.home_rounded;
    if (n.contains('work') || n.contains('office')) return Icons.work_rounded;
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.txt),
        title: Text(
          'My Addresses',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.txt,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(goldAccent),
              ),
            )
          : addresses.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Tap an address to use it for pickup and drop.',
                        style: TextStyle(
                          color: AppColors.mut,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                    for (final addr in addresses)
                      _buildAddressCard(
                        addr,
                        selectedAddressId == addr['id'],
                      ),
                    const SizedBox(height: 8),
                    _buildServiceAreaNote(),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: _GoldButton(
            label: 'Add New Address',
            icon: Icons.add_rounded,
            onTap: _showAddAddressSheet,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: goldAccent.withOpacity(0.1),
              ),
              child: const Icon(
                Icons.add_location_alt_rounded,
                size: 36,
                color: goldAccent,
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
              'Add the address where we should pick up and drop off your vehicle.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.mut,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _buildServiceAreaNote(),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceAreaNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.info_outline_rounded, size: 14, color: AppColors.mut),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'We currently serve within 100 km of Bangalore.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.mut, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> addr, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isSelected ? null : () => _setDefault(addr),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? Color.alphaBlend(
                      goldAccent.withOpacity(AppColors.isDark ? 0.08 : 0.07),
                      AppColors.surfaceRaised)
                  : AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? goldAccent : AppColors.line,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? goldAccent.withOpacity(0.16)
                        : AppColors.txt.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconFor(addr['name']),
                    size: 20,
                    color: isSelected ? goldAccent : AppColors.mut,
                  ),
                ),
                const SizedBox(width: 14),
                // Name + address
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              addr['name'] ?? 'Unknown',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.txt,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: goldAccent.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'DEFAULT',
                                style: TextStyle(
                                  color: AppColors.isDark
                                      ? goldAccent
                                      : goldDark,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        addr['address'] ?? '',
                        style: TextStyle(
                          color: AppColors.mut,
                          fontSize: 13,
                          height: 1.45,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Delete
                IconButton(
                  tooltip: 'Delete address',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDelete(addr),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 21,
                    color: AppColors.mut,
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

// =====================================================================
// ADD ADDRESS SHEET
// =====================================================================

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
  // address instead).
  bool _useManualEntry = false;
  bool isGeocoding = false;
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _nameFocus = FocusNode();

  static const List<String> _quickNames = ['Home', 'Work'];

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
    // Keeps the Home / Work chips in sync with what's typed.
    widget.nameController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    widget.nameController.removeListener(_onThemeChanged);
    _streetController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _nameFocus.dispose();
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
          _showBottomToast(context, 'Location permission is required',
              isError: true);
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
          _showBottomToast(
              context, 'Could not determine address from location',
              isError: true);
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
        _showBottomToast(context, 'Location detected');
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

  Future<void> _showSimpleDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title,
              style: TextStyle(
                  color: AppColors.txt, fontWeight: FontWeight.w800)),
          content: Text(message,
              style: TextStyle(color: AppColors.mut, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK',
                  style: TextStyle(
                      color: goldAccent, fontWeight: FontWeight.w700)),
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
  Future<({double lat, double lng, String address})?>
      _geocodeManualAddress() async {
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final pincode = _pincodeController.text.trim();

    if (street.isEmpty ||
        city.isEmpty ||
        !RegExp(r'^\d{6}$').hasMatch(pincode)) {
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
      final results =
          await locationFromAddress('$street, $city, $pincode, India');
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

  /// Save address to database
  Future<void> _saveAddress() async {
    FocusScope.of(context).unfocus();
    final name = widget.nameController.text.trim();
    final details = widget.detailsController.text.trim();

    if (name.isEmpty) {
      await _showSimpleDialog(
          'Incomplete Address', 'Please enter an address name.');
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
        await _showSimpleDialog(
            'Incomplete Address', 'Please detect your location first.');
        return;
      }
      resolvedAddress = widget.addressController.text.trim();
      lat = selectedLat!;
      lng = selectedLng!;
    }

    // House/flat/door number and landmark, when given, lead the address
    // so it reads naturally: "Flat 302, ABC Apartments, <street, locality,
    // pincode>" rather than being tacked on at the end.
    final address =
        details.isEmpty ? resolvedAddress : '$details, $resolvedAddress';

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

  // ----- small builders -----

  Widget _nameChip(String label) {
    final selected =
        widget.nameController.text.trim().toLowerCase() == label.toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          widget.nameController.text = label;
          widget.nameController.selection =
              TextSelection.collapsed(offset: label.length);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? goldAccent.withOpacity(0.16)
                : AppColors.txt.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? goldAccent : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                label == 'Home' ? Icons.home_rounded : Icons.work_rounded,
                size: 15,
                color: selected ? goldAccent : AppColors.mut,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.txt : AppColors.mut,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeSegment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? goldAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17,
                  color: selected ? AppColors.onAccentDark : AppColors.mut),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppColors.onAccentDark : AppColors.mut,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.txt.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Title + close
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Add Address',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.txt,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded,
                            color: AppColors.mut, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Where should we pick up and drop off your vehicle?',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.mut,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ===== 1. NAME =====
                  _sectionLabel('Save as'),
                  Row(children: _quickNames.map(_nameChip).toList()),
                  const SizedBox(height: 10),
                  TextField(
                    controller: widget.nameController,
                    focusNode: _nameFocus,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _fieldDecoration(
                      hint: 'Or type a name (e.g. Mom\'s place)',
                      icon: Icons.label_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ===== 2. LOCATION =====
                  _sectionLabel('Location'),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.txt.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _modeSegment(
                          label: 'Use my location',
                          icon: Icons.my_location_rounded,
                          selected: !_useManualEntry,
                          onTap: () =>
                              setState(() => _useManualEntry = false),
                        ),
                        const SizedBox(width: 4),
                        _modeSegment(
                          label: 'Type address',
                          icon: Icons.edit_location_alt_outlined,
                          selected: _useManualEntry,
                          onTap: () => setState(() => _useManualEntry = true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        ...previous,
                        if (current != null) current,
                      ],
                    ),
                    child: _useManualEntry
                        ? _ManualAddressTab(
                            key: const ValueKey('manual'),
                            streetController: _streetController,
                            cityController: _cityController,
                            pincodeController: _pincodeController,
                          )
                        : _DetectLocationTab(
                            key: const ValueKey('detect'),
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
                  ),
                  const SizedBox(height: 24),

                  // ===== 3. HOUSE / FLAT / DOOR NO. =====
                  _sectionLabel('Flat / house no. & landmark',
                      trailing: '· optional'),
                  TextField(
                    controller: widget.detailsController,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    minLines: 1,
                    maxLines: 2,
                    decoration: _fieldDecoration(
                      hint: 'e.g. Flat 302, ABC Apartments, near XYZ Mall',
                      icon: Icons.home_work_outlined,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ===== SAVE BUTTON =====
                  _GoldButton(
                    label: 'Save Address',
                    loading: isGeocoding,
                    onTap: isGeocoding ? null : _saveAddress,
                  ),
                ],
              ),
            ),
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
    super.key,
    required this.isDetecting,
    required this.isLocationDetected,
    required this.addressText,
    required this.onDetect,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    // Already found — show the address with a simple way to change it.
    if (isLocationDetected) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
        decoration: BoxDecoration(
          color: goldAccent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: goldAccent.withOpacity(0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.check_circle_rounded,
                  color: goldAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location found',
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    addressText,
                    style: TextStyle(
                      color: AppColors.mut,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: isDetecting ? null : onReset,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.isDark ? goldAccent : goldDark,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text(
                'Change',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // Not found yet — one clear tappable row.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDetecting ? null : onDetect,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: goldAccent.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isDetecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(goldAccent),
                          ),
                        )
                      : const Icon(Icons.my_location_rounded,
                          color: goldAccent, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDetecting
                          ? 'Finding your location…'
                          : 'Detect my current location',
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Best when you\'re at the pickup address',
                      style: TextStyle(color: AppColors.mut, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.mut),
            ],
          ),
        ),
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
    super.key,
    required this.streetController,
    required this.cityController,
    required this.pincodeController,
  });

  @override
  Widget build(BuildContext context) {
    final fieldStyle = TextStyle(
        color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w500);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: streetController,
          textCapitalization: TextCapitalization.words,
          style: fieldStyle,
          decoration: _fieldDecoration(
              hint: 'Street / area (e.g. MG Road)',
              icon: Icons.signpost_outlined),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: cityController,
                textCapitalization: TextCapitalization.words,
                style: fieldStyle,
                decoration: _fieldDecoration(
                    hint: 'City', icon: Icons.location_city_outlined),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextField(
                controller: pincodeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: fieldStyle,
                decoration: _fieldDecoration(
                        hint: 'PIN', icon: Icons.pin_drop_outlined)
                    .copyWith(counterText: ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The PIN code helps us find the exact spot.',
          style: TextStyle(color: AppColors.mut, fontSize: 12),
        ),
      ],
    );
  }
}