import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/booking_api.dart';
import '../services/payment_service.dart';
import '../services/payment_service_factory.dart';

/// Monthly wash plan renewal (vehicle dashboard → Monthly Wash Plan tile).
///
/// From 2 days before the plan's last day (IST calendar days, same rule as
/// the server and the daily reminder push) the plan's drop-down shows a blue
/// "RENEW AND PAY" button. Paying adds a new plan that starts when this one
/// ends (booking-api `renew_create` → Razorpay → confirm).

const int kRenewWindowDays = 2;

/// Days from today to the plan's end date, as IST calendar days
/// (0 = ends today, negative = already ended). Null if there is no end date.
int? planDaysLeft(Map subscription) {
  final end = DateTime.tryParse('${subscription['end_date'] ?? ''}');
  if (end == null) return null;
  const ist = Duration(hours: 5, minutes: 30);
  int day(DateTime t) => t.toUtc().add(ist).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  return day(end) - day(DateTime.now());
}

/// Show RENEW AND PAY? (last 2 days, last day — and after it ended, so a
/// lapsed customer can still restart the same plan.)
bool planRenewalDue(Map subscription) {
  final status = (subscription['status'] ?? 'active').toString().toLowerCase();
  if (status == 'renewed') return false;
  final d = planDaysLeft(subscription);
  return d != null && d <= kRenewWindowDays;
}

/// Text for the status pill on the plan tile.
String planStatusLabel(Map subscription) {
  final d = planDaysLeft(subscription);
  if (d == null) return 'Active';
  if (d < 0) return 'Ended';
  if (d == 0) return 'Ends today';
  if (d == 1) return 'Ends tomorrow';
  if (d <= kRenewWindowDays) return 'Ends in $d days';
  return 'Active';
}

class SubscriptionRenewButton extends StatefulWidget {
  const SubscriptionRenewButton({super.key, required this.subscription, required this.onRenewed});

  final Map subscription;

  /// Called after a successful payment (reload the plan + history).
  final VoidCallback onRenewed;

  @override
  State<SubscriptionRenewButton> createState() => _SubscriptionRenewButtonState();
}

class _SubscriptionRenewButtonState extends State<SubscriptionRenewButton> {
  static const Color _blue = Color(0xFF1E5EFF);
  static const Color _blueDark = Color(0xFF123A9E);

  bool _busy = false;
  String? _error;
  String? _intentId;

  String get _headline {
    final d = planDaysLeft(widget.subscription);
    if (d == null || d < 0) return 'Your plan has ended';
    if (d == 0) return 'Your plan ends today';
    if (d == 1) return 'Your plan ends tomorrow';
    return 'Your plan ends in $d days';
  }

  Future<void> _renew() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _error = null;
    });

    final CreateResult created;
    try {
      created = await BookingApi.renewCreate(widget.subscription['id'].toString());
    } catch (e) {
      _fail(e is BookingApiException ? e.message : 'Couldn\'t start the payment. Please try again.');
      return;
    }
    _intentId = created.intentId;
    if (created.orderId == null || created.keyId == null || created.amountPaise == null) {
      _fail('Couldn\'t start the payment. Please try again.');
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
      _fail('Couldn\'t open the payment. Please try again.');
      return;
    }
    if (!result.success) {
      _fail(result.errorMessage ?? 'Payment cancelled.');
      return;
    }

    var done = false;
    if (result.orderId != null && result.paymentId != null && result.signature != null) {
      try {
        done = (await BookingApi.confirm(
          orderId: result.orderId!,
          paymentId: result.paymentId!,
          signature: result.signature!,
        ))
            .booked;
      } catch (_) {}
    }
    // Paid — if the save is still finishing, wait for the server (it retries).
    for (var i = 0; !done && i < 6 && _intentId != null; i++) {
      try {
        done = (await BookingApi.status(_intentId!)).booked;
      } catch (_) {}
      if (!done) await Future.delayed(const Duration(seconds: 2));
    }

    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(done
            ? 'Plan renewed! Your daily washes continue.'
            : 'Payment received — your renewal will show in a minute. You won\'t be charged twice.'),
      ),
    );
    widget.onRenewed();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _blue.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.event_repeat_rounded, color: _blue, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_headline,
                        style: const TextStyle(color: _blue, fontSize: 15, fontWeight: FontWeight.w900, height: 1.25)),
                    const SizedBox(height: 3),
                    Text(
                      'Renew now to keep your daily washes going — same plan, same washer.',
                      style: TextStyle(color: _blue.withOpacity(0.85), fontSize: 12.5, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_blue, _blueDark]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: _blue.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: SizedBox(
              height: 52,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _renew,
                child: _busy
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.autorenew_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('RENEW AND PAY',
                                maxLines: 1,
                                style: TextStyle(
                                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFE5484D), fontSize: 12.5, height: 1.35)),
          ],
        ],
      ),
    );
  }
}
