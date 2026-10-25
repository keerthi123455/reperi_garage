import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/bill_download_button.dart';
import '../widgets/booking_addons.dart';
import '../widgets/inspection_view_widget.dart';
import '../widgets/error_display.dart';
import '../widgets/slot_picker.dart';

/// Live updates for one booking: a summary card with the status in plain
/// words and a progress bar, the garage's updates newest-first (tap a photo
/// to see it full screen), and Chat / Call fixed at the bottom. Refreshes
/// itself every 15 seconds and on pull-down.
class BookingTrackingScreen extends StatefulWidget {
  final Map booking;
  final bool autoOpenChat;

  const BookingTrackingScreen({
    super.key,
    required this.booking,
    this.autoOpenChat = false,
  });

  @override
  State<BookingTrackingScreen> createState() => _BookingTrackingScreenState();
}

class _BookingTrackingScreenState extends State<BookingTrackingScreen> {
  static const _signedUrlExpirySeconds = 300;
  static const _supportNumber = '9353094672';

  static const Color _gold = Color(0xFFD4A017);
  static const Color _green = Color(0xFF1FAA59);
  static const Color _red = Color(0xFFE5484D);

  List updates = [];
  bool loading = true;
  // Set when fetchUpdates() fails — drives a retry screen instead of
  // leaving the loading spinner stuck forever on a bad network moment.
  bool _loadError = false;
  bool hasUnreadMessages = false;
  bool _showOlder = false;

  /// Live copy of the booking — starts as what the list passed in, then
  /// refreshed from the database so the status here never goes stale.
  late Map<String, dynamic> _booking = Map<String, dynamic>.from(widget.booking);

  Timer? _poll;

  /// Signed photo links, reused for a few minutes so the 15-second refresh
  /// doesn't re-sign (and re-download) every photo each time.
  final Map<String, ({Future<String> url, DateTime at})> _urlCache = {};

