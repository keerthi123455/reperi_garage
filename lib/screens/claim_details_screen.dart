import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/error_display.dart';

class ClaimDetailsScreen extends StatefulWidget {
  final int claimId;
  final String adminUsername;

  const ClaimDetailsScreen({
    super.key,
    required this.claimId,
    required this.adminUsername,
  });

  @override
  State<ClaimDetailsScreen> createState() =>
      _ClaimDetailsScreenState();
}

class _ClaimDetailsScreenState
    extends State<ClaimDetailsScreen> {
  final _supabase = Supabase.instance.client;
  final _updateController = TextEditingController();
  Map? claim;
  List updates = [];
  bool loading = true;
  bool _descriptionExpanded = false;
  bool markingDone = false;

  // This claim now has a live delivery_stage/OTP flow just like a regular
  // booking (see claim_screen.dart), but nothing pushes the
  // customer's pickup-OTP entry or the delivery partner's stage taps into
  // this screen on its own — poll instead of leaving staff to keep
  // re-opening it themselves.
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchClaimDetails();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      _silentRefresh();
    });
  }

  /// Same fetch as _fetchClaimDetails, but silent — a background poll
  /// shouldn't pop an error dialog over a transient network hiccup the
  /// way a user-initiated retry should.
  Future<void> _silentRefresh() async {
    try {
      final claimResponse = await _supabase
          .from('claim_table')
          .select('*')
          .eq('id', widget.claimId)
          .single();

      final updatesResponse = await _supabase
          .from('claim_table_updates')
          .select('*')
          .eq('claim_id', widget.claimId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        claim = claimResponse;
        updates = updatesResponse;
      });
    } catch (_) {}
  }

  Future<void> _fetchClaimDetails() async {
    try {
      final claimResponse = await _supabase
          .from('claim_table')
          .select('*')
          .eq('id', widget.claimId)
          .single();

      final updatesResponse = await _supabase
          .from('claim_table_updates')
          .select('*')
          .eq('claim_id', widget.claimId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        claim = claimResponse;
        updates = updatesResponse;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage:
              'Could not load this claim\'s details. Please try again.',
          onRetry: _fetchClaimDetails,
        );
      }
    }
  }

  // How long a document link stays valid once generated — long enough to
  // actually view/download it, short enough that it's useless if it ever
  // leaks (chat log, screenshot, browser history) after that.
  static const _signedUrlExpirySeconds = 300;

  /// Documents are stored in a private bucket by their storage PATH (see
  /// claim_screen.dart's upload code) — this mints a fresh,
  /// short-lived signed URL right before actually opening the document,
  /// rather than reading a permanent public link straight off the row.
  /// Also handles claims submitted before this fix, whose stored value is
  /// still a full public URL rather than a bare path.
  Future<void> _downloadDocument(String storedValue) async {
    try {
      final path = storedValue.contains('/insurance-documents/')
          ? storedValue.split('/insurance-documents/').last
          : storedValue;

      final signedUrl = await _supabase.storage
          .from('insurance-documents')
          .createSignedUrl(path, _signedUrlExpirySeconds);

      if (await canLaunchUrl(Uri.parse(signedUrl))) {
        await launchUrl(Uri.parse(signedUrl));
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not open this document. Please try again.',
        );
      }
    }
  }

  /// One-tap "the repair work is physically finished" signal — mirrors
  /// booking_details_screen.dart's MARK AS DONE exactly, just against
  /// claim_table/claim_status instead of bookings/booking_status.
  /// This is a full doorstep pickup/drop claim now (see
  /// claim_screen.dart), so — like a 'bookings' row with
  /// pickup/drop on — the delivery partner is the one who generates the
  /// return OTP from web/deliverydashboard.html, not this screen.
  Future<void> _markAsDone() async {
    setState(() => markingDone = true);

    try {
      final nowIso = DateTime.now().toIso8601String();

      await _supabase.from('claim_table').update({
        'claim_status': 'Ready for Pickup',
        'marked_done_at': nowIso,
      }).eq('id', widget.claimId);

      if (!mounted) return;
      setState(() {
        claim!['claim_status'] = 'Ready for Pickup';
        claim!['marked_done_at'] = nowIso;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked done — delivery partner & customer notified')),
      );
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not mark this claim as done. Please try again.',
        );
      }
    }

    if (mounted) setState(() => markingDone = false);
  }

  Future<void> _addUpdate() async {
    if (_updateController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a description')),
      );
      return;
    }

    try {
      await _supabase.from('claim_table_updates').insert({
        'claim_id': widget.claimId,
        'admin_id': widget.adminUsername,
        'description': _updateController.text,
        'photo_url': null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _updateController.clear();
      _fetchClaimDetails();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update added!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not add your update. Please try again.',
        );
      }
    }
  }

  @override
  void dispose() {
    _updateController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Claim Details'),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFD4A017)),
        ),
      );
    }

    if (claim == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Claim Details'),
        ),
        body: const Center(child: Text('Claim not found')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Claim Details'),
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              labelColor: const Color(0xFFD4A017),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFFD4A017),
              tabs: const [
                Tab(text: 'Documents'),
                Tab(text: 'Updates'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _buildMarkAsDoneSection(),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Documents Tab
                  _buildDocumentsTab(),
                  // Updates Tab
                  _buildUpdatesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddUpdateDialog(),
        backgroundColor: const Color(0xFFD4A017),
        label: const Text(
          'Add Update',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
          ),
        ),
        icon: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  /// MARK AS DONE for a claim, or its "already done"/"delivered" states —
  /// sits above the Documents/Updates tabs so it's always visible
  /// regardless of which one is open. Mirrors booking_details_screen.dart.
  Widget _buildMarkAsDoneSection() {
    final status = (claim!['claim_status'] ?? 'submitted').toString();

    if (status == 'Delivered') {
      return Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
            SizedBox(width: 10),
            Text(
              'DELIVERED — CLAIM COMPLETE',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, letterSpacing: 0.6, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    if (claim!['marked_done_at'] != null) {
      return Container(
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFFD4A017).withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping_rounded, color: Color(0xFFD4A017), size: 20),
            SizedBox(width: 10),
            Text(
              'READY — WAITING FOR PICKUP',
              style: TextStyle(color: Color(0xFFD4A017), fontWeight: FontWeight.w900, letterSpacing: 0.6, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: markingDone ? null : _markAsDone,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.green.shade600.withOpacity(markingDone ? 0.6 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: markingDone
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text(
                  'MARK AS DONE',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                ),
        ),
      ),
    );
  }

  Widget _buildDocumentsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Damage Description Dropdown at Top
          GestureDetector(
            onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFD4A017).withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Damage Description',
                        style: TextStyle(
                          color: Color(0xFFD4A017),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Icon(
                        _descriptionExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: const Color(0xFFD4A017),
                      ),
                    ],
                  ),
                  if (_descriptionExpanded) ...[
                    const SizedBox(height: 12),
                    Text(
                      claim!['damage_description'] ?? 'No description provided',
                      style: TextStyle(
                        color: Colors.grey.withOpacity(0.9),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Submitted Documents',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _buildDocumentItem('RC Copy', claim!['rc_copy_url']),
          _buildDocumentItem('Driving License', claim!['driving_license_url']),
          _buildDocumentItem('Owner Aadhaar', claim!['owner_aadhaar_url']),
          _buildDocumentItem('Owner PAN', claim!['owner_pan_url']),
          _buildDocumentItem('Insurance Copy', claim!['insurance_copy_url']),
          _buildDocumentItem('Damage Photo', claim!['damage_photo_url']),
          const SizedBox(height: 40), // Extra padding at bottom
        ],
      ),
    );
  }

  Widget _buildDocumentItem(String title, String? url) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFD4A017).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  url != null ? '✅ Uploaded' : '❌ Not uploaded',
                  style: TextStyle(
                    color: url != null ? Colors.green : Colors.red,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (url != null)
            ElevatedButton.icon(
              onPressed: () => _downloadDocument(url),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A017),
                foregroundColor: Colors.black,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUpdatesTab() {
    if (updates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.update, size: 48, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text(
              'No updates yet',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: updates.length,
      itemBuilder: (context, index) {
        final update = updates[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFD4A017).withOpacity(0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Update #${updates.length - index}',
                style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (update['photo_url'] != null)
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: NetworkImage(update['photo_url']),
                      fit: BoxFit.cover,
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                ),
              Text(
                update['description'],
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.9),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                (DateTime.tryParse('${update['created_at'] ?? ''}')
                    ?.toString()
                    .split('.')[0] ?? ''),
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddUpdateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Add Update',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _updateController,
          maxLines: 4,
          maxLength: 500,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Describe the inspection update...',
            hintStyle: TextStyle(color: Colors.grey.withOpacity(0.6)),
            filled: true,
            fillColor: const Color(0xFF0C0C0C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _addUpdate();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A017),
            ),
            child: const Text(
              'Add',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}