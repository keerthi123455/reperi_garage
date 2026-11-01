import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/community_service.dart';
import '../../theme/app_colors.dart';

/// Shared Report bottom-sheet. Short list of reasons, optional one-line
/// "more detail", submits via CommunityService — no round-trip screens.
///
/// Satisfies App Store Review Guideline 1.2 (user-reportable UGC) with a
/// Friendly flow: no scary language, 3-tap submit, visible confirmation.
Future<void> showCommunityReportSheet(
  BuildContext context, {
  required String targetType, // 'reel' | 'post'
  required String targetId,
  required String targetName, // short label shown at the top of the sheet
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceRaised,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _ReportSheet(targetType: targetType, targetId: targetId, targetName: targetName),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.targetType, required this.targetId, required this.targetName});
  final String targetType;
  final String targetId;
  final String targetName;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _submitting = false;
  bool _done = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    final ok = await _safeReport();
    if (!mounted) return;
    if (!ok) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to send a report.')),
      );
      return;
    }
    setState(() { _submitting = false; _done = true; });
  }

  Future<bool> _safeReport() async {
    try {
      if (widget.targetType == 'reel') {
        return await CommunityService.reportReel(widget.targetId, reason: _reason!, details: _details.text);
      }
      return await CommunityService.reportPost(widget.targetId, reason: _reason!, details: _details.text);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _thanks();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.mut.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            ),
            Text('Report this ${widget.targetType}',
              style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(widget.targetName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.mut, fontSize: 13)),
            const SizedBox(height: 4),
            Text("We review every report within 24 hours. Nothing is shared with other users.",
              style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.4)),
            const SizedBox(height: 14),
            for (final r in CommunityService.reportReasons)
              RadioListTile<String>(
                dense: true, contentPadding: EdgeInsets.zero,
                activeColor: AppColors.accent,
                title: Text(r, style: TextStyle(color: AppColors.txt, fontSize: 14.5)),
                value: r, groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
              ),
            if (_reason != null) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _details,
                maxLength: 240,
                maxLines: 2,
                style: TextStyle(color: AppColors.txt, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Add a short note (optional)',
                  hintStyle: TextStyle(color: AppColors.mut),
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.mut.withOpacity(0.3))),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccentDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _reason == null || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Send report', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
            ),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).maybePop(),
              child: Text('Cancel', style: TextStyle(color: AppColors.mut, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thanks() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, color: const Color(0xFF1FAA59), size: 56),
        const SizedBox(height: 12),
        Text('Thanks for the heads-up',
          style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text("We'll review this within 24 hours and take action if needed.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mut, fontSize: 13.5, height: 1.4)),
        const SizedBox(height: 18),
        SizedBox(
          height: 46,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccentDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    ),
  );
}
