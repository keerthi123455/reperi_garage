import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/address_management_screen.dart';
import '../screens/profile_screen.dart';
import '../services/address_service.dart';
import '../services/vehicle_change_bus.dart';
import 'guest_sheets.dart';

// One way of handling "something's missing" on every final button (Pay,
// Book, Submit…):
//
//   1. a popup says exactly WHAT is missing,
//   2. "Add …" opens the page where it's added,
//   3. once added, the customer lands back on the SAME screen, same step,
//      and the action carries on,
//   4. "Cancel" just closes the popup — nothing else changes.
//
// Usage:
//   if (!await ensureReady(context, contact: true, vehicle: true)) return;

const _ink = Color(0xFF16213E);
const _yellow = Color(0xFFFFD23F);

/// Checks, in order: signed in → name & phone → vehicle → pickup address.
/// Returns true only when everything asked for is in place.
///
/// [vehicleId] — the vehicle the screen already has (skip the vehicle check
/// when it's set). [onVehicle] gets the vehicle that was found or added.
/// [onAddressAdded] runs after a new address is saved, so the screen can
/// reload its address card.
Future<bool> ensureReady(
  BuildContext context, {
  bool account = true,
  bool contact = false,
  bool vehicle = false,
  bool address = false,
  String? vehicleId,
  ValueChanged<String>? onVehicle,
  VoidCallback? onAddressAdded,
}) async {
  final auth = Supabase.instance.client.auth;

  // 1. Signed in.
  if ((account || contact || vehicle || address) && auth.currentUser == null) {
    final add = await showMissingPopup(
      context,
      icon: Icons.person_rounded,
      title: 'Login required',
      message: "Sign up or log in to continue. It takes 30 seconds and you'll come right back here.",
      addLabel: 'Sign up / Log in',
    );
    if (!add || !context.mounted) return false;
    if (!await requireAccount(context)) return false;
    if (!context.mounted) return false;
  }

  // 2. Name & phone.
  if (contact && !await hasContactDetails()) {
    if (!context.mounted) return false;
    final add = await showMissingPopup(
      context,
      icon: Icons.phone_iphone_rounded,
      title: 'Phone number missing',
      message: 'We need your name and mobile number so our team can reach you about this booking.',
      addLabel: 'Add details',
    );
    if (!add || !context.mounted) return false;
    if (!await requireContactDetails(context)) return false;
    if (!context.mounted) return false;
  }

  // 3. Vehicle.
  if (vehicle && (vehicleId == null || vehicleId.isEmpty)) {
    var id = await findCurrentVehicleId();
    if (!context.mounted) return false;
    if (id == null) {
      final add = await showMissingPopup(
        context,
        icon: Icons.directions_car_rounded,
        title: 'Vehicle required',
        message: "Add your vehicle to continue. You'll come right back here after.",
        addLabel: 'Add vehicle',
      );
      if (!add || !context.mounted) return false;
      final added = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => const ProfileScreen(autoOpenAddVehicle: true, returnAddedVehicle: true),
        ),
      );
      id = added ?? await findCurrentVehicleId();
      if (id == null || !context.mounted) return false;
      vehicleChangeBus.notifyVehicleUpdated();
    }
    onVehicle?.call(id);
  }

  // 4. Pickup address.
  if (address) {
    Map<String, dynamic>? addr;
    try {
      addr = await AddressService().getDefaultAddress();
    } catch (_) {}
    if (!context.mounted) return false;
    if (addr == null) {
      final add = await showMissingPopup(
        context,
        icon: Icons.location_on_rounded,
        title: 'Pickup address missing',
        message: "Add the address where we should come. You'll come right back here after.",
        addLabel: 'Add address',
      );
      if (!add || !context.mounted) return false;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AddressManagementScreen(returnAfterSave: true)),
      );
      try {
        addr = await AddressService().getDefaultAddress();
      } catch (_) {}
      if (addr == null || !context.mounted) return false;
      onAddressAdded?.call();
    }
  }

  return true;
}

/// The customer's active vehicle, or any vehicle they own — null if none.
Future<String?> findCurrentVehicleId() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return null;
  try {
    final profile = await supabase.from('profiles').select('active_vehicle_id').eq('id', user.id).maybeSingle();
    final active = profile?['active_vehicle_id']?.toString();
    if (active != null && active.isNotEmpty) return active;
    final rows = await supabase.from('vehicles').select('id').eq('user_id', user.id).limit(1);
    if ((rows as List).isNotEmpty) return rows.first['id']?.toString();
  } catch (_) {}
  return null;
}

/// "X is missing" popup with Cancel / Add. Returns true when Add is tapped.
Future<bool> showMissingPopup(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String addLabel,
}) async {
  final r = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x8C0B0B14),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, __) => _MissingDialog(icon: icon, title: title, message: message, addLabel: addLabel),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: child),
    ),
  );
  return r == true;
}

/// For things the customer fixes on the same screen (documents, a
/// checkbox, a package choice): lists what's missing, with one "OK".
Future<void> showMissingItems(
  BuildContext context, {
  required String title,
  required List<String> items,
  IconData icon = Icons.checklist_rounded,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x8C0B0B14),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, __) => _MissingDialog(icon: icon, title: title, items: items),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: child),
    ),
  );
}

class _MissingDialog extends StatelessWidget {
  const _MissingDialog({
    required this.icon,
    required this.title,
    this.message,
    this.addLabel,
    this.items,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? addLabel; // null → single "OK" button
  final List<String>? items;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 12))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(color: _yellow, shape: BoxShape.circle),
                  child: Icon(icon, color: _ink, size: 34),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(fontSize: 21, fontWeight: FontWeight.w800, color: _ink),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                        fontSize: 14.5, fontWeight: FontWeight.w600, color: const Color(0xB316213E), height: 1.4),
                  ),
                ],
                if (items != null && items!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ...items!.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(Icons.radio_button_unchecked_rounded, size: 18, color: Color(0xFFE5484D)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(t,
                                  style: GoogleFonts.manrope(
                                      fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink, height: 1.3)),
                            ),
                          ],
                        ),
                      )),
                ],
                const SizedBox(height: 18),
                if (addLabel != null)
                  Row(
                    children: [
                      Expanded(
                        child: _DialogButton(
                          label: 'Cancel',
                          filled: false,
                          onTap: () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _DialogButton(
                          label: addLabel!,
                          filled: true,
                          onTap: () => Navigator.of(context).pop(true),
                        ),
                      ),
                    ],
                  )
                else
                  _DialogButton(label: 'OK', filled: true, onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.label, required this.filled, required this.onTap});
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: filled ? _ink : const Color(0xFFF1F2F6),
          foregroundColor: filled ? Colors.white : _ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
