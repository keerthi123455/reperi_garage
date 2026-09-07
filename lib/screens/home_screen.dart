import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/banner.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';
import '../widgets/ask_ai_button.dart';
import '../widgets/banner_coverflow.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/dot_indicator_row.dart';
import '../widgets/location_row.dart';
import '../widgets/packages_side_heading.dart';
import '../widgets/promo_banner.dart';
import '../widgets/quick_action_row.dart';
import '../widgets/service_banner_row.dart';
import '../widgets/services_grid.dart';
import '../widgets/toast_banner.dart';
import '../widgets/vehicle_carousel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.servicesExpandedByDefault = false,
  });

  /// Mirrors the prototype's `servicesExpanded` design-time prop.
  final bool servicesExpandedByDefault;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _selectedBanner = 0;
  // A ValueNotifier (not plain state + setState) — the coverflow reports its
  // continuous drag/settle position every frame, and routing that through
  // setState would rebuild the entire screen (grid, banners, everything) on
  // every drag pixel. A scoped ValueListenableBuilder below keeps that churn
  // limited to just the side heading's opacity and the dot indicator.
  late final ValueNotifier<double> _coverflowPosition;
  bool _servicesOpen = false;
  String? _toastMessage;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    // Looked up by filename rather than a hardcoded index, so this keeps
    // pointing at the right slide even if kCoverflowBanners gets reordered.
    final defaultBanner = kCoverflowBanners.indexOf(kDefaultCoverflowBanner);
    if (defaultBanner >= 0) _selectedBanner = defaultBanner;
    _coverflowPosition = ValueNotifier(_selectedBanner.toDouble());
    _servicesOpen = widget.servicesExpandedByDefault;
  }

  void _flash(String message) {
    setState(() => _toastMessage = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _coverflowPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                AppHeader(
                  onMenu: () => _flash('Menu'),
                  onBell: () => _flash('No new notifications'),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 130),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LocationRow(
                          address: 'Flat 402, Sunrise Enclave, Indiranagar 560038',
                          onChange: () => _flash('Change service address'),
                        ),
                        VehicleCarousel(
                          vehicles: kVehicles,
                          onMore: () => _flash('Vehicle options'),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: QuickActionRow(
                            onBookService: () => _flash('Slot picker opens here'),
                            onBookWashing: () => _flash('Slot picker opens here'),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: ValueListenableBuilder<double>(
                            valueListenable: _coverflowPosition,
                            builder: (context, position, coverflow) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  PackagesSideHeading(
                                    // Fully visible only at the first banner
                                    // (index 0), fading out as soon as the
                                    // coverflow moves away from it.
                                    opacity: (1 - position.abs()).clamp(0.0, 1.0),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: coverflow!),
                                ],
                              );
                            },
                            // Passed as `child` rather than built inline, so
                            // the coverflow itself (with all its own image
                            // decoding/painting) isn't rebuilt every time
                            // `position` changes — only the heading is.
                            child: BannerCoverflow(
                              imagePaths: kCoverflowBanners,
                              selectedIndex: _selectedBanner,
                              onSelect: (i) => setState(() => _selectedBanner = i),
                              onPositionChanged: (p) => _coverflowPosition.value = p,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ValueListenableBuilder<double>(
                          valueListenable: _coverflowPosition,
                          builder: (context, position, _) => DotIndicatorRow(
                            count: kCoverflowBanners.length,
                            activeIndex: position
                                .round()
                                .clamp(0, kCoverflowBanners.length - 1)
                                .toInt(),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                          child: Text(
                            'What does your car need today?',
                            style: GoogleFonts.manrope(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        ServiceBannerRow(
                          imagePaths: kServiceBanners,
                          onTap: (i) => _flash('Slot picker opens here'),
                        ),
                        const SizedBox(height: 16),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'Keep your car showroom-new everyday :',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          // 1269x301 native size — a wide, short banner.
                          child: PromoBanner(
                            assetPath: kSubscriptionBanner,
                            aspectRatio: 1269 / 301,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'Our Services',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        ServicesGrid(
                          expanded: _servicesOpen,
                          onServiceTap: (_) => _flash('Slot picker opens here'),
                          onToggle: () =>
                              setState(() => _servicesOpen = !_servicesOpen),
                        ),
                        const SizedBox(height: 6),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'Get your paint protected :',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          // 1280x426 native size.
                          child: PromoBanner(
                            assetPath: kPpfBanner,
                            aspectRatio: 1280 / 426,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'Stranded somewhere ?',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          // 1280x511 native size.
                          child: PromoBanner(
                            assetPath: kEmergencyBanner,
                            aspectRatio: 1280 / 511,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomNavBar(
                currentIndex: _tab,
                onSelect: (i) {
                  setState(() => _tab = i);
                  const labels = {1: 'Bookings', 3: 'Services', 4: 'Profile'};
                  if (labels.containsKey(i)) _flash('${labels[i]} — coming next');
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 44 + bottomInset,
              child: Center(
                child: AskAiButton(
                  onTap: () => _flash('Ask AI: "What does my Baleno need?"'),
                ),
              ),
            ),
            if (_toastMessage != null)
              Positioned(
                left: 18,
                right: 18,
                bottom: 104 + bottomInset,
                child: ToastBanner(message: _toastMessage!),
              ),
          ],
        ),
      ),
    );
  }
}