  @override
  void initState() {
    super.initState();
    fetchUpdates();
    checkUnreadMessages();
    _markUpdateAsRead();
    if (widget.autoOpenChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openChat());
    }
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      fetchUpdates(silent: true);
      checkUnreadMessages();
      _refreshBooking();
    });
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  /// booking-images is a private bucket — `storedValue` is normally just the
  /// storage path (see booking_details_screen.dart's uploadUpdate()), but
  /// older rows may still hold a full public URL from before the bucket was
  /// made private, so both are handled here.
  Future<String> _resolveImageUrl(String storedValue) {
    final cached = _urlCache[storedValue];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(minutes: 4)) {
      return cached.url;
    }
    final path = storedValue.contains('/booking-images/')
        ? storedValue.split('/booking-images/').last
        : storedValue;
    final future = Supabase.instance.client.storage
        .from('booking-images')
        .createSignedUrl(path, _signedUrlExpirySeconds);
    _urlCache[storedValue] = (url: future, at: DateTime.now());
    return future;
  }

  static bool _isVideoPath(String p) =>
      RegExp(r'\.(mp4|mov|m4v|webm|3gp)(\?|$)', caseSensitive: false).hasMatch(p);

  Future<void> _markUpdateAsRead() async {
    try {
      await Supabase.instance.client
          .from('bookings')
          .update({'has_unread_update': false}).eq('id', widget.booking['id']);
    } catch (_) {
      // Non-fatal — worst case the home screen badge stays lit one
      // extra visit.
    }
  }

  /// [silent]: background refresh — keep showing what's there if it fails.
  Future<void> fetchUpdates({bool silent = false}) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('booking_updates')
          .select()
          .eq('booking_id', widget.booking['id'])
          .order('created_at', ascending: true);

      if (!mounted) return;

      setState(() {
        updates = response;
        loading = false;
        _loadError = false;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        loading = false;
        _loadError = true;
      });
    }
  }

  /// Re-reads this booking's row so the status / progress stay current.
  Future<void> _refreshBooking() async {
    try {
      final row = await Supabase.instance.client
          .from('bookings')
          .select()
          .eq('id', widget.booking['id'])
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _booking = {..._booking, ...row});
    } catch (_) {
      // Keep the last known state.
    }
  }

  Future<void> _pullToRefresh() async {
    await Future.wait([
      fetchUpdates(silent: true),
      checkUnreadMessages(),
      _refreshBooking(),
    ]);
  }

  Future<void> checkUnreadMessages() async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('booking_chats')
          .select()
          .eq('booking_id', widget.booking['id'])
          .eq('sender', 'admin')
          .eq('is_read_by_consumer', false);

      if (!mounted) return;

      setState(() {
        hasUnreadMessages = (response as List).isNotEmpty;
      });
    } catch (e) {
      // Background check only — no loading state tied to this and no
      // user-initiated action, so just log it instead of surfacing a toast.
      debugPrint('Error checking unread messages: $e');
    }
  }

  void openChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatSheet(
        bookingId: widget.booking['id'],
        sender: 'consumer',
        onMessagesRead: () {
          setState(() => hasUnreadMessages = false);
        },
      ),
    );
  }

  Future<void> _call() async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: _supportNumber));
    } catch (_) {
      if (!mounted) return;
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Call us on $_supportNumber',
        icon: Icons.phone_rounded,
      );
    }
  }

  // ── Status in plain words + progress ─────────────────────────────────
  bool get _pickup => (_booking['pickupdrop'] ?? '').toString().toLowerCase() == 'yes';
  String get _status => (_booking['booking_status'] ?? '').toString();
  String get _stage => (_booking['delivery_stage'] ?? '').toString();

  bool get _finished {
    final s = _status.toLowerCase();
    return s == 'delivered' || s == 'completed' || s == 'cancelled' || s == 'rejected';
  }

  String get _plainStatus {
    final status = _status;
    final stage = _stage;
    if (status == 'Delivered') return 'Completed';
    if (status == 'Cancelled' || status == 'Rejected') return status;
    if (_pickup) {
      if (stage == 'pickup_started') return 'Driver has arrived for pickup';
      if (stage == 'picked_up') return 'Picked up — going to the garage';
      if (stage == 'out_for_delivery') return 'On the way back to you';
      if (stage == 'delivered') return 'Delivered to you';
    }
    if (status == 'Ready for Pickup') {
      return _pickup ? 'Ready — coming back to you soon' : 'Ready — you can collect it';
    }
    final early = status.isEmpty || status == 'Pending' || status == 'Accepted';
    if (_pickup && stage == 'to_garage' && early) return 'At the garage';
    if (status.isEmpty || status == 'Pending') {
      return _pickup ? 'Booked — pickup is being arranged' : 'Booked — waiting for the garage';
    }
    if (status == 'Accepted') return 'Garage has accepted your booking';
    return status;
  }

  List<String> get _stepLabels => _pickup
      ? const ['Booked', 'Picked up', 'At garage', 'On the way', 'Done']
      : const ['Booked', 'At garage', 'Ready', 'Done'];

  /// Index of the step reached so far in [_stepLabels].
  int get _stepIndex {
    if (_status == 'Delivered' || _stage == 'delivered') return _stepLabels.length - 1;
    if (_pickup) {
      switch (_stage) {
        case 'out_for_delivery':
          return 3;
        case 'to_garage':
          return 2;
        case 'picked_up':
          return 1;
      }
      if (_status == 'Ready for Pickup') return 2;
      return 0;
    }
    if (_status == 'Ready for Pickup') return 2;
    if (_status.isEmpty || _status == 'Pending') return 0;
    return 1;
  }

  static String _formatTime(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final day = sameDay ? 'Today' : '${d.day} ${months[d.month - 1]}';
    return '$day, $h:$m $ampm';
  }

  // ── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceRaised,
        elevation: 0,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: AppColors.txt),
        title: Text(
          'Live updates',
          style: TextStyle(color: AppColors.txt, fontSize: 19, fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar: _buildActionBar(),
      body: loading
          ? _buildSkeleton()
          : _loadError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded, color: AppColors.mut, size: 44),
                        const SizedBox(height: 16),
                        Text(
                          "Couldn't load this booking's updates",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.mut, fontSize: 15),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() => loading = true);
                              fetchUpdates();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('TRY AGAIN',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: _gold,
                  onRefresh: _pullToRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildSummaryCard(),
                              // Inspection report from the garage (shows
                              // nothing when there isn't one).
                              InspectionViewWidget(bookingId: widget.booking['id'].toString()),
                              const SizedBox(height: 22),
                              _buildUpdatesSection(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryCard() {
    final name = (_booking['package_name'] ?? 'Service').toString();
    final price = _booking['package_price']?.toString();
    final steps = _stepLabels;
    final reached = _stepIndex;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: (_finished ? _green : _gold).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _finished ? Icons.check_circle_rounded : Icons.build_rounded,
                  color: _finished ? _green : _gold,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.txt, fontSize: 20, fontWeight: FontWeight.w900, height: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        _formatTime(_booking['created_at']),
                        _pickup ? 'pickup & drop' : 'at the garage',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(color: AppColors.mut, fontSize: 14.5, height: 1.35),
                    ),
                    if (price != null && price.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        price,
                        style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: _finished ? AppColors.mut : _green, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _plainStatus,
                  style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w800, height: 1.3),
                ),
              ),
            ],
          ),
          if (_status != 'Cancelled' && _status != 'Rejected') ...[
            const SizedBox(height: 12),
            Row(
              children: List.generate(steps.length, (i) {
                final done = i <= reached;
                return Expanded(
                  child: Container(
                    height: 7,
                    margin: EdgeInsets.only(right: i == steps.length - 1 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: done ? _green : AppColors.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(steps.length, (i) {
                final done = i <= reached;
                return Expanded(
                  child: Text(
                    steps[i],
                    textAlign: i == 0
                        ? TextAlign.start
                        : (i == steps.length - 1 ? TextAlign.end : TextAlign.center),
                    maxLines: 2,
                    style: TextStyle(
                      color: done ? AppColors.txt : AppColors.mut,
                      fontSize: 12,
                      fontWeight: done ? FontWeight.w800 : FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                );
              }),
            ),
          ],
          BookingSlotBadge(record: _booking),
          // Add-ons the garage asked for (approve & pay / reject), and
          // paid ones as sub-orders — same as on the dashboard card.
          BookingAddons(booking: _booking),
          // Bill (PDF) — appears once the garage marks the job done.
          BillDownloadButton(
            key: ValueKey('bill-bookings-${_booking['id']}-$_status'),
            table: 'bookings',
            id: _booking['id'].toString(),
            topPadding: 14,
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatesSection() {
    final newestFirst = updates.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Updates from the garage',
                style: TextStyle(color: AppColors.txt, fontSize: 21, fontWeight: FontWeight.w900),
              ),
            ),
            if (newestFirst.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  '${newestFirst.length}',
                  style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (newestFirst.isEmpty)
          _buildEmptyUpdates()
        else ...[
          _buildUpdateCard(newestFirst.first as Map, latest: true),
          if (newestFirst.length > 1) ...[
            if (_showOlder)
              ...newestFirst.skip(1).map((u) => _buildUpdateCard(u as Map, latest: false)),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _showOlder = !_showOlder),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.txt,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: Icon(_showOlder ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 24),
                label: Text(
                  _showOlder ? 'Hide earlier updates' : 'See earlier updates (${newestFirst.length - 1})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildEmptyUpdates() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: _gold.withOpacity(0.14), shape: BoxShape.circle),
            child: const Icon(Icons.photo_camera_rounded, color: _gold, size: 30),
          ),
          const SizedBox(height: 12),
          Text(
            'No updates yet',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.txt, fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'The garage will post photos and notes here once work starts. '
            "We'll notify you when they do.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.mut, fontSize: 15, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateCard(Map u, {required bool latest}) {
    final image = (u['image_url'] ?? '').toString();
    final description = (u['description'] ?? '').toString();
    final stage = (u['stage'] ?? 'Update').toString();
    final time = _formatTime(u['created_at']);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: latest ? _gold.withOpacity(0.6) : AppColors.line, width: latest ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stage,
                      style: TextStyle(color: AppColors.txt, fontSize: 19, fontWeight: FontWeight.w900, height: 1.25),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(time, style: TextStyle(color: AppColors.mut, fontSize: 14)),
                    ],
                  ],
                ),
              ),
              if (latest) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(20)),
                  child: const Text(
                    'LATEST',
                    style: TextStyle(color: Colors.black, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                  ),
                ),
              ],
            ],
          ),
          if (image.isNotEmpty) ...[
            const SizedBox(height: 14),
            if (_isVideoPath(image))
              _UpdateVideo(resolve: () => _resolveImageUrl(image))
            else
              _UpdatePhoto(
                future: _resolveImageUrl(image),
                title: stage,
              ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(color: AppColors.txt.withOpacity(0.85), height: 1.5, fontSize: 16),
            ),
          ],
        ],
      ),
    );
  }

  /// Chat and Call, always visible at the bottom.
  Widget _buildActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ElevatedButton.icon(
                          onPressed: openChat,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.txt,
                            foregroundColor: AppColors.ink,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 22),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Chat with garage', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ),
                      if (hasUnreadMessages)
                        Positioned(
                          top: -5,
                          right: -5,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: _red,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.surfaceRaised, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: _call,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.txt,
                    side: BorderSide(color: AppColors.txt.withOpacity(0.3), width: 1.4),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.phone_rounded, size: 22),
                  label: const Text('Call us', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    Widget box(double h, {double r = 14, double? w}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(r)),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        box(170, r: 24),
        const SizedBox(height: 22),
        box(22, w: 200, r: 8),
        const SizedBox(height: 12),
        box(300, r: 24),
      ],
    );
  }
}

