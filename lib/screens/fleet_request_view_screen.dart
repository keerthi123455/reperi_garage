import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';

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

  // ── Animation controllers ──
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
        await Supabase.instance.client
            .from('fleet_pickup_requests')
            .update({'has_unread_update': false}).eq('id', widget.request['id']);
      }
    });

    _watchRequestForUnreadChat();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Send failed: $e'),
          backgroundColor: Colors.red,
        ),
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
    Supabase.instance.client
        .from('fleet_pickup_requests')
        .update({'fleet_has_unread_chat': false}).eq('id', widget.request['id']);

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
    return Container(
      height: MediaQuery.of(sheetCtx).size.height * 0.72 + viewInsets.bottom,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFF2A2A2A)),
          left: BorderSide(color: Color(0xFF2A2A2A)),
          right: BorderSide(color: Color(0xFF2A2A2A)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded,
                      color: Color(0xFFD4A017), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Garage Admin',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Real-time conversation',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(sheetCtx),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E1E1E), height: 20),

          Expanded(
            child: _chatLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFD4A017),
                      strokeWidth: 2,
                    ),
                  )
                : _chatMessages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet.\nStart the conversation.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.white24, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: _chatScrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _chatMessages.length,
                        itemBuilder: (_, i) {
                          final msg = _chatMessages[i];
                          final isFleet = msg['sender_type'] == 'fleet';
                          final seen = isFleet
                              ? msg['is_read_by_admin'] == true
                              : msg['is_read_by_fleet'] == true;
                          return _chatBubble(
                              msg['message'] ?? '', isFleet, seen);
                        },
                      ),
          ),

          if (_otherTyping)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFFD4A017),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Garage Admin is typing…',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding:
                EdgeInsets.fromLTRB(16, 0, 16, 16 + viewInsets.bottom),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: TextField(
                      controller: _chatController,
                      onChanged: _handleChatTyping,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendChatMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message…',
                        hintStyle: TextStyle(color: Color(0xFF444444)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _sendChatMessage,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _chatSending
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            color: Colors.black, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatBubble(String message, bool isFleet, bool seen) {
    return Align(
      alignment: isFleet ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isFleet ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            constraints: const BoxConstraints(maxWidth: 280),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isFleet
                  ? const Color(0xFFD4A017).withOpacity(0.15)
                  : const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isFleet ? 16 : 4),
                bottomRight: Radius.circular(isFleet ? 4 : 16),
              ),
              border: isFleet
                  ? Border.all(
                      color: const Color(0xFFD4A017).withOpacity(0.25))
                  : Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Text(
              message,
              style: TextStyle(
                color:
                    isFleet ? const Color(0xFFE8C84A) : Colors.white,
                fontSize: 13.5,
              ),
            ),
          ),
          if (isFleet)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    seen ? Icons.remove_red_eye : Icons.remove_red_eye_outlined,
                    size: 11,
                    color: seen ? const Color(0xFFD4A017) : Colors.white24,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    seen ? 'Seen' : 'Sent',
                    style: TextStyle(
                      fontSize: 10,
                      color: seen ? const Color(0xFFD4A017) : Colors.white24,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: Colors.red),
      );
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_rounded,
                      color: Color(0xFFD4A017)),
                  onPressed: _openChatPopup,
                ),
                if (_hasUnreadChat)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),

      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: const BoxDecoration(
            color: Colors.black,
            border:
                Border(top: BorderSide(color: Color(0xFF1E1E1E), width: 1)),
          ),
          child: Row(
            children: [
              Expanded(
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
                  onPressed: _callGarage,
                ),
              ),
              const SizedBox(width: 12),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      minimumSize: const Size(54, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: const Color(0xFFD4A017).withOpacity(0.4),
                        ),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _openChatPopup,
                    child: const Icon(Icons.chat_bubble_rounded,
                        color: Color(0xFFD4A017), size: 22),
                  ),
                  if (_hasUnreadChat)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
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

                const SizedBox(height: 20),
                const _Label('STATUS'),
                const SizedBox(height: 8),
                _StatusBadge(status: req['status'] ?? 'Pending'),

                const SizedBox(height: 24),
                _Divider(),

                if (req['payment_status'] == 'awaiting_payment' ||
                    req['payment_status'] == 'paid') ...[
                  const SizedBox(height: 20),
                  const _Label('SERVICE BILL'),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...List<Map<String, dynamic>>.from(req['bill_items'] ?? []).map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item['name']?.toString() ?? '',
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  '₹${item['price']}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(color: Color(0xFF2A2A2A), height: 1),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1)),
                            Text(
                              '₹${req['total_amount']}',
                              style: const TextStyle(
                                color: Color(0xFFD4A017),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (req['payment_status'] == 'awaiting_payment')
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD4A017),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PaymentScreen(
                                      title: 'Fleet Service — ${req['company_name'] ?? ''}',
                                      price: '₹${req['total_amount']}',
                                      duration: '',
                                      vehicleId: '',
                                      billItems: List<Map<String, dynamic>>.from(req['bill_items'] ?? []),
                                      onlineOnly: true,
                                      onSuccess: (orderId, paymentId) async {
                                        await Supabase.instance.client
                                            .from('fleet_pickup_requests')
                                            .update({
                                              'payment_status': 'paid',
                                              'razorpay_order_id': orderId,
                                              'razorpay_payment_id': paymentId,
                                            })
                                            .eq('id', req['id']);
                                      },
                                    ),
                                  ),
                                );
                                if (mounted) setState(() {});
                              },
                              child: const Text(
                                'PAY NOW',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1),
                              ),
                            ),
                          )
                        else
                          Row(
                            children: const [
                              Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                              SizedBox(width: 8),
                              Text('Paid', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Divider(),
                ],

                if (statuses.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const _Label('STATUS HISTORY'),
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
                              color: isLast
                                  ? Colors.white
                                  : Colors.white54,
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

                const SizedBox(height: 20),
                const _Label('ADMIN COMMENT'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.07)),
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

                if (comments.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const _Label('COMMENT HISTORY'),
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

                const SizedBox(height: 20),
                const _Label('GARAGE PHOTO UPDATE'),
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
                        Text('No photo uploaded yet.',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 14)),
                      ],
                    ),
                  ),

                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const _Label('PHOTO HISTORY'),
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

                const SizedBox(height: 20),
                const _Label('WORK APPROVAL'),
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
          decoration:
              BoxDecoration(color: _color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          status,
          style: TextStyle(
              color: _color, fontSize: 20, fontWeight: FontWeight.bold),
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