import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/booking_api.dart';
import '../services/payment_service.dart';
import '../services/payment_service_factory.dart';
import '../theme/app_colors.dart';
import '../services/vehicle_change_bus.dart';
import 'requirements.dart';
import 'slot_picker.dart';

const _gold = Color(0xFFD4A017);

/// Popup opened from an offer card: pick your apartment → Book Now →
/// Pay ₹X (Razorpay) → booked. Everything happens inside this one popup.
///
/// Prices are NOT decided here: booking-api charges what's in the Supabase
/// `services` table for [serviceKey]. [fallbackPrice] is only shown for a
/// split second before the server's price arrives.
///
/// Returns true if a booking was completed (so the caller can close the
/// offer screens and go back to Home).
Future<bool> showOfferBookingSheet(
  BuildContext context, {
  required String image,
  required String title,
  required String serviceKey,
  required int fallbackPrice,
}) async {
  final booked = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withOpacity(0.35),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, __, ___) => _OfferBookingSheet(
      image: image,
      title: title,
      serviceKey: serviceKey,
      fallbackPrice: fallbackPrice,
    ),
    transitionBuilder: (context, anim, _, child) {
      final t = Curves.easeOutCubic.transform(anim.value);
      return BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6 * t, sigmaY: 6 * t),
        child: Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, 40 * (1 - t)),
            child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
          ),
        ),
      );
    },
  );
  return booked == true;
}

enum _Step { choose, pay, processing, done }

class _Apartment {
  const _Apartment(this.id, this.name);
  final int id;
  final String name;
}

class _OfferBookingSheet extends StatefulWidget {
  const _OfferBookingSheet({
    required this.image,
    required this.title,
    required this.serviceKey,
    required this.fallbackPrice,
  });

  final String image;
  final String title;
  final String serviceKey;
  final int fallbackPrice;

  @override
  State<_OfferBookingSheet> createState() => _OfferBookingSheetState();
}

class _OfferBookingSheetState extends State<_OfferBookingSheet> {
  _Step _step = _Step.choose;

  List<_Apartment>? _apartments; // null = still loading
  String? _loadError;
  _Apartment? _selected;
  BookingSlot? _slot; // when the washer should come (9 AM – 7 PM)

  String? _vehicleId; // the customer's active vehicle, if they have one
  String? _totalDisplay; // server price, e.g. "₹199"
  bool _busy = false;
  String? _error;
  String? _paidRef; // set when paid but the booking still needs saving
  String? _intentId;

  String get _priceText => _totalDisplay ?? '₹${widget.fallbackPrice}';

  @override
  void initState() {
    super.initState();
    _loadApartments();
    _loadActiveVehicle();
  }

