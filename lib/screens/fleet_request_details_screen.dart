import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class FleetRequestDetailsScreen extends StatefulWidget {
  final Map fleetRequest;

  const FleetRequestDetailsScreen({
    super.key,
    required this.fleetRequest,
  });

  @override
  State<FleetRequestDetailsScreen> createState() =>
      _FleetRequestDetailsScreenState();
}

class _FleetRequestDetailsScreenState
    extends State<FleetRequestDetailsScreen> {
  late String _currentStatus;
  late String _pendingStatus;

  Uint8List? _adminImageBytes;

  final _picker = ImagePicker();
  bool _updating = false;
  final _commentController = TextEditingController();

  // ── Chat state ──
  final _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  List<Map<String, dynamic>> _chatMessages = [];
  bool _chatLoading = false;
  bool _chatSending = false;
  RealtimeChannel? _chatChannel;

  // ── Sheet setState handle ──
  StateSetter? _sheetSetState;

  // ── Live unread badge state ──
  late bool _hasUnreadChat;
  RealtimeChannel? _requestWatchChannel;

  final List<String> _statusOptions = [
    'Pending',
    'Picked Up',
    'In Garage',
    'Completed',
  ];

  late String _paymentStatus;
  List<Map<String, dynamic>>? _billItems;
  num? _totalAmount;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.fleetRequest['status'] ?? 'Pending';
    _pendingStatus = _currentStatus;
    _hasUnreadChat = widget.fleetRequest['admin_has_unread_chat'] == true;
    _paymentStatus = widget.fleetRequest['payment_status'] ?? 'unpaid';
    _billItems = widget.fleetRequest['bill_items'] != null
        ? List<Map<String, dynamic>>.from(widget.fleetRequest['bill_items'])
        : null;
    _totalAmount = widget.fleetRequest['total_amount'];

    Future.microtask(() async {
      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({'has_unread_update': false}).eq(
              'id', widget.fleetRequest['id']);
    });

    _watchRequestForUnreadChat();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatChannel?.unsubscribe();
    _requestWatchChannel?.unsubscribe();
    super.dispose();
  }

  // ── Live badge: watch this request row for admin_has_unread_chat changes ──

  void _watchRequestForUnreadChat() {
    _requestWatchChannel = Supabase.instance.client
        .channel('fleet_request_watch_${widget.fleetRequest['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'fleet_pickup_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.fleetRequest['id'],
          ),
          callback: (payload) {
            if (!mounted) return;
            final updated = payload.newRecord;
            final unread = updated['admin_has_unread_chat'] == true;
            if (unread != _hasUnreadChat) {
              setState(() => _hasUnreadChat = unread);
            }
          },
        )
        .subscribe();
  }

  // ── Chat helpers ──

  Future<void> _loadChatMessages() async {
    _sheetSetState?.call(() => _chatLoading = true);
    try {
      final rows = await Supabase.instance.client
          .from('fleet_chat_messages')
          .select()
          .eq('request_id', widget.fleetRequest['id'].toString())
          .order('created_at', ascending: true);
      if (mounted) {
        _chatMessages = List<Map<String, dynamic>>.from(rows);
        _sheetSetState?.call(() {});
        _scrollChatToBottom();
      }
    } catch (_) {}
    if (mounted) {
      _sheetSetState?.call(() => _chatLoading = false);
    }
  }

  void _subscribeToChat() {
    _chatChannel = Supabase.instance.client
        .channel('fleet_chat_${widget.fleetRequest['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'fleet_chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'request_id',
            value: widget.fleetRequest['id'],
          ),
          callback: (payload) {
            if (!mounted) return;
            final incoming = payload.newRecord;
            // Skip if we already have this row (optimistic insert matched by id)
            final alreadyExists = _chatMessages.any(
              (m) => m['id'] != null && m['id'] == incoming['id'],
            );
            if (alreadyExists) return;
            _chatMessages.add(incoming);
            _sheetSetState?.call(() {});
            _scrollChatToBottom();
          },
        )
        .subscribe();
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
_sheetSetState?.call(() {});
    _sheetSetState?.call(() => _chatSending = true);

    // Optimistically add the message locally so it shows instantly
    final optimisticMsg = {
      'request_id': widget.fleetRequest['id'].toString(),
      'sender_type': 'admin',
      'sender_name': 'Garage Admin',
      'message': text,
      'created_at': DateTime.now().toIso8601String(),
    };
    _chatMessages.add(optimisticMsg);
    _sheetSetState?.call(() {});
    _scrollChatToBottom();

    try {
      final inserted = await Supabase.instance.client
          .from('fleet_chat_messages')
          .insert({
            'request_id': widget.fleetRequest['id'].toString(),
            'sender_type': 'admin',
            'sender_name': 'Garage Admin',
            'message': text,
          })
          .select()
          .single();

      // Replace optimistic entry with the real DB row
      final idx = _chatMessages.indexOf(optimisticMsg);
      if (idx != -1) {
        _chatMessages[idx] = Map<String, dynamic>.from(inserted);
        _sheetSetState?.call(() {});
      }

      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({'fleet_has_unread_chat': true}).eq(
              'id', widget.fleetRequest['id']);
    } catch (e) {
      // Roll back the optimistic message on failure
      _chatMessages.remove(optimisticMsg);
      _sheetSetState?.call(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Send failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) _sheetSetState?.call(() => _chatSending = false);
  }

  void _openChatPopup() {
    // Mark admin unread as cleared locally and in DB
    setState(() => _hasUnreadChat = false);
    Supabase.instance.client
        .from('fleet_pickup_requests')
        .update({'admin_has_unread_chat': false}).eq(
            'id', widget.fleetRequest['id']);

    // Reset chat state before opening
    _chatMessages = [];
    _chatLoading = true;
    _sheetSetState = null;

    _subscribeToChat();

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
                    children: [
                      Text(
                        widget.fleetRequest['company_name'] ?? 'Fleet Chat',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const Text(
                        'Real-time conversation',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 11),
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
                          final isAdmin = msg['sender_type'] == 'admin';
                          return _chatBubble(msg['message'] ?? '', isAdmin);
                        },
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

  Widget _chatBubble(String message, bool isAdmin) {
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isAdmin
              ? const Color(0xFFD4A017).withOpacity(0.15)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isAdmin ? 16 : 4),
            bottomRight: Radius.circular(isAdmin ? 4 : 16),
          ),
          border: isAdmin
              ? Border.all(
                  color: const Color(0xFFD4A017).withOpacity(0.25))
              : Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isAdmin ? const Color(0xFFE8C84A) : Colors.white,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  // ── Existing methods ──

  Future<void> _confirmStatusChange() async {
    if (_pendingStatus == _currentStatus) return;
    setState(() => _updating = true);
    try {
      final currentRequest = await Supabase.instance.client
          .from('fleet_pickup_requests')
          .select()
          .eq('id', widget.fleetRequest['id'])
          .single();

      final existingStatusHistory =
          currentRequest['status_history'] ?? '';

      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({
            'status': _pendingStatus,
            'status_history': '$existingStatusHistory|$_pendingStatus',
            'has_unread_update': false,
          }).eq('id', widget.fleetRequest['id']);

      if (!mounted) return;
      setState(() => _currentStatus = _pendingStatus);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to $_pendingStatus'),
          backgroundColor: const Color(0xFFD4A017),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _showChargeFleetSheet() {
    final items = <Map<String, TextEditingController>>[
      {
        'name': TextEditingController(text: '21 Step Inspection'),
        'price': TextEditingController(text: '2999'),
      },
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            num total = 0;
            for (final item in items) {
              total += num.tryParse(item['price']!.text.trim()) ?? 0;
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const Text(
                        'Charge Fleet',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Add each billable item and its price.',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                      const SizedBox(height: 20),

                      ...items.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: item['name'],
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Item ${index + 1}',
                                    labelStyle: const TextStyle(color: Colors.white54),
                                    filled: true,
                                    fillColor: const Color(0xFF1A1A1A),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: item['price'],
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white),
                                  onChanged: (_) => setSheetState(() {}),
                                  decoration: InputDecoration(
                                    labelText: '₹ Price',
                                    labelStyle: const TextStyle(color: Colors.white54),
                                    filled: true,
                                    fillColor: const Color(0xFF1A1A1A),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              if (items.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                                  onPressed: () => setSheetState(() => items.removeAt(index)),
                                ),
                            ],
                          ),
                        );
                      }),

                      TextButton.icon(
                        onPressed: () => setSheetState(() {
                          items.add({
                            'name': TextEditingController(),
                            'price': TextEditingController(),
                          });
                        }),
                        icon: const Icon(Icons.add, color: Color(0xFFD4A017)),
                        label: const Text('Add Item', style: TextStyle(color: Color(0xFFD4A017))),
                      ),

                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1)),
                            Text(
                              '₹${total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Color(0xFFD4A017),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4A017),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: total <= 0
                              ? null
                              : () async {
                                  final finalItems = items
                                      .where((i) => i['name']!.text.trim().isNotEmpty &&
                                          num.tryParse(i['price']!.text.trim()) != null)
                                      .map((i) => {
                                            'name': i['name']!.text.trim(),
                                            'price': num.parse(i['price']!.text.trim()),
                                          })
                                      .toList();

                                  Navigator.pop(sheetContext);
                                  await _submitCharge(finalItems, total);
                                },
                          child: Text(
                            'CHARGE ₹${total.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitCharge(List<Map<String, dynamic>> items, num total) async {
    setState(() => _updating = true);
    try {
      await Supabase.instance.client.from('fleet_pickup_requests').update({
        'bill_items': items,
        'total_amount': total,
        'payment_status': 'awaiting_payment',
        'billed_at': DateTime.now().toIso8601String(),
        'has_unread_update': true,
        'latest_update_type': 'CHARGED',
      }).eq('id', widget.fleetRequest['id']);

      if (!mounted) return;
      setState(() {
        _billItems = items;
        _totalAmount = total;
        _paymentStatus = 'awaiting_payment';
        _updating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fleet charged ₹${total.toStringAsFixed(0)}'),
          backgroundColor: const Color(0xFFD4A017),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _updating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to charge: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _saveComment() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) return;
    setState(() => _updating = true);
    try {
      final currentRequest = await Supabase.instance.client
          .from('fleet_pickup_requests')
          .select()
          .eq('id', widget.fleetRequest['id'])
          .single();

      final existingComments = currentRequest['comment_history'] ?? '';

      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({
            'admin_comment': comment,
            'comment_history': '$existingComments|$comment',
            'has_unread_update': false,
          }).eq('id', widget.fleetRequest['id']);

      if (!mounted) return;
      _commentController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Comment saved'),
            backgroundColor: Color(0xFFD4A017)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _pickAdminImage() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;
    final picked =
        await _picker.pickImage(source: source, imageQuality: 70);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _adminImageBytes = bytes);
  }

  Future<ImageSource?> _showImageSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Add Garage Photo',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFFD4A017)),
                title: const Text('Take Photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: Color(0xFFD4A017)),
                title: const Text('Choose from Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _uploadAdminPhoto() async {
    if (_adminImageBytes == null) return;
    setState(() => _updating = true);
    try {
      final fileName =
          'garage_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('booking-images')
          .uploadBinary(
            'garage/$fileName',
            _adminImageBytes!,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg'),
          );

      final imageUrl = Supabase.instance.client.storage
          .from('booking-images')
          .getPublicUrl('garage/$fileName');

      final currentRequest = await Supabase.instance.client
          .from('fleet_pickup_requests')
          .select()
          .eq('id', widget.fleetRequest['id'])
          .single();

      final existingHistory = currentRequest['photo_history'] ?? '';

      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({
            'admin_photo_url': imageUrl,
            'photo_history': '$existingHistory|$imageUrl',
            'customer_approval': null,
          }).eq('id', widget.fleetRequest['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Garage photo uploaded')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
    if (mounted) setState(() => _updating = false);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Picked Up':
        return Colors.blueAccent;
      case 'In Garage':
        return Colors.orangeAccent;
      case 'Completed':
        return Colors.greenAccent;
      default:
        return const Color(0xFFD4A017);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = widget.fleetRequest;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Color(0xFFD4A017)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'FLEET REQUEST',
          style: TextStyle(
            color: Color(0xFFD4A017),
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Fleet info card ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(28),
                    border:
                        Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4A017)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.local_shipping_rounded,
                              color: Color(0xFFD4A017),
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fleet['company_name'] ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  fleet['vehicle_model'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _infoRow('Car Number', fleet['car_number'] ?? ''),
                      _infoRow(
                          'Driver Name', fleet['driver_name'] ?? ''),
                      _infoRow('Phone', fleet['phone'] ?? ''),
                      _infoRow('Pickup Address',
                          fleet['pickup_address'] ?? ''),
                      const SizedBox(height: 20),
                      if (fleet['vehicle_photo_url'] != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'VEHICLE PHOTO UPLOADED BY FLEET',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                fleet['vehicle_photo_url'],
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      const Text(
                        'CUSTOMER RESPONSE',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          fleet['customer_approval'] ??
                              'Awaiting Response',
                          style: TextStyle(
                            color: fleet['customer_approval'] ==
                                    'Approved'
                                ? Colors.green
                                : fleet['customer_approval'] ==
                                        'Rejected'
                                    ? Colors.red
                                    : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Status ──
                const Text(
                  'UPDATE STATUS',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 14),

                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _pendingStatus,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A1A1A),
                      icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFFD4A017)),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      items: _statusOptions.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _statusColor(status),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(status.toUpperCase()),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _pendingStatus = value);
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _pendingStatus != _currentStatus
                      ? SizedBox(
                          key: const ValueKey('confirm-btn'),
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4A017),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _updating
                                ? null
                                : _confirmStatusChange,
                            child: _updating
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.black,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'CONFIRM: $_currentStatus → $_pendingStatus'
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                          ),
                        )
                      : const SizedBox(
                          key: ValueKey('no-confirm')),
                ),

                const SizedBox(height: 20),

                // ── Charge Fleet ──
                if (_currentStatus == 'Completed' && _paymentStatus == 'unpaid')
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _showChargeFleetSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A017),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.receipt_long_rounded, color: Colors.black),
                      label: const Text(
                        'CHARGE FLEET',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                  )
                else if (_paymentStatus == 'awaiting_payment')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD4A017), size: 18),
                        const SizedBox(width: 10),
                        Text(
                          'Charged ₹${_totalAmount?.toStringAsFixed(0) ?? ''} — awaiting fleet payment',
                          style: const TextStyle(color: Color(0xFFD4A017), fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else if (_paymentStatus == 'paid')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          'Paid ₹${_totalAmount?.toStringAsFixed(0) ?? ''}',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),

                // ── Comment ──
                const Text(
                  'ADMIN COMMENT',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'A formal note/log saved with this request — not a live chat.',
                  style:
                      TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 14),

                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: TextField(
                    controller: _commentController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Add a comment or note…',
                      hintStyle:
                          TextStyle(color: Color(0xFF444444)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A017),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _updating ? null : _saveComment,
                    child: _updating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'SAVE COMMENT',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Chat popup button ──
                GestureDetector(
                  onTap: _openChatPopup,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFD4A017).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: const Color(0xFFD4A017)
                              .withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A017)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                              Icons.chat_bubble_rounded,
                              color: Color(0xFFD4A017),
                              size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chat with Fleet',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Real-time messaging for quick updates',
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        if (_hasUnreadChat)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          )
                        else
                          const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFFD4A017),
                              size: 14),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Garage photo ──
                const Text(
                  'GARAGE PHOTO UPDATE',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 14),

                GestureDetector(
                  onTap: _pickAdminImage,
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: const Color(0xFF2A2A2A)),
                    ),
                    child: _adminImageBytes == null
                        ? const Center(
                            child: Text(
                              'UPLOAD GARAGE PHOTO',
                              style:
                                  TextStyle(color: Colors.white54),
                            ),
                          )
                        : ClipRRect(
                            borderRadius:
                                BorderRadius.circular(18),
                            child: Image.memory(
                              _adminImageBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A017),
                    ),
                    onPressed:
                        _updating ? null : _uploadAdminPhoto,
                    child: const Text(
                      'UPLOAD PHOTO',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}