/// One update photo: tap to open full screen with pinch-to-zoom.
/// A video the garage sent — a big play tile. Tapping opens the video in the
/// phone's own player (or a new browser tab on the web), which handles
/// full screen, sound and seeking on every platform.
class _UpdateVideo extends StatefulWidget {
  const _UpdateVideo({required this.resolve});

  final Future<String> Function() resolve;

  @override
  State<_UpdateVideo> createState() => _UpdateVideoState();
}

class _UpdateVideoState extends State<_UpdateVideo> {
  bool _opening = false;

  Future<void> _play() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final url = await widget.resolve();
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't play the video. Please try again.")),
        );
      }
    } catch (e) {
      debugPrint('Video open failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't play the video. Please try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _play,
      child: Container(
        height: 190,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF022B57), Color(0xFF0B1A2E)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(color: Color(0xFFFDF003), shape: BoxShape.circle),
              child: _opening
                  ? const Padding(
                      padding: EdgeInsets.all(22),
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF022B57)),
                    )
                  : const Icon(Icons.play_arrow_rounded, color: Color(0xFF022B57), size: 44),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Tap to play video',
                  maxLines: 1,
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdatePhoto extends StatelessWidget {
  const _UpdatePhoto({required this.future, required this.title});

  final Future<String> future;
  final String title;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FutureBuilder<String>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(
                height: 230,
                width: double.infinity,
                color: AppColors.surfaceSunken,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4A017), strokeWidth: 2),
                ),
              );
            }
            final url = snapshot.data!;
            return GestureDetector(
              onTap: () => _openFullScreen(context, url),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: url,
                    // Same photo across re-signed links → reuse the download.
                    cacheKey: Uri.tryParse(url)?.path ?? url,
                    height: 230,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    placeholder: (context, _) => Container(
                      color: AppColors.surfaceSunken,
                      child: const Center(
                        child: CircularProgressIndicator(color: Color(0xFFD4A017), strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, _, __) => Container(
                      color: AppColors.surfaceSunken,
                      child: Icon(Icons.broken_image_rounded, color: AppColors.mut),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('Tap to zoom', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, _, __) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: url,
                cacheKey: Uri.tryParse(url)?.path ?? url,
                fit: BoxFit.contain,
                errorWidget: (context, _, __) =>
                    const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
              ),
            ),
          ),
        ),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED CHAT SHEET — used by both consumer and admin
