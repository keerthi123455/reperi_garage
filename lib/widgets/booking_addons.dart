import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/booking_api.dart';
import '../services/payment_service.dart';
import '../services/payment_service_factory.dart';
import '../theme/app_colors.dart';

/// Add-ons the garage asked for on one booking, shown inside that booking's
/// tile on the vehicle dashboard:
///  • Requested → a pulsing "ADD-ON REQUESTED" banner; tap → popup to
///    Approve & Pay (Razorpay, the garage's price) or Reject (reason / call).
///  • Paid      → listed as a sub-order under the booking.
///  • Rejected  → a small "you rejected" line.
/// Shows nothing when there are no add-ons (or for roadside bookings).
class BookingAddons extends StatefulWidget {
  const BookingAddons({super.key, required this.booking});

  final Map<String, dynamic> booking;

  @override
  State<BookingAddons> createState() => _BookingAddonsState();
}

class _BookingAddonsState extends State<BookingAddons> {
  List<Map<String, dynamic>> _addons = const [];

  bool get _isRoadside =>
      (widget.booking['package_name'] ?? '').toString().toLowerCase().startsWith('roadside assistance');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BookingAddons oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The dashboard re-fetches bookings on refresh → new map → reload.
    if (oldWidget.booking['id'] != widget.booking['id']) _addons = const [];
    if (!identical(oldWidget.booking, widget.booking)) _load();
  }

  Future<void> _load() async {
    final id = widget.booking['id'];
    if (id == null || _isRoadside) return;
    try {
      final rows = await Supabase.instance.client
          .from('addon_services')
          .select()
          .eq('booking_id', id)
          .neq('status', 'Cancelled')
          .order('created_at', ascending: true);
      if (!mounted) return;
      setState(() => _addons = List<Map<String, dynamic>>.from(rows as List));
    } catch (e) {
      // Table not created yet / offline — just show nothing.
      debugPrint('addon_services load failed: $e');
    }
  }

  Future<void> _open(Map<String, dynamic> addon) async {
    HapticFeedback.selectionClick();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddonReviewDialog(addon: addon),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isRoadside || _addons.isEmpty) return const SizedBox.shrink();

    final open = _addons.where((a) => a['status'] == 'Requested' || a['status'] == 'Approved').toList();
    // Paid add-ons and ₹0 ones the garage did for free.
    final paid = _addons.where((a) => a['status'] == 'Paid' || a['status'] == 'Free').toList();
    final rejected = _addons.where((a) => a['status'] == 'Rejected').toList();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in open) ...[
            _RequestedBanner(addon: a, onTap: () => _open(a)),
            const SizedBox(height: 10),
          ],
          if (paid.isNotEmpty) _SubOrders(addons: paid),
          for (final a in rejected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.block_rounded, size: 15, color: AppColors.mut),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add-on rejected: ${a['package_name'] ?? ''} (${_price(a)})',
                      style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _price(Map<String, dynamic> a) {
  if (a['status'] == 'Free' || a['price'] == 0) return 'FREE';
  final p = (a['package_price'] ?? '').toString();
  if (p.isNotEmpty) return p;
  return '₹${a['price'] ?? ''}';
}

const Color _kBlue = Color(0xFF1E5EFF);
const Color _kBlueDark = Color(0xFF123A9E);
const Color _kYellow = Color(0xFFFFD23F);

/// "ADD-ON REQUESTED" — blue with yellow text, gently glowing.
class _RequestedBanner extends StatefulWidget {
  const _RequestedBanner({required this.addon, required this.onTap});

  final Map<String, dynamic> addon;
  final VoidCallback onTap;

  @override
  State<_RequestedBanner> createState() => _RequestedBannerState();
}

class _RequestedBannerState extends State<_RequestedBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.addon;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_kBlue, _kBlueDark]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kYellow.withOpacity(0.55)),
            boxShadow: [
              BoxShadow(color: _kBlue.withOpacity(0.25 + 0.25 * _c.value), blurRadius: 12 + 8 * _c.value),
            ],
          ),
          child: child,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: _kYellow.withOpacity(0.18), shape: BoxShape.circle),
              child: const Icon(Icons.add_task_rounded, color: _kYellow, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ADD-ON REQUESTED',
                    style: TextStyle(color: _kYellow, fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: 0.9),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${a['package_name'] ?? 'Extra work'} · ${_price(a)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to approve or reject',
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: _kYellow),
          ],
        ),
      ),
    );
  }
}

