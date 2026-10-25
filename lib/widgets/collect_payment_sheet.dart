import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/garage_theme.dart';

/// "Collect payment" for a cash booking: the customer pays by UPI (scans the
/// QR picked in the CRM → Payment QR) or in cash.
///
/// Returns 'upi' or 'cash' once the garage confirms, or null if they backed
/// out. The caller then closes the booking and saves the method with the
/// `record_payment_collection` RPC (supabase/payment_collection.sql).
Future<String?> showCollectPayment(BuildContext context, {required String amountText}) async {
  while (context.mounted) {
    final method = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChooseSheet(amountText: amountText),
    );
    if (method == null || !context.mounted) return null;

    if (method == 'cash') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => _CashDialog(amountText: amountText),
      );
      if (ok == true) return 'cash';
      return null;
    }

    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UpiSheet(amountText: amountText),
    );
    if (done == true) return 'upi';
    // Back → choose again.
  }
  return null;
}

/// Saves how the booking was paid. Never blocks closing the booking — the
/// method is for matching UPI payments to the bank statement.
Future<void> recordPaymentCollection({
  required String table,
  required String id,
  required String method,
  String? adminId,
}) async {
  try {
    await Supabase.instance.client.rpc('record_payment_collection', params: {
      'p_table': table,
      'p_id': id,
      'p_method': method,
      'p_admin_id': adminId,
    });
  } catch (e) {
    debugPrint('record_payment_collection failed: $e');
  }
}

Widget _sheetFrame({required List<Widget> children}) {
  return Builder(
    builder: (context) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        decoration: const BoxDecoration(
          color: G.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: G.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _amount(String text, {TextAlign align = TextAlign.left}) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
      child: Text(
        text.isEmpty ? '—' : text,
        maxLines: 1,
        style: const TextStyle(color: G.navy, fontSize: 40, fontWeight: FontWeight.w900, height: 1.15),
      ),
    );

Widget _outlineButton(String label, VoidCallback onTap) => SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: G.mut,
          side: const BorderSide(color: G.line, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        ),
      ),
    );

class _ChooseSheet extends StatelessWidget {
  const _ChooseSheet({required this.amountText});

  final String amountText;

  @override
  Widget build(BuildContext context) {
    Widget option(String emoji, Color tint, String title, String sub, String value) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            color: G.card,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.pop(context, value),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: G.line, width: 2),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: G.txt, fontSize: 19, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text(sub,
                              style: const TextStyle(color: G.mut, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: G.faint),
                  ],
                ),
              ),
            ),
          ),
        );

    return _sheetFrame(children: [
      const Text('Collect payment', style: TextStyle(color: G.txt, fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('How is the customer paying?',
          style: TextStyle(color: G.mut, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      _amount(amountText),
      option('📱', G.blueBg, 'UPI', 'Show our QR — the customer scans and pays', 'upi'),
      option('💵', G.greenBg, 'Cash', 'The customer pays you in cash', 'cash'),
      const SizedBox(height: 16),
      _outlineButton('Cancel', () => Navigator.pop(context)),
    ]);
  }
}

class _UpiSheet extends StatefulWidget {
  const _UpiSheet({required this.amountText});

  final String amountText;

  @override
  State<_UpiSheet> createState() => _UpiSheetState();
}

class _UpiSheetState extends State<_UpiSheet> {
  late final Future<Map<String, dynamic>?> _qr = _loadQr();

  Future<Map<String, dynamic>?> _loadQr() async {
    final rows = await Supabase.instance.client.rpc('active_payment_qr');
    final list = rows is List ? rows : const [];
    return list.isEmpty ? null : Map<String, dynamic>.from(list.first as Map);
  }

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(children: [
      const Text('Scan to pay',
          textAlign: TextAlign.center, style: TextStyle(color: G.txt, fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      _amount(widget.amountText, align: TextAlign.center),
      const SizedBox(height: 12),
      FutureBuilder<Map<String, dynamic>?>(
        future: _qr,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator(color: G.navy)),
            );
          }
          final qr = snap.data;
          if (snap.hasError || qr == null || (qr['image_url'] ?? '').toString().isEmpty) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: G.redBg, borderRadius: BorderRadius.circular(14)),
              child: Text(
                snap.hasError
                    ? "Couldn't load the QR. Check the internet and try again, or take cash."
                    : 'No payment QR is set up yet. Please take cash, or ask Reperi to add the QR in the CRM.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: G.red, fontSize: 15, fontWeight: FontWeight.w700, height: 1.4),
              ),
            );
          }
          return Center(
            child: Container(
              width: 270,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: G.navy, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Image.network(
                      qr['image_url'].toString(),
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, p) =>
                          p == null ? child : const Center(child: CircularProgressIndicator(color: G.navy)),
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text("Couldn't load the QR image",
                            textAlign: TextAlign.center, style: TextStyle(color: G.red, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (qr['label'] ?? '').toString(),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: G.mut, fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: G.amberBg, borderRadius: BorderRadius.circular(12)),
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: "Check the customer's phone shows "),
            const TextSpan(text: '"Payment successful"', style: TextStyle(fontWeight: FontWeight.w900)),
            TextSpan(text: ' for ${widget.amountText.isEmpty ? 'the amount' : widget.amountText} before tapping below.'),
          ]),
          style: const TextStyle(color: G.amber, fontSize: 14, fontWeight: FontWeight.w700, height: 1.35),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 58,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: G.green,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('✅ PAYMENT DONE', maxLines: 1, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      _outlineButton('Back', () => Navigator.pop(context, false)),
    ]);
  }
}

class _CashDialog extends StatelessWidget {
  const _CashDialog({required this.amountText});

  final String amountText;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: AlertDialog(
        backgroundColor: G.card,
        surfaceTintColor: G.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💵', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 6),
            const Text('Cash received?',
                textAlign: TextAlign.center, style: TextStyle(color: G.txt, fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Did you collect '),
                TextSpan(
                  text: amountText.isEmpty ? 'the payment' : amountText,
                  style: const TextStyle(color: G.txt, fontWeight: FontWeight.w900),
                ),
                const TextSpan(text: ' in cash from the customer?'),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(color: G.mut, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        actions: [
          Row(
            children: [
              Expanded(child: _outlineButton('No', () => Navigator.pop(context, false))),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: G.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Yes, received', maxLines: 1, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
