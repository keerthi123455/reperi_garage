import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'payment_screen.dart';

/// Static, hardcoded package data — deliberately NOT fetched from Supabase,
/// mirroring ServicingPackageScreen's own car equivalent. Unlike that
/// screen's tiers (which each unlock different features), every engine
/// capacity here gets the exact same checklist — only the price changes.
class _EngineTier {
  final String label;
  final int price;

  const _EngineTier({required this.label, required this.price});
}

const _tiers = [
  _EngineTier(label: 'Up to 125 CC', price: 799),
  _EngineTier(label: '126–200 CC', price: 999),
  _EngineTier(label: '201–350 CC', price: 1499),
  _EngineTier(label: '351–500 CC', price: 2999),
  _EngineTier(label: '501 CC & Above', price: 3999),
];

const _checklist = [
  'Complete vehicle general inspection',
  'Air filter inspection',
  'Brake inspection',
  'Tyre pressure and condition check',
  'Battery and electrical check',
  'Chain cleaning, lubrication and adjustment (chain-drive bikes)',
  'Clutch and throttle check',
  'Suspension and steering inspection',
  'Visible nuts, bolts and cable check',
  'Check for visible leaks and unusual noises',
  'Basic vehicle cleaning',
  'Final inspection after servicing',
];

const int _addOnPrice = 400;
const _addOnItems = ['Engine oil change', 'Air filter change', 'Oil filter change'];

/// Formatting helper — every price in this screen is well under a lakh, so
/// a single thousands-comma is all Indian grouping actually needs here.
String _rupees(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return '₹$digits';
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);
  return '₹$head,$tail';
}

class TwoWheelerServicingScreen extends StatefulWidget {
  final String vehicleId;

  const TwoWheelerServicingScreen({super.key, required this.vehicleId});

  @override
  State<TwoWheelerServicingScreen> createState() =>
      _TwoWheelerServicingScreenState();
}