/// Paid add-ons as sub-orders of the booking.
class _SubOrders extends StatelessWidget {
  const _SubOrders({required this.addons});

  final List<Map<String, dynamic>> addons;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ADD-ONS (SUB-ORDERS)',
            style: TextStyle(color: AppColors.mut, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9),
          ),
          for (final a in addons) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: AppColors.mut),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (a['package_name'] ?? 'Add-on').toString(),
                    style: TextStyle(color: AppColors.txt, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _price(a),
                      style: const TextStyle(color: Color(0xFFD4A017), fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1FAA59).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        a['status'] == 'Free' ? 'FREE' : 'PAID',
                        style: const TextStyle(color: Color(0xFF1FAA59), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Popup: approve & pay / reject ────────────────────────────────────────

enum _View { review, paying, reject, rejecting, paid, rejected }

class AddonReviewDialog extends StatefulWidget {
  const AddonReviewDialog({super.key, required this.addon});

  final Map<String, dynamic> addon;

  static const String kSupportPhone = '9353094672';

  @override
  State<AddonReviewDialog> createState() => _AddonReviewDialogState();
}

class _AddonReviewDialogState extends State<AddonReviewDialog> {
  _View _view = _View.review;
  String? _error;
  String? _imageUrl;
  String? _intentId;
  final _reason = TextEditingController();

  Map<String, dynamic> get a => widget.addon;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final stored = (a['image_path'] ?? '').toString();
    if (stored.isEmpty) return;
    final path = stored.contains('/booking-images/') ? stored.split('/booking-images/').last : stored;
    try {
      final url = await Supabase.instance.client.storage.from('booking-images').createSignedUrl(path, 3600);
      if (mounted) setState(() => _imageUrl = url);
    } catch (_) {}
  }

  // ── Approve & pay ──
  Future<void> _approveAndPay() async {
    setState(() {
      _view = _View.paying;
      _error = null;
    });

    final CreateResult created;
    try {
      created = await BookingApi.addonCreate(a['id'].toString());
    } catch (e) {
      _back(e is BookingApiException ? e.message : 'Couldn\'t start the payment. Please try again.');
      return;
    }
    _intentId = created.intentId;
    if (created.orderId == null || created.keyId == null || created.amountPaise == null) {
      _back('Couldn\'t start the payment. Please try again.');
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
        contact: ((user?.phone ?? '').isNotEmpty ? user!.phone! : (user?.userMetadata?['phone'] ?? '')).toString(),
      );
    } catch (_) {
      _back('Couldn\'t open the payment. Please try again.');
      return;
    }

    if (!result.success) {
      _back(result.errorMessage ?? 'Payment cancelled.');
      return;
    }

    if (result.orderId != null && result.paymentId != null && result.signature != null) {
      try {
        final r = await BookingApi.confirm(
          orderId: result.orderId!,
          paymentId: result.paymentId!,
          signature: result.signature!,
        );
        if (r.booked) {
          _done();
          return;
        }
      } catch (_) {}
    }
    // Paid — wait for the server (webhook / retry) to record it.
    final intentId = _intentId;
    if (intentId != null) {
      for (var i = 0; i < 6; i++) {
        try {
          if ((await BookingApi.status(intentId)).booked) {
            _done();
            return;
          }
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    if (!mounted) return;
    setState(() {
      _view = _View.paid;
      _error = 'Payment received. It may take a minute to show as paid — you won\'t be charged twice.';
    });
  }

  void _done() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _view = _View.paid;
      _error = null;
    });
  }

  void _back(String message) {
    if (!mounted) return;
    setState(() {
      _view = _View.review;
      _error = message;
    });
  }

  // ── Reject ──
  Future<void> _reject({required bool thenCall}) async {
    final typed = _reason.text.trim();
    if (!thenCall && typed.isEmpty) {
      setState(() => _error = 'Tell the garage why, or choose "Reject & call".');
      return;
    }
    setState(() {
      _view = _View.rejecting;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('customer_reject_addon', params: {
        'p_id': a['id'].toString(),
        'p_reason': typed.isNotEmpty ? typed : 'Customer wants to discuss on a call',
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _view = _View.reject;
        _error = 'Couldn\'t send that. Please try again.';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _view = _View.rejected);
    if (thenCall) _call();
  }

  Future<void> _call() async {
    final uri = Uri.parse('tel:${AddonReviewDialog.kSupportPhone}');
    try {
      if (!await launchUrl(uri)) throw 'no dialer';
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Call us on ${AddonReviewDialog.kSupportPhone}')),
      );
    }
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    final busy = _view == _View.paying || _view == _View.rejecting;
    return PopScope(
      canPop: !busy,
      child: Dialog(
        backgroundColor: AppColors.surfaceRaised,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _content(busy),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(bool busy) {
    switch (_view) {
      case _View.paid:
        return _result(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF1FAA59),
          title: 'Approved & paid',
          body: _error ?? 'Thanks! ${a['package_name'] ?? 'The add-on'} is added to your booking. The garage has been told to go ahead.',
        );
      case _View.rejected:
        return _result(
          icon: Icons.info_rounded,
          color: AppColors.mut,
          title: 'Add-on rejected',
          body: 'We\'ve told the garage. Nothing was charged.',
        );
      default:
        break;
    }

    return [
      // Header
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: _kBlue, borderRadius: BorderRadius.circular(20)),
            child: const Text(
              'ADD-ON REQUESTED',
              style: TextStyle(color: _kYellow, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
          ),
          const Spacer(),
          if (!busy)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close_rounded, color: AppColors.mut),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if ((a['image_path'] ?? '').toString().isNotEmpty) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: _imageUrl == null
                ? Container(
                    color: AppColors.photoPlaceholder,
                    alignment: Alignment.center,
                    child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Image.network(
                    _imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.photoPlaceholder,
                      alignment: Alignment.center,
                      child: Icon(Icons.broken_image_outlined, color: AppColors.mut),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 14),
      ],
      Text(
        (a['package_name'] ?? 'Extra work').toString(),
        style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w800, height: 1.25),
      ),
      if ((a['description'] ?? '').toString().trim().isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          a['description'].toString(),
          style: TextStyle(color: AppColors.txt.withOpacity(0.8), fontSize: 14, height: 1.4),
        ),
      ],
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text('Price agreed by the garage', style: TextStyle(color: AppColors.mut, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            Text(
              _price(a),
              style: const TextStyle(color: Color(0xFFD4A017), fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Color(0xFFE5484D), fontSize: 13, height: 1.35)),
      ],
      const SizedBox(height: 16),
      if (_view == _View.reject || _view == _View.rejecting) ..._rejectForm() else ..._reviewButtons(),
    ];
  }

  List<Widget> _reviewButtons() {
    final paying = _view == _View.paying;
    return [
      SizedBox(
        height: 52,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1FAA59),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: paying ? null : _approveAndPay,
          child: paying
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'APPROVE & PAY ${_price(a)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                  ),
                ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 48,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE5484D),
            side: const BorderSide(color: Color(0xFFE5484D)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: paying ? null : () => setState(() {
            _view = _View.reject;
            _error = null;
          }),
          child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        ),
      ),
    ];
  }

  List<Widget> _rejectForm() {
    final sending = _view == _View.rejecting;
    return [
      Text('Why don\'t you want this?', style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      TextField(
        controller: _reason,
        enabled: !sending,
        minLines: 2,
        maxLines: 4,
        maxLength: 300,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(color: AppColors.txt, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'e.g. Too expensive, I\'ll get it done later',
          hintStyle: TextStyle(color: AppColors.mut, fontSize: 13.5),
          filled: true,
          fillColor: AppColors.surfaceSunken,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.line)),
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 50,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE5484D),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: sending ? null : () => _reject(thenCall: false),
          child: sending
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : const Text('SEND REJECTION TO GARAGE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.4)),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1FAA59),
            side: const BorderSide(color: Color(0xFF1FAA59)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: sending ? null : () => _reject(thenCall: true),
          icon: const Icon(Icons.call_rounded, size: 18),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('REJECT & CALL US', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          ),
        ),
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: sending ? null : () => setState(() {
          _view = _View.review;
          _error = null;
        }),
        child: Text('Back', style: TextStyle(color: AppColors.mut)),
      ),
    ];
  }

  List<Widget> _result({required IconData icon, required Color color, required String title, required String body}) {
    return [
      const SizedBox(height: 6),
      Icon(icon, color: color, size: 56),
      const SizedBox(height: 12),
      Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.txt, fontSize: 19, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        body,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.txt.withOpacity(0.8), fontSize: 14, height: 1.4),
      ),
      const SizedBox(height: 18),
      SizedBox(
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccentDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
    ];
  }
}
