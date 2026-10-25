import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/error_display.dart';

/// "Download bill (PDF)" for one booking — shows nothing until the bill
/// exists. Bills are made automatically when the job is done (garage taps
/// MARK AS DONE, wash / inspection / PUC / claim finished, plan bought) and
/// can be replaced from the CRM; this always opens the current one.
///
/// [table] is the booking's table ('bookings', 'pollution_booking', …),
/// [id] its id. Give it a key that changes with the booking's status so it
/// looks again once the job is finished, e.g.
/// `ValueKey('bill-$table-$id-$status')`.
///
/// Works on Android, iOS and web: it opens a short-lived link to the PDF in
/// the browser / PDF viewer, which downloads or lets the customer save/share.
class BillDownloadButton extends StatefulWidget {
  const BillDownloadButton({super.key, required this.table, required this.id, this.topPadding = 12});

  final String table;
  final String id;
  final double topPadding;

  @override
  State<BillDownloadButton> createState() => _BillDownloadButtonState();
}

class _BillDownloadButtonState extends State<BillDownloadButton> {
  static const Color _yellow = Color(0xFFFDF003);
  static const Color _navy = Color(0xFF022B57);

  Map<String, dynamic>? _invoice;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      final row = await Supabase.instance.client
          .from('invoices')
          .select('id, invoice_no, pdf_path, total')
          .eq('booking_table', widget.table)
          .eq('booking_id', widget.id)
          .eq('status', 'issued')
          .maybeSingle();
      if (mounted) setState(() => _invoice = row);
    } catch (e) {
      // No bill yet / table not set up — just don't show the button.
      debugPrint('Bill lookup failed: $e');
    }
  }

  Future<void> _download() async {
    final inv = _invoice;
    if (inv == null || _opening) return;
    setState(() => _opening = true);
    try {
      final path = inv['pdf_path'].toString();
      final signed = await Supabase.instance.client.storage.from('invoices').createSignedUrl(path, 600);
      // download=<file name> makes the browser save it as a PDF file.
      final fileName = '${inv['invoice_no']}.pdf'.replaceAll(RegExp(r'[^A-Za-z0-9.\-]'), '');
      final sep = signed.contains('?') ? '&' : '?';
      final uri = Uri.parse('$signed${sep}download=${Uri.encodeQueryComponent(fileName)}');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ErrorDisplay.showPremiumToast(context, message: "Couldn't open the bill. Please try again.", icon: Icons.error_outline_rounded);
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(context, error: e, customMessage: "Couldn't download the bill. Please try again.");
      }
      debugPrint('Bill download failed: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invoice == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: widget.topPadding),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _opening ? null : _download,
          style: ElevatedButton.styleFrom(
            backgroundColor: _yellow,
            foregroundColor: _navy,
            disabledBackgroundColor: _yellow.withOpacity(0.6),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: _opening
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: _navy))
              : const Icon(Icons.download_rounded, size: 22),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Download bill (PDF)', maxLines: 1, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    );
  }
}