  Future<void> _loadApartments() async {
    setState(() {
      _apartments = null;
      _loadError = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('apartments')
          .select('id,name')
          .eq('active', true)
          .order('sort_order', ascending: true)
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 15));
      final list = [
        for (final r in rows)
          _Apartment((r['id'] as num).toInt(), (r['name'] ?? '').toString()),
      ];
      if (mounted) setState(() => _apartments = list);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Couldn\'t load apartments. Check your connection.');
      }
    }
  }

  Future<void> _loadActiveVehicle() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('active_vehicle_id')
          .eq('id', user.id)
          .maybeSingle();
      final id = row?['active_vehicle_id']?.toString();
      if (id != null && id.isNotEmpty) _vehicleId = id;
    } catch (_) {
      // Optional — the booking works without a vehicle.
    }
  }

  // ── Step 1 → 2: Book Now (gets the server's price) ─────────────────────
  Future<void> _bookNow() async {
    if (_selected == null) return;
    if (_slot == null || !_slot!.isStillValid) {
      setState(() {
        _slot = null;
        _error = 'Pick a wash time — same-day slots open 3 hours from now.';
      });
      return;
    }
    // Guest: quick sign-up in place, then straight on to the price.
    if (!await ensureReady(context, contact: true)) return;
    if (!mounted) return;
    if (_vehicleId == null) await _loadActiveVehicle();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final q = await BookingApi.quote(items: [widget.serviceKey]);
      if (!mounted) return;
      setState(() {
        _totalDisplay = q.totalDisplay;
        _step = _Step.pay;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is BookingApiException
            ? e.message
            : 'Couldn\'t get the price. Please try again.';
      });
    }
  }

  // ── Step 2: Pay ₹X — Razorpay, then the server books it ────────────────
  Future<void> _pay() async {
    final apt = _selected;
    if (apt == null) return;
    setState(() {
      _step = _Step.processing;
      _error = null;
    });

    final CreateResult created;
    try {
      created = await BookingApi.create(
        items: [widget.serviceKey],
        cash: false,
        vehicleId: _vehicleId ?? '',
        options: {
          'apartment_id': apt.id,
          'label': apt.name,
          if (_slot != null) 'slot': _slot!.toJson(),
        },
      );
    } catch (e) {
      _failBack(e is BookingApiException
          ? e.message
          : 'Couldn\'t start the payment. Please try again.');
      return;
    }
    _intentId = created.intentId;

    if (created.orderId == null || created.keyId == null || created.amountPaise == null) {
      _failBack('Couldn\'t start the payment. Please try again.');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    final PaymentResult result;
    try {
      result = await getPaymentService().openCheckout(
        orderId: created.orderId!,
        keyId: created.keyId!,
        amountInPaise: created.amountPaise!,
        name: (user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'] ?? 'Reperi').toString(),
        email: user?.email ?? '',
        contact: (user?.phone ?? user?.userMetadata?['phone'] ?? '').toString(),
      );
    } catch (_) {
      _failBack('Couldn\'t open the payment. Please try again.');
      return;
    }

    if (!result.success) {
      _failBack(result.errorMessage ?? 'Payment cancelled.');
      return;
    }

    // Some successful payments come back without ids — the server's
    // webhook still books them, so wait for that instead of failing.
    if (result.orderId == null || result.paymentId == null || result.signature == null) {
      await _finishViaStatus(result.paymentId ?? created.orderId!);
      return;
    }

    try {
      final booking = await BookingApi.confirm(
        orderId: result.orderId!,
        paymentId: result.paymentId!,
        signature: result.signature!,
      );
      if (booking.booked) {
        _succeed();
      } else {
        await _finishViaStatus(result.paymentId!);
      }
    } catch (_) {
      await _finishViaStatus(result.paymentId!);
    }
  }

  /// Paid, but the booking is still being saved — poll the server (which
  /// also retries the save). Never charges again.
  Future<void> _finishViaStatus(String paymentRef) async {
    final intentId = _intentId;
    if (intentId != null) {
      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          final s = await BookingApi.status(intentId);
          if (s.booked) {
            _succeed();
            return;
          }
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    if (!mounted) return;
    setState(() {
      _step = _Step.pay;
      _paidRef = paymentRef;
      _error = 'Your payment went through, but we\'re still saving your '
          'booking. Tap "Check again" — you won\'t be charged twice.';
    });
  }

  void _failBack(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.pay;
      _error = message;
    });
  }

  void _succeed() {
    // Home's car tile switches to "OFFER WASH ACTIVE".
    vehicleChangeBus.notifyVehicleUpdated();
    if (!mounted) return;
    setState(() {
      _step = _Step.done;
      _error = null;
      _paidRef = null;
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canClose = _step != _Step.processing;
    return PopScope(
      canPop: canClose,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.line),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_step == _Step.processing ? _Step.pay : _step),
                      child: switch (_step) {
                        _Step.choose => _chooseView(),
                        _Step.pay || _Step.processing => _payView(),
                        _Step.done => _doneView(),
                      },
                    ),
                  ),
                ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            widget.image,
            width: 54,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 54,
              height: 96,
              color: AppColors.chipBg,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _priceText,
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _gold,
                ),
              ),
            ],
          ),
        ),
        if (_step != _Step.processing)
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(false),
            icon: Icon(Icons.close_rounded, color: AppColors.mut),
          ),
      ],
    );
  }

  Widget _chooseView() {
    final apartments = _apartments;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 22),
        _label('Select your apartment'),
        const SizedBox(height: 8),
        if (_loadError != null)
          _inlineError(_loadError!, retry: _loadApartments)
        else if (apartments == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: _gold),
              ),
            ),
          )
        else if (apartments.isEmpty)
          _note('No apartments are available yet. Please check back soon.')
        else
          _apartmentDropdown(apartments),
        if (_selected != null) ...[
          const SizedBox(height: 20),
          _label('Pick a wash time'),
          const SizedBox(height: 10),
          SlotPicker(
            mode: SlotMode.doorstep,
            value: _slot,
            onChanged: (s) => setState(() {
              _slot = s;
              _error = null;
            }),
            style: SlotPickerStyle(
              accent: _gold,
              onAccent: AppColors.onAccentDark,
              surface: AppColors.surfaceSunken,
              border: AppColors.line,
              text: AppColors.txt,
              muted: AppColors.mut,
              tint: _gold.withOpacity(0.14),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _inlineError(_error!),
        ],
        const SizedBox(height: 22),
        _primaryButton(
          label: 'Book Now',
          busy: _busy,
          onTap: _selected == null || _slot == null || _busy ? null : _bookNow,
        ),
      ],
    );
  }

  Widget _apartmentDropdown(List<_Apartment> apartments) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _selected == null ? AppColors.line : _gold.withOpacity(0.7),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: _selected?.id,
          dropdownColor: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.mut),
          hint: Row(
            children: [
              Icon(Symbols.apartment, size: 20, color: AppColors.mut),
              const SizedBox(width: 10),
              Text(
                'Choose apartment',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mut,
                ),
              ),
            ],
          ),
          items: [
            for (final a in apartments)
              DropdownMenuItem<int>(
                value: a.id,
                child: Row(
                  children: [
                    const Icon(Symbols.apartment, size: 20, color: _gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.txt,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (id) => setState(() {
            _selected = apartments.firstWhere((a) => a.id == id);
            _error = null;
          }),
        ),
      ),
    );
  }

  Widget _payView() {
    final processing = _step == _Step.processing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              _summaryRow('Service', widget.title),
              const SizedBox(height: 10),
              _summaryRow('Apartment', _selected?.name ?? ''),
              if (_slot != null) ...[
                const SizedBox(height: 10),
                _summaryRow('Time', _slot!.fullLabel),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.line),
              ),
              _summaryRow('Total', _priceText, strong: true),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _inlineError(_error!),
        ],
        const SizedBox(height: 20),
        if (_paidRef != null)
          _primaryButton(
            label: 'Check again',
            busy: processing,
            onTap: processing
                ? null
                : () async {
                    setState(() {
                      _step = _Step.processing;
                      _error = null;
                    });
                    await _finishViaStatus(_paidRef!);
                  },
          )
        else
          _primaryButton(
            label: 'Pay $_priceText',
            icon: Icons.lock_rounded,
            busy: processing,
            onTap: processing ? null : _pay,
          ),
        if (!processing && _paidRef == null) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() {
              _step = _Step.choose;
              _error = null;
            }),
            child: Text(
              'Change apartment',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: AppColors.mut,
              ),
            ),
          ),
        ],
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_rounded, size: 14, color: AppColors.mut),
            const SizedBox(width: 6),
            Text(
              'Secure payment via Razorpay',
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.mut),
            ),
          ],
        ),
      ],
    );
  }

  Widget _doneView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFE0B02A), Color(0xFFB8860B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.check_rounded, size: 40, color: Color(0xFF15120A)),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Booking confirmed!',
          style: GoogleFonts.manrope(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: AppColors.txt,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your ${widget.title} at ${_selected?.name ?? 'your apartment'} is booked. '
          'Our team will be in touch shortly.',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(fontSize: 14, height: 1.45, color: AppColors.mut),
        ),
        const SizedBox(height: 22),
        _primaryButton(
          label: 'Done',
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  // ── small pieces ───────────────────────────────────────────────────────

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: AppColors.mut,
        ),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.mut),
        ),
      );

  Widget _summaryRow(String k, String v, {bool strong = false}) => Row(
        children: [
          Text(
            k,
            style: GoogleFonts.manrope(
              fontSize: strong ? 15 : 14,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong ? AppColors.txt : AppColors.mut,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: strong ? 18 : 14,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                color: strong ? _gold : AppColors.txt,
              ),
            ),
          ),
        ],
      );

  Widget _inlineError(String text, {VoidCallback? retry}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFE5484D).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFE5484D)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppColors.txt,
                ),
              ),
            ),
            if (retry != null)
              TextButton(
                onPressed: retry,
                child: const Text('Retry', style: TextStyle(color: _gold)),
              ),
          ],
        ),
      );

  Widget _primaryButton({
    required String label,
    VoidCallback? onTap,
    bool busy = false,
    IconData? icon,
  }) {
    final enabled = onTap != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled || busy ? 1 : 0.45,
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            disabledBackgroundColor: _gold,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Color(0xFF15120A),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: const Color(0xFF15120A)),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF15120A),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
