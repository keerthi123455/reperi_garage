import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';
import '../services/booking_api.dart';
import '../theme/fleet_theme.dart';
import '../theme/garage_theme.dart' show G, GaragePlate;
import '../widgets/error_display.dart';

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
    with TickerProviderStateMixin, FleetThemeListener {
  static const _signedUrlExpirySeconds = 300;

  // ── Approval state ──
  late String? _approvalState;
  bool _isSubmitting = false;

  // ── Unread chat badge ──
  bool _hasUnreadChat = false;
  RealtimeChannel? _requestWatchChannel;

  // ── Chat state ──
  final _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  List<Map<String, dynamic>> _chatMessages = [];
  bool _chatLoading = false;
  bool _chatSending = false;
  RealtimeChannel? _chatChannel;

  // ── Typing indicator ──
  RealtimeChannel? _typingChannel;
  bool _otherTyping = false;
  Timer? _typingClearTimer;
  DateTime? _lastTypingSentAt;

  // ── Sheet setState handle ──
  StateSetter? _sheetSetState;

  // 🔒 BLOCKING STATE - PERSISTENT
  Set<String> blockedSenders = {};
  bool blockingLoaded = false;
  bool isBlockedByOther = false;

  // ── Animation controllers ──
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  /// booking-images is a private bucket — `storedValue` is normally just the
  /// storage path (see fleet_order_sheet.dart / fleet_request_details_screen
  /// .dart), but older rows may still hold a full public URL from before the
  /// bucket was made private, so both are handled here.
  Future<String> _resolveImageUrl(String storedValue) async {
    final path = storedValue.contains('/booking-images/')
        ? storedValue.split('/booking-images/').last
        : storedValue;
    return Supabase.instance.client.storage
        .from('booking-images')
        .createSignedUrl(path, _signedUrlExpirySeconds);
  }

  @override
  void initState() {
    super.initState();

    _approvalState = widget.request['customer_approval'] as String?;
    if (widget.request['has_unread_update'] == true) {
      _approvalState = null;
    }

    _hasUnreadChat = widget.request['fleet_has_unread_chat'] == true;

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim =
        CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut);
    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    if (_approvalState != null) {
      _scaleController.value = 1.0;
      _fadeController.value = 1.0;
    }

    Future.microtask(() async {
      if (widget.request['has_unread_update'] == true) {
        try {
          await Supabase.instance.client
              .from('fleet_pickup_requests')
              .update({'has_unread_update': false}).eq('id', widget.request['id']);
        } catch (_) {
          // Non-fatal — worst case the unread badge stays lit one extra visit.
        }
      }
    });

    _watchRequestForUnreadChat();
    _fetchFleetBlockingStatus();
    _refreshLive();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatChannel?.unsubscribe();
    _typingChannel?.unsubscribe();
    _typingClearTimer?.cancel();
    _requestWatchChannel?.unsubscribe();
    super.dispose();
  }

  // ── Live badge: watch this request row for fleet_has_unread_chat changes ──

  void _watchRequestForUnreadChat() {
    _requestWatchChannel = Supabase.instance.client
        .channel('fleet_request_view_watch_${widget.request['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'fleet_pickup_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.request['id'],
          ),
          callback: (payload) {
            if (!mounted) return;
            final updated = payload.newRecord;
            final unread = updated['fleet_has_unread_chat'] == true;
            if (unread != _hasUnreadChat) {
              setState(() => _hasUnreadChat = unread);
            }
          },
        )
        .subscribe();
  }

  // ── Call garage ──

  Future<void> _callGarage() async {
    final uri = Uri.parse('tel:9353094672');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch dialler'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔒 FETCH BLOCKING STATUS FOR FLEET
  Future<void> _fetchFleetBlockingStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final requestId = widget.request['id'].toString();

      // Get users I've blocked
      final myBlocks = await supabase
          .from('blocked_fleet_chats')
          .select()
          .eq('request_id', requestId)
          .eq('blocked_by', 'fleet');

      // Check if I'm blocked by admin
      final theirBlocks = await supabase
          .from('blocked_fleet_chats')
          .select()
          .eq('request_id', requestId)
          .eq('blocked_by', 'admin')
          .eq('blocked_sender', 'fleet');

      if (mounted) {
        setState(() {
          blockedSenders = Set.from((myBlocks as List).map((b) => b['blocked_sender']));
          isBlockedByOther = (theirBlocks as List).isNotEmpty;
          blockingLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error fetching fleet blocking status: $e');
      if (mounted) {
        setState(() => blockingLoaded = true);
      }
    }
  }

  // ── Chat helpers ──

  Future<void> _loadChatMessages() async {
    _sheetSetState?.call(() => _chatLoading = true);
    try {
      final rows = await Supabase.instance.client
          .from('fleet_chat_messages')
          .select()
          .eq('request_id', widget.request['id'].toString())
          .order('created_at', ascending: true);
      if (mounted) {
        _chatMessages = List<Map<String, dynamic>>.from(rows);
        _sheetSetState?.call(() {});
        _scrollChatToBottom();
        _markAdminMessagesReadByFleet();
      }
    } catch (_) {}
    if (mounted) {
      _sheetSetState?.call(() => _chatLoading = false);
    }
  }

  Future<void> _markAdminMessagesReadByFleet() async {
    try {
      await Supabase.instance.client
          .from('fleet_chat_messages')
          .update({'is_read_by_fleet': true})
          .eq('request_id', widget.request['id'].toString())
          .eq('sender_type', 'admin')
          .eq('is_read_by_fleet', false);
    } catch (_) {}
  }

  void _subscribeToChat() {
    _chatChannel = Supabase.instance.client
        .channel('fleet_chat_view_${widget.request['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'fleet_chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'request_id',
            value: widget.request['id'],
          ),
          callback: (payload) {
            if (!mounted) return;
            final incoming = payload.newRecord;

            final confirmedIdx = _chatMessages.indexWhere(
              (m) => m['id'] != null && m['id'] == incoming['id'],
            );
            if (confirmedIdx != -1) return;

            final optimisticIdx = _chatMessages.indexWhere(
              (m) =>
                  m['id'] == null &&
                  m['sender_type'] == incoming['sender_type'] &&
                  m['message'] == incoming['message'],
            );

            if (optimisticIdx != -1) {
              _chatMessages[optimisticIdx] = incoming;
            } else {
              _chatMessages.add(incoming);
            }
            _sheetSetState?.call(() {});
            _scrollChatToBottom();

            if (incoming['sender_type'] == 'admin') {
              _markAdminMessagesReadByFleet();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'fleet_chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'request_id',
            value: widget.request['id'],
          ),
          callback: (payload) {
            if (!mounted) return;
            final updated = payload.newRecord;
            final idx =
                _chatMessages.indexWhere((m) => m['id'] == updated['id']);
            if (idx == -1) return;
            _chatMessages[idx] = updated;
            _sheetSetState?.call(() {});
          },
        )
        .subscribe();
  }

  // ── Typing indicator (ephemeral broadcast, not stored in DB) ──
  void _subscribeToTyping() {
    _typingChannel = Supabase.instance.client
        .channel('fleet_typing_view_${widget.request['id']}')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            if (!mounted) return;
            if (payload['sender'] == 'fleet') return; // ignore self

            _typingClearTimer?.cancel();
            _otherTyping = true;
            _sheetSetState?.call(() {});
            _typingClearTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                _otherTyping = false;
                _sheetSetState?.call(() {});
              }
            });
          },
        )
        .subscribe();
  }

  void _handleChatTyping(String _) {
    final now = DateTime.now();
    if (_lastTypingSentAt != null &&
        now.difference(_lastTypingSentAt!) <
            const Duration(milliseconds: 1200)) {
      return;
    }
    _lastTypingSentAt = now;
    _typingChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'sender': 'fleet'},
    );
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _chatSending) return;

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

    _chatController.clear();

    final optimisticMsg = {
      'request_id': widget.request['id'].toString(),
      'sender_type': 'fleet',
      'sender_name': widget.request['company_name'] ?? 'Fleet Operator',
      'message': text,
      'created_at': DateTime.now().toIso8601String(),
      'is_read_by_fleet': true,
      'is_read_by_admin': false,
    };

    _sheetSetState?.call(() {
      _chatSending = true;
      _chatMessages.add(optimisticMsg);
    });

    _scrollChatToBottom();

    try {
      final inserted = await Supabase.instance.client
          .from('fleet_chat_messages')
          .insert({
            'request_id': widget.request['id'].toString(),
            'sender_type': 'fleet',
            'sender_name': widget.request['company_name'] ?? 'Fleet Operator',
            'message': text,
            'is_read_by_fleet': true,
            'is_read_by_admin': false,
          })
          .select()
          .single();

      final idx = _chatMessages.indexOf(optimisticMsg);
      if (idx != -1) {
        _sheetSetState?.call(() => _chatMessages[idx] = inserted);
      }

      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({'admin_has_unread_chat': true})
          .eq('id', widget.request['id']);
    } catch (e) {
      _sheetSetState?.call(() => _chatMessages.remove(optimisticMsg));
      if (mounted) {
        ErrorDisplay.showPremiumError(
          context,
          error: e,
          customMessage: 'Could not send this message. Please try again.',
        );
      }
    }

    if (mounted) {
      _sheetSetState?.call(() => _chatSending = false);
    }
  }

  void _openChatPopup() {
    // Clear fleet's unread flag locally and in DB
    setState(() => _hasUnreadChat = false);
    () async {
      try {
        await Supabase.instance.client
            .from('fleet_pickup_requests')
            .update({'fleet_has_unread_chat': false}).eq('id', widget.request['id']);
      } catch (_) {
        // Non-fatal — worst case the unread badge stays lit one extra visit.
      }
    }();

    // Reset chat state before opening
    _chatMessages = [];
    _chatLoading = true;
    _otherTyping = false;
    _sheetSetState = null;

    _subscribeToChat();
    _subscribeToTyping();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSheetState) {
          _sheetSetState = setSheetState;
          return _buildChatSheet(sheetCtx);
        },
      ),
    ).then((_) {
      _sheetSetState = null;
      _chatChannel?.unsubscribe();
      _chatChannel = null;
      _typingChannel?.unsubscribe();
      _typingChannel = null;
      _typingClearTimer?.cancel();
    });

    // Load after sheet is open so spinner shows, then updates via _sheetSetState
    _loadChatMessages();
  }

  Widget _buildChatSheet(BuildContext sheetCtx) {
    final viewInsets = MediaQuery.of(sheetCtx).viewInsets;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        height: MediaQuery.of(sheetCtx).size.height * 0.75 + viewInsets.bottom,
        decoration: BoxDecoration(
          color: F.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: F.line, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(color: F.yellow, shape: BoxShape.circle),
                    child: const Icon(Icons.support_agent_rounded, color: F.navy, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Garage team',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: F.txt, fontWeight: FontWeight.w900, fontSize: 18)),
                        Text('Replies show up here instantly',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: F.mut, fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  // 🔒 MENU & CLOSE BUTTONS
                  if (blockingLoaded)
                    IconButton(
                      tooltip: 'Block or report',
                      icon: Icon(Icons.more_vert_rounded, color: F.mut),
                      onPressed: _showFleetSafetyMenu,
                    ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: F.mut),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
            ),
            Divider(color: F.line, height: 22),
            Expanded(
              child: _chatLoading
                  ? Center(child: CircularProgressIndicator(color: F.accent, strokeWidth: 2.4))
                  : isBlockedByOther
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.block_rounded, color: F.red, size: 52),
                                const SizedBox(height: 14),
                                Text('You are blocked',
                                    style: TextStyle(color: F.txt, fontSize: 19, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 6),
                                Text('You cannot send or receive messages',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: F.mut, fontSize: 15.5)),
                              ],
                            ),
                          ),
                        )
                      : _chatMessages.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.forum_rounded, color: F.faint, size: 48),
                                    const SizedBox(height: 10),
                                    Text('No messages yet',
                                        style: TextStyle(color: F.txt, fontSize: 17, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    Text('Ask the garage anything about this vehicle.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: F.mut, fontSize: 15)),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _chatScrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: _chatMessages.length,
                              itemBuilder: (_, i) {
                                final msg = _chatMessages[i];
                                final senderKey = msg['sender_type'] ?? 'unknown';
                                final isBlocked = blockedSenders.contains(senderKey);

                                // 🔒 SKIP blocked messages
                                if (isBlocked) return const SizedBox.shrink();

                                final isFleet = msg['sender_type'] == 'fleet';
                                final seen = isFleet ? msg['is_read_by_admin'] == true : msg['is_read_by_fleet'] == true;
                                return _chatBubble(msg['message'] ?? '', isFleet, seen);
                              },
                            ),
            ),
            if (_otherTyping)
              Padding(
                padding: const EdgeInsets.only(left: 18, bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: F.accent),
                    ),
                    const SizedBox(width: 8),
                    Text('Garage team is typing…',
                        style: TextStyle(color: F.mut, fontSize: 14, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + viewInsets.bottom),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      onChanged: _handleChatTyping,
                      enabled: !isBlockedByOther && blockingLoaded,
                      style: TextStyle(color: F.txt, fontSize: 17),
                      cursorColor: F.accent,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendChatMessage(),
                      decoration: F.input(isBlockedByOther ? 'You are blocked' : 'Type a message…').copyWith(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: F.yellow,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _sendChatMessage,
                      child: SizedBox(
                        width: 54,
                        height: 54,
                        child: _chatSending
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(color: F.navy, strokeWidth: 2.4),
                              )
                            : const Icon(Icons.send_rounded, color: F.navy, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatBubble(String message, bool isFleet, bool seen) {
    return Align(
      alignment: isFleet ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isFleet ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isFleet ? F.navy : F.card,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isFleet ? 18 : 4),
                bottomRight: Radius.circular(isFleet ? 4 : 18),
              ),
              border: isFleet ? null : Border.all(color: F.line),
            ),
            child: Text(
              message,
              style: TextStyle(color: isFleet ? Colors.white : F.txt, fontSize: 16, height: 1.35),
            ),
          ),
          if (isFleet)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(seen ? Icons.done_all_rounded : Icons.done_rounded, size: 15, color: seen ? F.blue : F.faint),
                  const SizedBox(width: 4),
                  Text(seen ? 'Seen' : 'Sent',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: seen ? F.blue : F.faint)),
                ],
              ),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ── Approval ──

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
          }).eq('id', widget.request['id']);

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
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not submit your decision. Please try again.',
      );
    }
  }

  // 🔒 SHOW FLEET SAFETY MENU
  void _showFleetSafetyMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: F.card,
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
                color: F.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text(
                'Block Admin',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _blockFleetUser('admin');
              },
            ),
            if (blockedSenders.contains('admin'))
              ListTile(
                leading: const Icon(Icons.person_add, color: Colors.green),
                title: const Text(
                  'Unblock Admin',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _unblockFleetUser('admin');
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
                _showFleetReportDialog();
              },
            ),
            ListTile(
              title: Text('Cancel', style: TextStyle(color: F.mut, fontWeight: FontWeight.w700, fontSize: 16)),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // 🔒 BLOCK FLEET USER
  Future<void> _blockFleetUser(String sender) async {
    try {
      final supabase = Supabase.instance.client;
      final requestId = widget.request['id'].toString();

      await supabase.from('blocked_fleet_chats').insert({
        'request_id': requestId,
        'blocked_by': 'fleet',
        'blocked_sender': sender,
      });

      if (mounted) {
        setState(() => blockedSenders.add(sender));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blocked $sender'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 2),
          ),
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

  // 🔒 UNBLOCK FLEET USER
  Future<void> _unblockFleetUser(String sender) async {
    try {
      final supabase = Supabase.instance.client;
      final requestId = widget.request['id'].toString();

      await supabase
          .from('blocked_fleet_chats')
          .delete()
          .eq('request_id', requestId)
          .eq('blocked_by', 'fleet')
          .eq('blocked_sender', sender);

      if (mounted) {
        setState(() => blockedSenders.remove(sender));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin unblocked'),
            duration: Duration(seconds: 2),
          ),
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

  // 🔒 SHOW FLEET REPORT DIALOG
  void _showFleetReportDialog() {
    final reasons = ['Offensive language', 'Spam', 'Inappropriate', 'Other'];
    String? selectedReason;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: F.card,
        surfaceTintColor: F.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Report Admin',
          style: TextStyle(
            color: F.txt,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: reasons
              .map((reason) => RadioListTile<String>(
                title: Text(
                  reason,
                  style: TextStyle(
                    color: F.txt,
                    fontSize: 16,
                  ),
                ),
                value: reason,
                groupValue: selectedReason,
                activeColor: F.accent,
                onChanged: (value) {
                  Navigator.pop(context);
                  selectedReason = value;
                  if (selectedReason != null) {
                    _submitFleetReport(selectedReason!);
                  }
                },
              ))
              .toList(),
        ),
      ),
    );
  }

  // 🔒 SUBMIT FLEET REPORT
  Future<void> _submitFleetReport(String reason) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase.from('chat_reports').insert({
        'request_id': widget.request['id'].toString(),
        'reported_sender': 'admin',
        'report_reason': reason,
        'reporter': 'fleet',
        'report_type': 'fleet',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. Thank you!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
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

  @override
  Widget build(BuildContext context) {
    final req = widget.request;

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

    final step = F.stepOf(req['status']?.toString());
    // Refreshed after paying (see _refreshLive), so the bill and the report
    // unlock without leaving this screen.
    final awaitingPay = _v('payment_status') == 'awaiting_payment';
    final paid = _v('payment_status') == 'paid';
    final adminComment = (req['admin_comment'] ?? '').toString().trim();
    // The garage has sent something to approve → approval goes to the top.
    final approvalOnTop = adminComment.isNotEmpty || req['admin_photo_url'] != null;
    final model = (req['vehicle_model'] ?? '').toString().trim();
    final (stepFg, stepBg) = F.stepColors(step);
    final requested = G.when(req['created_at']);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: F.bg,
        bottomNavigationBar: _bottomBar(),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Row(
                      children: [
                        FleetIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Request details',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: F.txt, fontSize: 21, fontWeight: FontWeight.w900)),
                        ),
                        const FleetThemeButton(),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        // ── Vehicle ──
                        GaragePlate(req['car_number']?.toString(), fontSize: 28),
                        const SizedBox(height: 10),
                        Text(model.isEmpty ? 'Vehicle' : model,
                            style: TextStyle(color: F.txt, fontSize: 24, fontWeight: FontWeight.w900, height: 1.2)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FleetPill(F.statusLabel(req['status']?.toString()), fg: stepFg, bg: stepBg),
                            if (requested.isNotEmpty)
                              Text('Requested $requested',
                                  style: TextStyle(color: F.mut, fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),

                        // ── What needs you ──
                        if (awaitingPay) ...[
                          const SizedBox(height: 16),
                          _billCard(req, toPay: true),
                        ],
                        if (approvalOnTop) ...[
                          const SizedBox(height: 16),
                          _approvalCard(adminComment, urgent: _approvalState == null),
                        ],

                        // ── 21-point inspection report ──
                        if (widget.request['delivery_partner_id'] != null || _v('inspection21_status') != null) ...[
                          const SizedBox(height: 16),
                          _inspectionReportCard(),
                        ],

                        // ── Progress ──
                        _section('PROGRESS'),
                        _timeline(step, requested),
                        if (statuses.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _historyCard(statuses),
                        ],

                        // ── Garage updates ──
                        _section('UPDATE FROM THE GARAGE'),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: F.box(),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.campaign_rounded, color: F.accent, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  adminComment.isEmpty ? 'No updates yet. We\'ll post here as work moves along.' : adminComment,
                                  style: TextStyle(
                                    color: adminComment.isEmpty ? F.mut : F.txt,
                                    fontSize: 17,
                                    height: 1.45,
                                    fontWeight: adminComment.isEmpty ? FontWeight.w600 : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (comments.length > 1) ...[
                          const SizedBox(height: 10),
                          Text('Earlier updates',
                              style: TextStyle(color: F.mut, fontSize: 14.5, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          for (final c in comments.reversed.skip(1))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: F.sunken, borderRadius: BorderRadius.circular(14)),
                                child: Text(c, style: TextStyle(color: F.mut, fontSize: 15.5, height: 1.4)),
                              ),
                            ),
                        ],

                        // ── Photos ──
                        _section('PHOTOS FROM THE GARAGE'),
                        if (req['admin_photo_url'] == null && photos.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: F.box(),
                            child: Row(
                              children: [
                                Icon(Icons.photo_outlined, color: F.faint, size: 24),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text('No photos yet.',
                                      style: TextStyle(color: F.mut, fontSize: 16, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          if (req['admin_photo_url'] != null) _photo(req['admin_photo_url'].toString(), label: 'LATEST'),
                          for (var i = 0; i < photos.length; i++)
                            if (photos[i] != req['admin_photo_url']?.toString())
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _photo(photos[i], label: 'PHOTO ${i + 1}'),
                              ),
                        ],

                        // ── Bill (paid) ──
                        if (paid) ...[
                          _section('SERVICE BILL'),
                          _billCard(req, toPay: false),
                        ],

                        // ── Approval (nothing sent yet) ──
                        if (!approvalOnTop) ...[
                          _section('WORK APPROVAL'),
                          _approvalCard(adminComment, urgent: false),
                        ],

                        // ── Your photo ──
                        if (req['vehicle_photo_url'] != null) ...[
                          _section('YOUR PHOTO OF THE VEHICLE'),
                          _photo(req['vehicle_photo_url'].toString()),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 21-point inspection report ──────────────────────────────────────
  // Made from the 21 photos the pickup partner takes (fleet-inspection
  // function). The fleet can download it once the bill is paid.
  Map<String, dynamic>? _live; // latest payment / report state of this request
  bool _reportOpening = false;

  Future<void> _refreshLive() async {
    try {
      final row = await Supabase.instance.client
          .from('fleet_pickup_requests')
          .select('payment_status, inspection21_status, inspection21_summary, delivery_partner_id')
          .eq('id', widget.request['id'])
          .maybeSingle();
      if (mounted && row != null) setState(() => _live = Map<String, dynamic>.from(row));
    } catch (_) {
      // Keep what we have.
    }
  }

  dynamic _v(String k) => _live != null && _live!.containsKey(k) ? _live![k] : widget.request[k];

  Future<void> _downloadReport() async {
    if (_reportOpening) return;
    setState(() => _reportOpening = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('fleet-inspection', body: {
        'action': 'download',
        'id': '${widget.request['id']}',
        'fleet_user_id': '${widget.request['fleet_user_id'] ?? ''}',
      });
      final url = (res.data is Map ? res.data['url'] : null)?.toString();
      if (url == null || url.isEmpty) throw 'no link';
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open the report. Please try again.")));
      }
    } on FunctionException catch (e) {
      final msg = e.details is Map ? (e.details['message'] ?? '').toString() : '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.isNotEmpty ? msg : "Couldn't open the report. Please try again.")),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open the report. Please try again.")));
      }
    } finally {
      if (mounted) setState(() => _reportOpening = false);
    }
  }

  /// Shown only for pickups done by a Reperi delivery partner.
  Widget _inspectionReportCard() {
    final status = (_v('inspection21_status') ?? '').toString();
    final paid = _v('payment_status') == 'paid';
    final summary = _v('inspection21_summary') is Map ? Map<String, dynamic>.from(_v('inspection21_summary') as Map) : null;
    final ready = status == 'ready';

    Widget chip(String n, String label, Color fg, Color bg) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(n, maxLines: 1, style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w900)),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        );

    final String sub;
    if (ready && paid) {
      sub = 'Photos of every side of the vehicle at pickup, checked for scratches, dents and cracks.';
    } else if (ready) {
      sub = 'Ready — available to download once the service bill is paid.';
    } else if (status == 'processing' || status == 'failed') {
      sub = "Our pickup partner has taken the 21 photos. We're preparing your report.";
    } else {
      sub = 'Our pickup partner takes 21 photos of the vehicle at pickup. Your report is made from them.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ready && paid ? F.box(border: F.dark ? F.yellow : F.navy, width: 2) : F.box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_rounded, color: F.accent, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text('21-point inspection report',
                    style: TextStyle(color: F.txt, fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(sub, style: TextStyle(color: F.mut, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
          if (ready && paid && summary != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                chip('${summary['ok'] ?? 0}', 'No damage', F.green, F.greenBg),
                const SizedBox(width: 8),
                chip('${summary['minor'] ?? 0}', 'Minor', F.amber, F.amberBg),
                const SizedBox(width: 8),
                chip('${summary['major'] ?? 0}', 'Major', F.red, F.redBg),
              ],
            ),
          ],
          if (ready) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: paid
                  ? ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: F.yellow,
                        foregroundColor: F.navy,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _reportOpening ? null : _downloadReport,
                      icon: _reportOpening
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: F.navy))
                          : const Icon(Icons.download_rounded, size: 22),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('DOWNLOAD REPORT (PDF)',
                            maxLines: 1, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: F.sunken,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: F.line, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('🔒 Unlocks after payment',
                              maxLines: 1, style: TextStyle(color: F.mut, fontSize: 17, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(t, style: TextStyle(color: F.mut, fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
      );

  /// Call garage + Chat, always at the bottom.
  Widget _bottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: F.card,
        border: Border(top: BorderSide(color: F.line)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: F.yellow,
                          foregroundColor: F.navy,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.call_rounded, size: 22),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Call garage', maxLines: 1, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                        ),
                        onPressed: _callGarage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: F.accent,
                              side: BorderSide(color: F.accent, width: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.chat_bubble_rounded, size: 21),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Chat', maxLines: 1, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                            ),
                            onPressed: _openChatPopup,
                          ),
                        ),
                        if (_hasUnreadChat)
                          Positioned(
                            top: -7,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: F.redSolid,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: F.card, width: 2),
                              ),
                              child: const Text('NEW',
                                  style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Requested → Picked up → In garage → Done.
  Widget _timeline(int step, String requested) {
    const subs = ['We have your request', 'On the way to the garage', 'Inspection and work', 'Vehicle returned'];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: F.box(),
      child: Column(
        children: [
          for (var i = 0; i < F.steps.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < step || (i == step && step == 3)
                            ? F.greenSolid
                            : (i == step ? F.yellow : F.line),
                      ),
                      alignment: Alignment.center,
                      child: i < step || (i == step && step == 3)
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                          : Text('${i + 1}',
                              style: TextStyle(
                                color: i == step ? F.navy : F.mut,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              )),
                    ),
                    if (i < F.steps.length - 1)
                      Container(width: 2.5, height: 26, color: i < step ? F.greenSolid : F.line),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3, bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(F.steps[i],
                            style: TextStyle(
                              color: i <= step ? F.txt : F.mut,
                              fontSize: 17,
                              fontWeight: i == step ? FontWeight.w900 : FontWeight.w700,
                            )),
                        Text(
                          i == 0 && requested.isNotEmpty ? requested : (i == step && step < 3 ? 'Now · ${subs[i]}' : subs[i]),
                          style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _historyCard(List<String> statuses) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: F.box(),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          iconColor: F.accent,
          collapsedIconColor: F.mut,
          title: Text('Status history (${statuses.length})',
              style: TextStyle(color: F.txt, fontSize: 16, fontWeight: FontWeight.w800)),
          children: [
            for (var i = statuses.length - 1; i >= 0; i--)
              ListTile(
                dense: true,
                leading: Icon(i == statuses.length - 1 ? Icons.radio_button_checked_rounded : Icons.check_circle_rounded,
                    color: i == statuses.length - 1 ? F.accent : F.faint, size: 20),
                title: Text(statuses[i],
                    style: TextStyle(
                      color: i == statuses.length - 1 ? F.txt : F.mut,
                      fontSize: 15.5,
                      fontWeight: i == statuses.length - 1 ? FontWeight.w800 : FontWeight.w600,
                    )),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _photo(String stored, {String? label}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: FutureBuilder<String>(
        future: _resolveImageUrl(stored),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Container(
              height: 220,
              width: double.infinity,
              color: F.sunken,
              child: Center(child: CircularProgressIndicator(color: F.accent, strokeWidth: 2.4)),
            );
          }
          final url = snapshot.data!;
          return GestureDetector(
            onTap: () => _openPhoto(url),
            child: Stack(
              children: [
                Image.network(
                  url,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 220,
                    color: F.sunken,
                    child: Center(child: Icon(Icons.broken_image_rounded, color: F.faint, size: 40)),
                  ),
                ),
                if (label != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.62), borderRadius: BorderRadius.circular(10)),
                      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(20)),
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
    );
  }

  void _openPhoto(String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, _, __) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(child: Image.network(url, fit: BoxFit.contain)),
          ),
        ),
        transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  String _rupees(dynamic v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null) return '₹${v ?? ''}';
    final s = n.round().toString();
    if (s.length <= 3) return '₹$s';
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '₹${parts.join(',')},$last3';
  }

  Widget _billCard(Map req, {required bool toPay}) {
    final items = List<Map<String, dynamic>>.from(req['bill_items'] ?? []);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: toPay
          ? F.box(border: F.dark ? F.yellow : F.navy, width: 2)
          : F.box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (toPay) ...[
            Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: F.accent, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Your bill is ready',
                      style: TextStyle(color: F.txt, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(item['name']?.toString() ?? '',
                        style: TextStyle(color: F.txt, fontSize: 16, fontWeight: FontWeight.w600, height: 1.3)),
                  ),
                  const SizedBox(width: 10),
                  Text(_rupees(item['price']),
                      style: TextStyle(color: F.txt, fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          Divider(color: F.line, height: 18),
          Row(
            children: [
              Expanded(
                child: Text('TOTAL', style: TextStyle(color: F.mut, fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_rupees(req['total_amount']),
                      maxLines: 1, style: TextStyle(color: F.accent, fontSize: 26, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (toPay && _v('payment_method') == 'cash')
            // Fleet already picked Cash on Delivery — not paid yet; the
            // garage/delivery partner records cash collection in the CRM.
            Row(children: [
              Icon(Icons.payments_rounded, color: F.amber, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text("Cash on delivery — ${_rupees(req['total_amount'])} on drop-off",
                maxLines: 2,
                style: TextStyle(color: F.amber, fontWeight: FontWeight.w900, fontSize: 16, height: 1.3))),
            ])
          else if (toPay)
            _payRow(req)
          else
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: F.green, size: 22),
                const SizedBox(width: 8),
                Text(_v('payment_method') == 'cash' ? 'Paid (cash)' : 'Paid',
                  style: TextStyle(color: F.green, fontWeight: FontWeight.w900, fontSize: 17)),
              ],
            ),
        ],
      ),
    );
  }

  /// The fleet picks how to settle this bill: pay now with Razorpay, or
  /// pay cash when the car is delivered back. Cash doesn't go through
  /// Razorpay at all; the amount is just logged against the fleet
  /// account for the CRM to collect.
  Widget _payRow(Map req) {
    return SizedBox(
      height: 58,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: F.yellow,
          foregroundColor: F.navy,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.payments_rounded, size: 20),
        onPressed: _isSubmitting ? null : () => _choosePayment(req),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('PAY ${_rupees(req['total_amount'])}',
            maxLines: 1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }

  Future<void> _choosePayment(Map req) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: F.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 44, height: 4, margin: const EdgeInsets.only(bottom: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: F.line, borderRadius: BorderRadius.circular(2))),
            Center(child: Text('How would you like to pay?',
              style: TextStyle(color: F.txt, fontSize: 19, fontWeight: FontWeight.w900))),
            const SizedBox(height: 4),
            Center(child: Text(_rupees(req['total_amount']),
              style: TextStyle(color: F.accent, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
            const SizedBox(height: 14),
            _payChoice(ctx, 'razorpay', Icons.lock_rounded, 'Pay now',
              'UPI, card or net banking · instant'),
            const SizedBox(height: 10),
            _payChoice(ctx, 'cash', Icons.payments_rounded, 'Cash on delivery',
              'Hand it over when the car is dropped back'),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'razorpay') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            title: 'Fleet Service — ${req['company_name'] ?? ''}',
            duration: '',
            vehicleId: '',
            vehicleRequired: false,
            fleetRequestId: '${req['id']}',
          ),
        ),
      );
      if (mounted) setState(() {});
      await _refreshLive();
      return;
    }

    // Cash on Delivery — mark it on the row and come back.
    setState(() => _isSubmitting = true);
    try {
      final companyUserId = widget.request['fleet_user_id'];
      await BookingApi.fleetChooseCod(id: '${req['id']}', fleetUserId: companyUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Noted — pay cash when the car is dropped back')),
      );
      await _refreshLive();
    } catch (e) {
      if (mounted) {
        ErrorDisplay.showPremiumError(context, error: e,
          customMessage: e is BookingApiException ? e.message : "Couldn't record Cash on Delivery.");
      }
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  Widget _payChoice(BuildContext ctx, String key, IconData icon, String title, String subtitle) =>
    Material(
      color: F.sunken, borderRadius: BorderRadius.circular(16),
      child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => Navigator.pop(ctx, key),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 44, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(color: F.yellow.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: F.accent, size: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: F.txt, fontSize: 16.5, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3)),
            ])),
            Icon(Icons.chevron_right_rounded, color: F.mut, size: 24),
          ]),
        )),
    );

  /// Approve / reject what the garage sent (or the decision already made).
  Widget _approvalCard(String adminComment, {required bool urgent}) {
    final decided = _approvalState != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: urgent
          ? BoxDecoration(color: F.amberBg, borderRadius: BorderRadius.circular(20))
          : F.box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!decided) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: urgent ? F.amber : F.accent, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Approve the work',
                      style: TextStyle(color: urgent ? F.amber : F.txt, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              adminComment.isNotEmpty
                  ? 'Read the garage update below, then approve or reject.'
                  : 'Review the work done and approve or reject.',
              style: TextStyle(color: urgent ? F.amber : F.mut, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
            ),
            const SizedBox(height: 14),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: decided ? _buildApprovalResult(_approvalState!) : _buildApprovalButtons(),
          ),
        ],
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
            icon: Icons.check_circle_rounded,
            color: F.greenSolid,
            filled: true,
            isLoading: _isSubmitting,
            onPressed: () => _handleApproval('Approved'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ApprovalButton(
            label: 'REJECT',
            icon: Icons.cancel_rounded,
            color: F.red,
            isLoading: _isSubmitting,
            onPressed: () => _handleApproval('Rejected'),
          ),
        ),
      ],
    );
  }

  Widget _buildApprovalResult(String decision) {
    final isApproved = decision == 'Approved';
    final color = isApproved ? F.green : F.red;
    final icon = isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded;
    final label = isApproved ? 'Approved' : 'Rejected';
    final sublabel = isApproved ? 'You approved this work. The garage will go ahead.' : 'You rejected this work. The garage has been told.';

    return FadeTransition(
      key: ValueKey('result_$decision'),
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(
            color: isApproved ? F.greenBg : F.redBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(sublabel, style: TextStyle(color: F.mut, fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600)),
                  ],
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

class _ApprovalButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final bool isLoading;
  final VoidCallback onPressed;

  const _ApprovalButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.filled = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: filled ? color : F.card,
          foregroundColor: fg,
          disabledBackgroundColor: filled ? color.withOpacity(0.6) : F.card,
          disabledForegroundColor: fg.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: filled ? BorderSide.none : BorderSide(color: color, width: 2),
          ),
          elevation: 0,
        ),
        icon: isLoading
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: fg, strokeWidth: 2.2))
            : Icon(icon, size: 21),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5, letterSpacing: 0.4)),
        ),
        onPressed: isLoading ? null : onPressed,
      ),
    );
  }
}
