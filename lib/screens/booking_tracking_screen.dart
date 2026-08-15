import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/inspection_view_widget.dart';

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
  List updates = [];
  bool loading = true;
  bool hasUnreadMessages = false;

  @override
  void initState() {
    super.initState();
    fetchUpdates();
    checkUnreadMessages();
    _markUpdateAsRead();
    if (widget.autoOpenChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openChat());
    }
  }

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

  Future<void> fetchUpdates() async {
    final supabase = Supabase.instance.client;

    final response = await supabase
        .from('booking_updates')
        .select()
        .eq('booking_id', widget.booking['id'])
        .order('created_at', ascending: true);

    if (!mounted) return;

    setState(() {
      updates = response;
      loading = false;
    });
  }

  Future<void> checkUnreadMessages() async {
    final supabase = Supabase.instance.client;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.booking['package_name'],
          style: const TextStyle(color: Color(0xFFD4A017)),
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4A017)),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // ── HEADER CARD ──
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.booking['package_name'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            widget.booking['package_price'],
                            style: const TextStyle(
                              color: Color(0xFFD4A017),
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4A017).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              widget.booking['booking_status'],
                              style: const TextStyle(
                                color: Color(0xFFD4A017),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    const Text(
                      'Service Timeline',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 20),

                    ...updates.map((u) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFD4A017),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    u['stage'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.network(
                                u['image_url'],
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              u['description'] ?? '',
                              style: const TextStyle(
                                color: Colors.white70,
                                height: 1.5,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 30),

                    // ── INSPECTION SECTION ──
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.camera_alt_rounded,
                                color: Color(0xFFD4A017),
                                size: 24,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Inspection Report',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          InspectionViewWidget(
                            bookingId: widget.booking['id'],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // ── CHAT BUTTON ──
                    GestureDetector(
                      onTap: openChat,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            height: 68,
                            decoration: BoxDecoration(
                              color: const Color(0xFF111111),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFFD4A017).withOpacity(0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline_rounded,
                                    color: Color(0xFFD4A017), size: 22),
                                SizedBox(width: 10),
                                Text(
                                  'CHAT WITH GARAGE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (hasUnreadMessages)
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.6),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ── CALL BUTTON ──
                    GestureDetector(
                      onTap: () async {
                        final uri = Uri(scheme: 'tel', path: '9353094672');
                        // ignore: deprecated_member_use
                        await launchUrl(uri);
                      },
                      child: Container(
                        height: 68,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Center(
                          child: Text(
                            'CALL GARAGE',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
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
  }

  Future<void> markMessagesRead() async {
    final supabase = Supabase.instance.client;

    final otherSender =
        widget.sender == 'consumer' ? 'admin' : 'consumer';

    final readField = widget.sender == 'consumer'
        ? 'is_read_by_consumer'
        : 'is_read_by_admin';

    await supabase
        .from('booking_chats')
        .update({readField: true})
        .eq('booking_id', widget.bookingId)
        .eq('sender', otherSender);

    widget.onMessagesRead?.call();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e'), backgroundColor: Colors.red),
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
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // ── Handle ──
          Container(
            margin: const EdgeInsets.only(top: 14, bottom: 10),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
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
                    const Text(
                      'Garage Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                // 🔒 SAFETY MENU
                if (blockingLoaded)
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white54),
                    onPressed: () {
                      final otherSender = widget.sender == 'consumer' ? 'admin' : 'consumer';
                      _showSafetyMenu(otherSender);
                    },
                  ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF1E1E1E), height: 1),

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
                            const Text(
                              'You are blocked',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'You cannot send or receive messages from this user',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : messages.isEmpty
                        ? const Center(
                            child: Text(
                              'No messages yet.\nSend the first one!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 15, height: 1.6),
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
                                        : const Color(0xFF1E1E1E),
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
                                      color: isMe ? Colors.black : Colors.white,
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
                                              : Colors.white24,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          seen ? 'Seen' : 'Sent',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: seen
                                                ? const Color(0xFFD4A017)
                                                : Colors.white24,
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
                    style: const TextStyle(
                      color: Colors.white38,
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
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: Color(0xFF1E1E1E))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _handleTyping,
                    enabled: !isBlockedByOther && blockingLoaded,
                    style: const TextStyle(color: Colors.white),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: isBlockedByOther ? 'You are blocked' : 'Type a message...',
                      hintStyle:
                          const TextStyle(color: Color(0xFF444444)),
                      filled: true,
                      fillColor: isBlockedByOther 
                          ? const Color(0xFF2A1A1A)
                          : const Color(0xFF1A1A1A),
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
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.black,
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
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
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
              title: const Text('Cancel', style: TextStyle(color: Colors.white54)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User unblocked'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
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
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Report User',
          style: TextStyle(
            color: Colors.white,
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
                  style: const TextStyle(
                    color: Colors.white,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. Thank you!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}