// ─────────────────────────────────────────────────────────────
class ChatSheet extends StatefulWidget {
  final String bookingId;
  final String sender; // 'consumer' or 'admin'
  final VoidCallback? onMessagesRead;

  const ChatSheet({
    super.key,
    required this.bookingId,
    required this.sender,
    this.onMessagesRead,
  });

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List messages = [];
  bool loading = true;
  bool sending = false;

  // ── Realtime ──
  RealtimeChannel? _chatChannel;
  RealtimeChannel? _typingChannel;

  // ── Typing indicator ──
  bool _otherTyping = false;
  Timer? _typingClearTimer;
  DateTime? _lastTypingSentAt;

  // 🔒 BLOCKING STATE - PERSISTENT
  Set<String> blockedSenders = {};
  bool blockingLoaded = false;
  bool isBlockedByOther = false;

  @override
  void initState() {
    super.initState();
    _fetchBlockingStatus();
    fetchMessages();
    markMessagesRead();
    _subscribeToChatChanges();
    _subscribeToTyping();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _typingClearTimer?.cancel();
    _chatChannel?.unsubscribe();
    _typingChannel?.unsubscribe();
    super.dispose();
  }

  // 🔒 FETCH BLOCKING STATUS
  Future<void> _fetchBlockingStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final otherSender = widget.sender == 'consumer' ? 'admin' : 'consumer';