class _TwoWheelerServicingScreenState
    extends State<TwoWheelerServicingScreen> {
  int _selectedTier = 0;
  // Open by default on the pre-selected tier — the checklist is the whole
  // point of this screen, so nobody should have to discover the tap first.
  bool _expanded = true;

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

  void _onTierTap(int i) {
    setState(() {
      if (_selectedTier == i) {
        _expanded = !_expanded;
      } else {
        _selectedTier = i;
        _expanded = true;
      }
    });
  }

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/919353094672?text=${Uri.encodeComponent("Hi, I have a question about the two-wheeler servicing packages.")}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Shows the "Enhance Your Service?" sheet, then books with whichever
  /// total the user picked there. Backing out of the sheet (drag-to-dismiss)
  /// cancels the booking entirely rather than assuming either answer.
  Future<void> _bookNow() async {
    final tier = _tiers[_selectedTier];
    final addOn = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddOnSheet(tierPrice: tier.price),
    );
    if (addOn == null || !mounted) return;

    final total = tier.price + (addOn ? _addOnPrice : 0);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title:
              'General Bike Service (${tier.label})${addOn ? ' + Oil Change Add-on' : ''}',
          price: _rupees(total),
          duration: '1-2 hrs',
          vehicleId: widget.vehicleId,
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              Text(
                'Choose Your Service',
                style: TextStyle(
                  color: AppColors.txt,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Every engine capacity gets the same checklist below — only the price changes. Tap a price to see what\'s included.',
                style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              ..._tiers.asMap().entries.map((e) => _buildTierCard(e.key, e.value)),
              const SizedBox(height: 8),
              _buildAddOnBanner(),
              const SizedBox(height: 28),
              _buildCompareSection(),
              const SizedBox(height: 28),
              _buildWhatsAppCard(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _buildStickyBar(),
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
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'GENERAL SERVICE',
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Keep Your Bike Running Smooth',
                style: TextStyle(
                  color: AppColors.txt,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── PRICE TIER CARD (tap to select + expand its checklist) ──
  Widget _buildTierCard(int i, _EngineTier tier) {
    final isSelected = i == _selectedTier;
    final isOpen = isSelected && _expanded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? Color.alphaBlend(
                  const Color(0xFFD4A017).withOpacity(0.10), AppColors.surfaceRaised)
              : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFFD4A017) : AppColors.line,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _onTierTap(i),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected ? const Color(0xFFD4A017) : AppColors.mut,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        tier.label,
                        style: TextStyle(
                          color: AppColors.txt,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _rupees(tier.price),
                      style: const TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      isOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.mut,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState:
                  isOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(color: AppColors.line, height: 1),
                    const SizedBox(height: 12),
                    Text(
                      "What's Included",
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._checklist.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Color(0xFFD4A017), size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    color: AppColors.txt.withOpacity(0.8),
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 4),
                    Text(
                      'Engine oil, air filter and oil filter replacement aren\'t included in this price — see the add-on below.',
                      style: TextStyle(
                        color: AppColors.mut,
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  // ── OPTIONAL ADD-ON BANNER ──
  Widget _buildAddOnBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFD4A017).withOpacity(0.14),
            const Color(0xFFF5C842).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFD4A017),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'SPECIAL OFFER',
              style: TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Upgrade Your Bike Service',
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Get these additional services for just +₹$_addOnPrice extra!',
            style: TextStyle(color: AppColors.txt.withOpacity(0.75), fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          ..._addOnItems.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Color(0xFFD4A017), size: 15),
                    const SizedBox(width: 8),
                    Text(
                      item,
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 6),
          Text(
            'Subject to vehicle compatibility and parts availability — you\'ll get one more chance to add it when you book.',
            style: TextStyle(
              color: AppColors.mut,
              fontSize: 11,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── COMPARE CHART (every tier gets the same checklist — this is what
  // makes that visible at a glance, rather than just stated in text) ──
  Widget _buildCompareSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compare Plans',
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Same checklist across every engine capacity — only price and the optional add-on change.',
            style: TextStyle(color: AppColors.mut, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: {
                0: const FixedColumnWidth(180),
                for (var i = 1; i <= _tiers.length; i++) i: const FixedColumnWidth(92),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line, width: 2)),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Included',
                        style: TextStyle(color: AppColors.mut, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    ..._tiers.map((t) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            children: [
                              Text(
                                t.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _rupees(t.price),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.txt,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
                for (final item in _checklist)
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.line.withOpacity(0.4))),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          item,
                          style: TextStyle(color: AppColors.txt.withOpacity(0.8), fontSize: 11.5),
                        ),
                      ),
                      for (var t = 0; t < _tiers.length; t++)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Center(
                            child: Icon(Icons.check_circle, color: Colors.green, size: 17),
                          ),
                        ),
                    ],
                  ),
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Oil, air & oil filter change',
                        style: TextStyle(color: AppColors.txt.withOpacity(0.8), fontSize: 11.5),
                      ),
                    ),
                    for (var t = 0; t < _tiers.length; t++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: Text(
                            '+₹$_addOnPrice',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFD4A017),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── WHATSAPP HELP CARD ──
  Widget _buildWhatsAppCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.chat_bubble_rounded, color: Color(0xFF25D366), size: 32),
          const SizedBox(height: 12),
          Text(
            'Still Not Sure?',
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Our Service Advisors are here to help',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.mut, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openWhatsApp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Chat on WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  // ── STICKY BOOK NOW BAR ──
  Widget _buildStickyBar() {
    final tier = _tiers[_selectedTier];
    return GestureDetector(
      onTap: _bookNow,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4A017).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_month, color: Colors.black, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'BOOK ${tier.label} • ${_rupees(tier.price)}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The upsell shown right at booking time — one more chance to add the oil
/// change bundle before paying. Popping `true`/`false` (rather than just
/// closing) is what tells [_TwoWheelerServicingScreenState._bookNow] which
/// total to book; popping with nothing (drag-to-dismiss) cancels the
/// booking instead of silently picking either answer.
class _AddOnSheet extends StatelessWidget {
  const _AddOnSheet({required this.tierPrice});

  final int tierPrice;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Enhance Your Service?',
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'OPTIONAL',
                    style: TextStyle(
                      color: AppColors.mut,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Your General Bike Service includes the standard checklist. Want to add an engine oil and filter replacement?',
              style: TextStyle(
                color: AppColors.txt.withOpacity(0.8),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Engine oil + Air filter + Oil filter',
                          style: TextStyle(
                            color: AppColors.txt,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'All three add-on items in one convenient package.',
                          style: TextStyle(color: AppColors.mut, fontSize: 11.5, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '+₹$_addOnPrice',
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A017),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'Add this package to my booking · Total ${_rupees(tierPrice + _addOnPrice)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Continue without Add-on · Total ${_rupees(tierPrice)}',
                  style: TextStyle(
                    color: AppColors.mut,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
