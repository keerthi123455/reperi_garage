import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';

/// The hamburger-menu drawer opened from [AppHeader]'s menu button. Purely
/// presentational — every action is a callback so all the navigation,
/// external-URL, and logout logic stays in `HomeScreen`, matching how the
/// rest of this screen's widgets (e.g. `QuickActionRow`, `BottomNavBar`)
/// are wired.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.profileName,
    required this.activeVehicle,
    required this.onMyVehicles,
    required this.onMyBookings,
    required this.onRoadsideAssistance,
    required this.onAiAdvisor,
    required this.onFleetLogin,
    required this.onServicePartners,
    required this.onBePartner,
    required this.onPrivacyPolicy,
    required this.onTermsAndConditions,
    required this.onContactUs,
    required this.onLogout,
  });

  final String? profileName;
  final Vehicle? activeVehicle;
  final VoidCallback onMyVehicles;
  final VoidCallback onMyBookings;
  final VoidCallback onRoadsideAssistance;
  final VoidCallback onAiAdvisor;
  final VoidCallback onFleetLogin;
  final VoidCallback onServicePartners;
  final VoidCallback onBePartner;
  final VoidCallback onPrivacyPolicy;
  final VoidCallback onTermsAndConditions;
  final VoidCallback onContactUs;
  final VoidCallback onLogout;

  void _select(BuildContext context, VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.ink,
      child: SafeArea(
        child: Column(
          children: [
            _ProfileHeader(profileName: profileName, activeVehicle: activeVehicle),
            Container(height: 1, color: AppColors.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerTile(
                    icon: Symbols.directions_car,
                    label: 'My Vehicles',
                    onTap: () => _select(context, onMyVehicles),
                  ),
                  _DrawerTile(
                    icon: Symbols.calendar_month,
                    label: 'My Bookings',
                    onTap: () => _select(context, onMyBookings),
                  ),
                  _DrawerTile(
                    icon: Symbols.emergency,
                    label: 'Roadside Assistance',
                    onTap: () => _select(context, onRoadsideAssistance),
                  ),
                  _DrawerTile(
                    icon: Symbols.auto_awesome,
                    label: 'AI Advisor',
                    onTap: () => _select(context, onAiAdvisor),
                  ),
                  _DrawerTile(
                    icon: Symbols.local_shipping,
                    label: 'Fleet Login',
                    onTap: () => _select(context, onFleetLogin),
                  ),
                  _DrawerTile(
                    icon: Symbols.storefront,
                    label: 'Service Partners',
                    onTap: () => _select(context, onServicePartners),
                  ),
                  _DrawerTile(
                    icon: Symbols.handshake,
                    label: 'Be a Partner',
                    onTap: () => _select(context, onBePartner),
                  ),
                  _DrawerTile(
                    icon: Symbols.privacy_tip,
                    label: 'Privacy Policy',
                    onTap: () => _select(context, onPrivacyPolicy),
                  ),
                  _DrawerTile(
                    icon: Symbols.description,
                    label: 'Terms & Conditions',
                    onTap: () => _select(context, onTermsAndConditions),
                  ),
                  _DrawerTile(
                    icon: Symbols.call,
                    label: 'Contact Us',
                    onTap: () => _select(context, onContactUs),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: _LogoutButton(onTap: () => _select(context, onLogout)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profileName, required this.activeVehicle});

  final String? profileName;
  final Vehicle? activeVehicle;

  @override
  Widget build(BuildContext context) {
    final name = (profileName == null || profileName!.trim().isEmpty) ? 'Reperi User' : profileName!.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final photoUrl = activeVehicle?.photoUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipOval(
            child: SizedBox(
              width: 64,
              height: 64,
              child: hasPhoto
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _InitialAvatar(initial: initial),
                    )
                  : _InitialAvatar(initial: initial),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.txt,
                  ),
                ),
                if (activeVehicle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${activeVehicle!.brand} ${activeVehicle!.model}'.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mut,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activeVehicle!.carNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.chipBg,
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.manrope(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.accent),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.txt,
                  ),
                ),
              ),
              Icon(Symbols.chevron_right, size: 18, color: AppColors.mut),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: Material(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Symbols.logout, size: 19, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                'LOG OUT',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