      // Get users I've blocked
      final myBlocks = await supabase
          .from('blocked_chats')
          .select()
          .eq('booking_id', widget.bookingId)
          .eq('blocked_by', widget.sender);

      // Check if I'm blocked by them
      final theirBlocks = await supabase
          .from('blocked_chats')
          .select()
          .eq('booking_id', widget.bookingId)
          .eq('blocked_by', otherSender)
          .eq('blocked_sender', widget.sender);

      if (mounted) {
        setState(() {
          blockedSenders = Set.from((myBlocks as List).map((b) => b['blocked_sender']));
          isBlockedByOther = (theirBlocks as List).isNotEmpty;
          blockingLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error fetching blocking status: $e');
      if (mounted) {
        setState(() => blockingLoaded = true);
      }
    }
  }

  // ── Live message sync (insert + read-status updates) ──
  void _subscribeToChatChanges() {
    final supabase = Supabase.instance.client;

    _chatChannel = supabase
        .channel('booking_chat_${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'booking_chats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: widget.bookingId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final incoming = payload.newRecord;

            final confirmedIdx = messages.indexWhere(
              (m) => m['id'] != null && m['id'] == incoming['id'],
            );
            if (confirmedIdx != -1) return; // already have the confirmed row

            // If this confirms one of our own not-yet-confirmed optimistic
            // sends (no id yet), replace it instead of adding a duplicate.
            final optimisticIdx = messages.indexWhere(
              (m) =>
                  m['id'] == null &&
                  m['sender'] == incoming['sender'] &&
                  m['message'] == incoming['message'],
            );

            setState(() {
              if (optimisticIdx != -1) {
                messages[optimisticIdx] = incoming;
              } else {
                messages.add(incoming);
              }
            });
            _scrollToBottom();

            // A message just arrived from the other side while the sheet
            // is open — mark it read immediately so they see the seen tick.
            if (incoming['sender'] != widget.sender) {
              markMessagesRead();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'booking_chats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: widget.bookingId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final updated = payload.newRecord;
            final idx = messages.indexWhere((m) => m['id'] == updated['id']);
            if (idx == -1) return;
            setState(() => messages[idx] = updated);
          },
        )
        .subscribe();
  }

  // ── Typing indicator (ephemeral broadcast, not stored in DB) ──
  void _subscribeToTyping() {
    final supabase = Supabase.instance.client;

    _typingChannel = supabase
        .channel('booking_typing_${widget.bookingId}')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            if (!mounted) return;
            if (payload['sender'] == widget.sender) return; // ignore self

            _typingClearTimer?.cancel();
            setState(() => _otherTyping = true);
            _typingClearTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => _otherTyping = false);
            });
          },
        )
        .subscribe();
  }

  void _handleTyping(String _) {
    final now = DateTime.now();
    if (_lastTypingSentAt != null &&
        now.difference(_lastTypingSentAt!) <
            const Duration(milliseconds: 1200)) {
      return; // throttle so we don't flood the channel on every keystroke
    }
    _lastTypingSentAt = now;
    _typingChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'sender': widget.sender},
    );
  }

  Future<void> fetchMessages() async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('booking_chats')
          .select()
          .eq('booking_id', widget.bookingId)
          .order('created_at', ascending: true);

      if (!mounted) return;

      setState(() {
        messages = response;
        loading = false;
      });

      _scrollToBottom();
    } catch (e) {
      // Without this, a failed fetch left `loading` stuck true forever —
      // an unrecoverable spinner in the chat sheet with no way out.
      if (!mounted) return;
      setState(() => loading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not load messages. Please try again.',
      );
    }
  }

  Future<void> markMessagesRead() async {
    final supabase = Supabase.instance.client;

    final otherSender =
        widget.sender == 'consumer' ? 'admin' : 'consumer';

    final readField = widget.sender == 'consumer'
        ? 'is_read_by_consumer'
        : 'is_read_by_admin';

    try {
      await supabase
          .from('booking_chats')
          .update({readField: true})
          .eq('booking_id', widget.bookingId)
          .eq('sender', otherSender);

      widget.onMessagesRead?.call();
    } catch (e) {
      // Non-fatal — worst case the "seen" tick / unread badge lags.
      debugPrint('Error marking messages read: $e');
    }
  }

  Future<void> sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // 🔒 CHECK BLOCKING
    if (isBlockedByOther) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot send messages - you have been blocked'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => sending = true);
    _controller.clear();

    final supabase = Supabase.instance.client;

    // Show it immediately rather than waiting on the round trip.
    final optimisticMsg = {
      'booking_id': widget.bookingId,
      'message': text,
      'sender': widget.sender,
      'is_read_by_admin': widget.sender == 'admin',
      'is_read_by_consumer': widget.sender == 'consumer',
    };
    setState(() => messages.add(optimisticMsg));
    _scrollToBottom();

    try {
      final inserted = await supabase
          .from('booking_chats')
          .insert(optimisticMsg)
          .select()
          .single();

      if (mounted) {
        final idx = messages.indexOf(optimisticMsg);
        if (idx != -1) {
          setState(() => messages[idx] = inserted);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => messages.remove(optimisticMsg));
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not send this message. Please try again.',
        );
      }
    }

    if (mounted) setState(() => sending = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75 + bottomPadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // ── Handle ──
          Container(
            margin: const EdgeInsets.only(top: 14, bottom: 10),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.txt.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // ── Title ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_rounded,
                        color: Color(0xFFD4A017),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Garage Chat',
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                // 🔒 SAFETY MENU
                if (blockingLoaded)
                  IconButton(
                    icon: Icon(Icons.more_vert, color: AppColors.mut),
                    onPressed: () {
                      final otherSender = widget.sender == 'consumer' ? 'admin' : 'consumer';
                      _showSafetyMenu(otherSender);
                    },
                  ),
              ],
            ),
          ),

          Divider(color: AppColors.line, height: 1),

          // ── Messages ──
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFFD4A017)),
                  )
                : isBlockedByOther
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.block, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              'You are blocked',
                              style: TextStyle(
                                color: AppColors.txt,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You cannot send or receive messages from this user',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.mut,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : messages.isEmpty
                        ? Center(
                            child: Text(
                              'No messages yet.\nSend the first one!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColors.mut, fontSize: 15, height: 1.6),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final msg = messages[index];
                              final senderKey = msg['sender'] ?? 'unknown';
                              final isBlocked = blockedSenders.contains(senderKey);

                              // 🔒 SKIP blocked messages
                              if (isBlocked) return const SizedBox.shrink();

                              final isMe = msg['sender'] == widget.sender;

                          // Has the OTHER party read this message of mine?
                          final seen = widget.sender == 'consumer'
                              ? msg['is_read_by_admin'] == true
                              : msg['is_read_by_consumer'] == true;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(bottom: 2),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width *
                                        0.72,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? const Color(0xFFD4A017)
                                        : AppColors.surfaceRaised,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft:
                                          Radius.circular(isMe ? 18 : 4),
                                      bottomRight:
                                          Radius.circular(isMe ? 4 : 18),
                                    ),
                                  ),
                                  child: Text(
                                    msg['message'],
                                    style: TextStyle(
                                      color: isMe ? AppColors.onAccentDark : AppColors.txt,
                                      fontSize: 15,
                                      fontWeight: isMe
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isMe)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10, right: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          seen
                                              ? Icons.remove_red_eye
                                              : Icons.remove_red_eye_outlined,
                                          size: 12,
                                          color: seen
                                              ? const Color(0xFFD4A017)
                                              : AppColors.mut,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          seen ? 'Seen' : 'Sent',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: seen
                                                ? const Color(0xFFD4A017)
                                                : AppColors.mut,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  const SizedBox(height: 10),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // ── Typing indicator ──
          if (_otherTyping)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFFD4A017),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.sender == 'consumer'
                        ? 'Garage is typing…'
                        : 'Customer is typing…',
                    style: TextStyle(
                      color: AppColors.mut,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          // ── Input ──
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPadding),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _handleTyping,
                    enabled: !isBlockedByOther && blockingLoaded,
                    style: TextStyle(color: AppColors.txt),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: isBlockedByOther ? 'You are blocked' : 'Type a message...',
                      hintStyle:
                          TextStyle(color: AppColors.mut),
                      filled: true,
                      fillColor: isBlockedByOther
                          ? const Color(0xFF2A1A1A)
                          : AppColors.surfaceSunken,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: sending ? null : sendMessage,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: sending
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              color: AppColors.onAccentDark,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: AppColors.onAccentDark,
                            size: 22,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🔒 SHOW SAFETY MENU
  void _showSafetyMenu(String otherSender) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.txt.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text(
                'Block',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _blockUser(otherSender);
              },
            ),
            if (blockedSenders.contains(otherSender))
              ListTile(
                leading: const Icon(Icons.person_add, color: Colors.green),
                title: const Text(
                  'Unblock',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _unblockUser(otherSender);
                },
              ),
            ListTile(
              leading: const Icon(Icons.flag, color: Colors.orange),
              title: const Text(
                'Report',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog(otherSender);
              },
            ),
            ListTile(
              title: Text('Cancel', style: TextStyle(color: AppColors.mut)),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // 🔒 BLOCK USER
  Future<void> _blockUser(String sender) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase.from('blocked_chats').insert({
        'booking_id': widget.bookingId,
        'blocked_by': widget.sender,
        'blocked_sender': sender,
      });

      if (mounted) {
        setState(() => blockedSenders.add(sender));
        // showPremiumToast, not a plain SnackBar — this chat is a modal
        // bottom sheet with no Scaffold of its own, so a SnackBar attaches
        // to the screen underneath and renders hidden behind the sheet.
        ErrorDisplay.showPremiumToast(
          context,
          message: 'Blocked $sender',
          icon: Icons.block_rounded,
          accent: Colors.red.shade400,
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not block this user. Please try again.',
        );
      }
    }
  }

  // 🔒 UNBLOCK USER
  Future<void> _unblockUser(String sender) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase
          .from('blocked_chats')
          .delete()
          .eq('booking_id', widget.bookingId)
          .eq('blocked_by', widget.sender)
          .eq('blocked_sender', sender);

      if (mounted) {
        setState(() => blockedSenders.remove(sender));
        ErrorDisplay.showPremiumToast(
          context,
          message: 'User unblocked',
          icon: Icons.check_circle_rounded,
          accent: Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not unblock this user. Please try again.',
        );
      }
    }
  }

  // 🔒 SHOW REPORT DIALOG
  void _showReportDialog(String sender) {
    final reasons = ['Offensive language', 'Spam', 'Inappropriate', 'Other'];
    String? selectedReason;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Report User',
          style: TextStyle(
            color: AppColors.txt,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: reasons
              .map((reason) => RadioListTile<String>(
                title: Text(
                  reason,
                  style: TextStyle(
                    color: AppColors.txt,
                    fontSize: 15,
                  ),
                ),
                value: reason,
                groupValue: selectedReason,
                activeColor: const Color(0xFFD4A017),
                onChanged: (value) {
                  Navigator.pop(context);
                  selectedReason = value;
                  if (selectedReason != null) {
                    _submitReport(sender, selectedReason!);
                  }
                },
              ))
              .toList(),
        ),
      ),
    );
  }

  // 🔒 SUBMIT REPORT
  Future<void> _submitReport(String sender, String reason) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase.from('chat_reports').insert({
        'booking_id': widget.bookingId,
        'reported_sender': sender,
        'report_reason': reason,
        'reporter': widget.sender,
        'report_type': 'booking',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ErrorDisplay.showPremiumToast(
          context,
          message: 'Report submitted. Thank you!',
          icon: Icons.flag_rounded,
          accent: Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not submit this report. Please try again.',
        );
      }
    }
  }
}
