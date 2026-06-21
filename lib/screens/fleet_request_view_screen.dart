import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FleetRequestViewScreen extends StatefulWidget {
  final Map request;

  const FleetRequestViewScreen({
    super.key,
    required this.request,
  });

  @override
  State<FleetRequestViewScreen> createState() =>
      _FleetRequestViewScreenState();
}

class _FleetRequestViewScreenState extends State<FleetRequestViewScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────
  late String? _approvalState; // 'Approved' | 'Rejected' | null
  bool _isSubmitting = false;

  // Animation controllers
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _approvalState = widget.request['customer_approval'] as String?;
    if (widget.request['has_unread_update'] == true) {
      _approvalState = null;
    }

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    if (_approvalState != null) {
      _scaleController.value = 1.0;
      _fadeController.value = 1.0;
    }

    Future.microtask(() async {
      if (widget.request['has_unread_update'] == true) {
        await Supabase.instance.client
            .from('fleet_pickup_requests')
            .update({'has_unread_update': false})
            .eq('id', widget.request['id']);
      }
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleApproval(String decision) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({
            'customer_approval': decision,
            'has_unread_update': true,
            'latest_update_type': decision == 'Approved'
                ? 'CUSTOMER APPROVED'
                : 'CUSTOMER REJECTED',
          })
          .eq('id', widget.request['id']);

      if (!mounted) return;
      setState(() {
        _approvalState = decision;
        _isSubmitting = false;
      });

      _scaleController.reset();
      _fadeController.reset();
      await _fadeController.forward();
      _scaleController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;

    // ── Parse histories ──────────────────────────────────────────────
    final photos = (req['photo_history'] ?? '')
        .toString()
        .split('|')
        .where((e) => e.isNotEmpty)
        .toList();

    final statuses = (req['status_history'] ?? '')
        .toString()
        .split('|')
        .where((e) => e.isNotEmpty)
        .toList();

    final comments = (req['comment_history'] ?? '')
        .toString()
        .split('|')
        .where((e) => e.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),

      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'REQUEST DETAILS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.5,
          ),
        ),
      ),

      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: const BoxDecoration(
            color: Colors.black,
            border: Border(
              top: BorderSide(color: Color(0xFF1E1E1E), width: 1),
            ),
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A017),
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            icon: const Icon(Icons.call, color: Colors.black, size: 20),
            label: const Text(
              'CALL GARAGE',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                fontSize: 14,
              ),
            ),
            onPressed: () {
              // launchUrl here later
            },
          ),
        ),
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Vehicle header ────────────────────────────────────────
            Text(
              req['vehicle_model'] ?? 'Unknown Vehicle',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD4A017).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFFD4A017).withOpacity(0.4)),
              ),
              child: Text(
                req['car_number'] ?? '',
                style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (req['vehicle_photo_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  req['vehicle_photo_url'],
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

            const SizedBox(height: 24),
            _Divider(),

            // ── Current Status ─────────────────────────────────────────
            const SizedBox(height: 20),
            _Label('STATUS'),
            const SizedBox(height: 8),
            _StatusBadge(status: req['status'] ?? 'Pending'),

            const SizedBox(height: 24),
            _Divider(),

            // ── Status History ─────────────────────────────────────────
            if (statuses.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Label('STATUS HISTORY'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.07)),
                ),
                child: Column(
                  children: statuses.asMap().entries.map((entry) {
                    final index = entry.key;
                    final status = entry.value;
                    final isLast = index == statuses.length - 1;
                    return ListTile(
                      leading: Icon(
                        isLast
                            ? Icons.radio_button_checked
                            : Icons.check_circle,
                        color: isLast
                            ? const Color(0xFFD4A017)
                            : const Color(0xFFD4A017).withOpacity(0.5),
                        size: 20,
                      ),
                      title: Text(
                        status,
                        style: TextStyle(
                          color: isLast ? Colors.white : Colors.white54,
                          fontSize: 14,
                          fontWeight: isLast
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),
              _Divider(),
            ],

            // ── Latest Admin Comment ───────────────────────────────────
            const SizedBox(height: 20),
            _Label('ADMIN COMMENT'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: Text(
                req['admin_comment'] ?? 'No updates yet.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),

            // ── Comment History ────────────────────────────────────────
            if (comments.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Label('COMMENT HISTORY'),
              const SizedBox(height: 12),
              Column(
                children: comments.asMap().entries.map((entry) {
                  final index = entry.key;
                  final comment = entry.value;
                  final isLast = index == comments.length - 1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isLast
                            ? const Color(0xFFD4A017).withOpacity(0.07)
                            : const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLast
                              ? const Color(0xFFD4A017).withOpacity(0.3)
                              : Colors.white.withOpacity(0.05),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.comment_outlined,
                            color: isLast
                                ? const Color(0xFFD4A017)
                                : Colors.white24,
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              comment,
                              style: TextStyle(
                                color: isLast
                                    ? Colors.white
                                    : Colors.white54,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 24),
            _Divider(),

            // ── Latest Garage Photo ────────────────────────────────────
            const SizedBox(height: 20),
            _Label('GARAGE PHOTO UPDATE'),
            const SizedBox(height: 10),
            if (req['admin_photo_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  req['admin_photo_url'],
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.07)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.image_not_supported_outlined,
                        color: Colors.white38, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'No photo uploaded yet.',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ],
                ),
              ),

            // ── Photo History ──────────────────────────────────────────
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 24),
              _Label('PHOTO HISTORY'),
              const SizedBox(height: 14),
              Column(
                children: photos.asMap().entries.map((entry) {
                  final index = entry.key;
                  final photo = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            photo,
                            height: 220,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Photo number badge
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFFD4A017)
                                      .withOpacity(0.4)),
                            ),
                            child: Text(
                              'PHOTO ${index + 1}',
                              style: const TextStyle(
                                color: Color(0xFFD4A017),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 24),
            _Divider(),

            // ── Work approval ──────────────────────────────────────────
            const SizedBox(height: 20),
            _Label('WORK APPROVAL'),
            const SizedBox(height: 6),
            const Text(
              'Review the work done and approve or reject below.',
              style: TextStyle(
                  color: Colors.white38, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _approvalState == null
                  ? _buildApprovalButtons()
                  : _buildApprovalResult(_approvalState!),
            ),

            const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildApprovalButtons() {
    return Row(
      key: const ValueKey('buttons'),
      children: [
        Expanded(
          child: _ApprovalButton(
            label: 'APPROVE',
            icon: Icons.check_circle_outline,
            color: const Color(0xFF1DB954),
            isLoading: _isSubmitting,
            onPressed: () => _handleApproval('Approved'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ApprovalButton(
            label: 'REJECT',
            icon: Icons.cancel_outlined,
            color: const Color(0xFFE53935),
            isLoading: _isSubmitting,
            onPressed: () => _handleApproval('Rejected'),
          ),
        ),
      ],
    );
  }

  Widget _buildApprovalResult(String decision) {
    final isApproved = decision == 'Approved';
    final color =
        isApproved ? const Color(0xFF1DB954) : const Color(0xFFE53935);
    final icon = isApproved ? Icons.check_circle : Icons.cancel;
    final label = isApproved ? 'APPROVED' : 'REJECTED';
    final sublabel = isApproved
        ? 'You\'ve approved this work update.'
        : 'You\'ve rejected this work update.';

    return FadeTransition(
      key: ValueKey('result_$decision'),
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 52),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sublabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helper widgets ────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(color: Colors.white.withOpacity(0.07), height: 1);
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF1DB954);
      case 'rejected':
        return const Color(0xFFE53935);
      case 'in progress':
        return const Color(0xFFD4A017);
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          status,
          style: TextStyle(
            color: _color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _ApprovalButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isLoading;
  final VoidCallback onPressed;

  const _ApprovalButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.12),
        foregroundColor: color,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withOpacity(0.5)),
        ),
        elevation: 0,
      ),
      icon: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  color: color, strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          fontSize: 13,
        ),
      ),
      onPressed: isLoading ? null : onPressed,
    );
  }
}