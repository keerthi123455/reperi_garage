import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/placeholder_box.dart';

/// Static catalog data — deliberately NOT fetched from Supabase, matching
/// the same pattern as the two-wheeler servicing/washing screens.
class _SparePart {
  const _SparePart({
    required this.name,
    required this.brand,
    required this.imagePath,
    required this.description,
  });

  final String name;
  final String brand;
  final String imagePath;
  final String description;
}

const _kFilterParts = [
  _SparePart(
    name: 'HAG Cartridge Oil Filter',
    brand: 'HAG',
    imagePath: 'assets/images/filter1.jpeg',
    description:
        'Cartridge-type automotive oil filter with pleated filtration media, designed to remove contaminants from engine oil and help maintain clean oil circulation through the engine.',
  ),
  _SparePart(
    name: 'HAG Panel Air Filter',
    brand: 'HAG',
    imagePath: 'assets/images/filter2.jpeg',
    description:
        'Panel-style automotive air filter designed to filter dust, dirt and other airborne particles from the engine air intake, helping provide clean air to the engine.',
  ),
  _SparePart(
    name: 'HAG Cabin Air Filter',
    brand: 'HAG',
    imagePath: 'assets/images/filter3.jpeg',
    description:
        "Pleated cabin air filter designed to help filter dust and airborne particles from the air entering the vehicle's passenger cabin through the air-conditioning and ventilation system.",
  ),
  _SparePart(
    name: 'HAG Premium Cabin Air Filter',
    brand: 'HAG',
    imagePath: 'assets/images/filter4.jpeg',
    description:
        "High-quality pleated cabin air filter designed to help capture dust and airborne particles from incoming cabin air, supporting cleaner air circulation through the vehicle's AC and ventilation system.",
  ),
  _SparePart(
    name: 'HAG Engine Air Filter',
    brand: 'HAG',
    imagePath: 'assets/images/filter5.jpeg',
    description:
        'Panel-type engine air filter with pleated filtration media, designed to prevent dust and contaminants from entering the engine through the air-intake system.',
  ),
];

const String _kSupportPhone = '9353094672';
const String _kSupportWhatsApp = '919353094672';
const Color _kAccent = Color(0xFFD4A017);

class SparesScreen extends StatefulWidget {
  const SparesScreen({super.key});

  @override
  State<SparesScreen> createState() => _SparesScreenState();
}

class _SparesScreenState extends State<SparesScreen> {
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
    super.dispose();
  }

  void _openListing(_SparePart part) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: part.name,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) => _SparePartSheet(part: part),
      transitionBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 22),
              _buildHero(),
              const SizedBox(height: 28),
              Text(
                'Filters',
                style: TextStyle(color: AppColors.txt, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Genuine HAG filters for your vehicle.',
                style: TextStyle(color: AppColors.mut, fontSize: 14.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              ..._kFilterParts.asMap().entries.map(
                    (e) => _FadeInEntry(index: e.key, child: _buildListingCard(e.value)),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER ──
  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line),
            ),
            child: Icon(Icons.arrow_back, color: AppColors.txt, size: 20),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'SPARES',
                    style: TextStyle(
                      color: _kAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Genuine Parts, Delivered',
                style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── HERO ── native size is 1280x960 (4:3).
  Widget _buildHero() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/filter_collage.jpeg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const PlaceholderBox(label: 'filter_collage.jpeg', borderRadius: 0),
            ),
            // A bottom-up shade so the overlaid title stays legible
            // regardless of how bright the photo underneath it is.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.35, 1.0],
                  colors: [
                    Colors.black.withOpacity(0.0),
                    Colors.black.withOpacity(0.72),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Genuine Filters,\nBuilt To Protect',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'HAG filters for your engine, cabin & AC.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── LISTING CARD (tap to open the detail popup) ──
  Widget _buildListingCard(_SparePart part) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openListing(part),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Image.asset(
                      part.imagePath,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          PlaceholderBox(label: part.imagePath.split('/').last, borderRadius: 0),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        part.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.txt,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kAccent.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Brand: ${part.brand}',
                          style: const TextStyle(color: _kAccent, fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: AppColors.mut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades + rises a listing into place, each successive [index] settling
/// slightly later than the one before — same idea as the "Edit Vehicle"
/// sheet's own cascade-in fields elsewhere in the app.
class _FadeInEntry extends StatelessWidget {
  const _FadeInEntry({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 16), child: child),
      ),
      child: child,
    );
  }
}

/// The detail popup — image, description, and the two contact actions.
class _SparePartSheet extends StatelessWidget {
  const _SparePartSheet({required this.part});

  final _SparePart part;

  Future<void> _callNow(BuildContext context) async {
    try {
      await launchUrl(Uri.parse('tel:$_kSupportPhone'));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call.')),
      );
    }
  }

  Future<void> _enquire(BuildContext context) async {
    final uri = Uri.parse(
      'https://wa.me/$_kSupportWhatsApp?text=${Uri.encodeComponent("Hi, I'd like to enquire about the ${part.name}.")}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Image.asset(
                            part.imagePath,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                PlaceholderBox(label: part.imagePath.split('/').last, borderRadius: 0),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Material(
                            color: Colors.black.withOpacity(0.4),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Navigator.pop(context),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _kAccent.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Brand: ${part.brand}',
                              style: const TextStyle(color: _kAccent, fontSize: 12.5, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            part.name,
                            style: TextStyle(
                              color: AppColors.txt,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            part.description,
                            style: TextStyle(color: AppColors.txt.withOpacity(0.82), fontSize: 15, height: 1.5),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _callNow(context),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.txt,
                                    side: BorderSide(color: AppColors.line),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  icon: const Icon(Icons.call_rounded, size: 18),
                                  label: const Text('CALL NOW',
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _enquire(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  icon: const Icon(Icons.chat_rounded, color: Colors.white, size: 18),
                                  label: const Text('ENQUIRE',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                                ),
                              ),
                            ],
                          ),
                        ],
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
