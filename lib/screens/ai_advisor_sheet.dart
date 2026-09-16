import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'profile_screen.dart';
import '../services/ai_chat_session.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'services_screen.dart'
    show exportPackageCatalogForAi, buildPackageScreenFor, categoryAccentColor, categoryIconFor;

// ─────────────────────────────────────────────────────────────────────────────
// pubspec.yaml dependencies needed:
//   image_picker: ^1.0.7
//   url_launcher: ^6.2.5
//
// ios/Runner/Info.plist — add:
//   <key>NSCameraUsageDescription</key>
//   <string>Used to photograph your vehicle for diagnosis</string>
//   <key>NSPhotoLibraryUsageDescription</key>
//   <string>Used to select vehicle photos for diagnosis</string>
//   <key>LSApplicationQueriesSchemes</key>
//   <array><string>tel</string></array>
//
// android/app/src/main/AndroidManifest.xml — add inside <manifest>:
//   <queries>
//     <intent>
//       <action android:name="android.intent.action.DIAL" />
//     </intent>
//   </queries>
// ─────────────────────────────────────────────────────────────────────────────

const String _expertPhone = '9353094672';

class AiAdvisorSheet extends StatefulWidget {
  /// Pass the active vehicle map from HomeScreen so LEARN MORE can forward
  /// vehicleId → the package's real screen → PaymentScreen → bookings table.
  final Map<String, dynamic>? vehicle;

  const AiAdvisorSheet({super.key, this.vehicle});

  @override
  State<AiAdvisorSheet> createState() => _AiAdvisorSheetState();
}

class _AiAdvisorSheetState extends State<AiAdvisorSheet>
    with TickerProviderStateMixin {
  // ── Controllers ────────────────────────────────────────────────────────────
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  // ── State ──────────────────────────────────────────────────────────────────
  bool _isTyping = false;
  bool _showChips = true;
  Uint8List? _attachedImage;

  // ── Theme ──────────────────────────────────────────────────────────────────
  // Routed through AppColors so the sheet follows the app's light/dark
  // toggle instead of staying permanently dark — these are getters (not
  // `static const`) because AppColors' fields are mutated in place by
  // themeController and are therefore not compile-time constants.
  static Color get _bg => AppColors.ink;
  static Color get _surface => AppColors.surfaceRaised;
  static Color get _surfaceAlt => AppColors.surfaceRaised;
  static Color get _surfaceSunken => AppColors.surfaceSunken;
  static const Color _gold       = Color(0xFFD4A017);
  static const Color _goldLight  = Color(0xFFF5C842);
  static Color get _white => AppColors.txt;
  static Color get _grey => AppColors.mut;
  static Color get _border => AppColors.line;
  static const Color _green      = Color(0xFF4CAF50);

  // ── Messages ───────────────────────────────────────────────────────────────
  // Backed by AiChatSession.messages (the same List instance, not a copy) —
  // every `messages.add(...)` below already mutates that shared list in
  // place, so closing this sheet or navigating away to a suggested package
  // and coming back needs no separate save step; reopening just reads the
  // same list again.
  List<Map<String, dynamic>> get messages => AiChatSession.messages;

  final List<String> _quickPrompts = [
    'Scratch on bumper',
    "Car won't start",
    'AC not cooling',
    'Tyre vibration',
    'Engine noise',
    'Brake squeaking',
  ];

  // ── Catalog ────────────────────────────────────────────────────────────────
  // The exact same catalog the Services screen searches over (every real
  // package, every category, every screen) via exportPackageCatalogForAi()
  // — the AI can only ever recommend from this list, and every suggestion
  // opens the exact real screen for it via buildPackageScreenFor(). No
  // separate hardcoded package list exists anywhere in this file.
  List<Map<String, dynamic>> _catalogForAi = [];

  /// Loads the catalog — synchronous and instant, since it's the same
  /// static data the Services screen already holds in memory.
  void _loadPackageCatalogForAi() {
    _catalogForAi = exportPackageCatalogForAi().map((p) {
      return {
        // category+name is a stable, unique identifier into that catalog —
        // it has no separate database key of its own.
        'key': '${p['category']}::::${p['name']}',
        'name': p['name'],
        'category': p['category'],
        'price': p['price'],
        'duration': p['duration'],
        'tagline': p['tagline'],
        'features': p['features'],
      };
    }).toList();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final resuming = AiChatSession.messages.isNotEmpty;
    if (!resuming) {
      AiChatSession.messages.add({
        'isUser': false,
        'text':
            "Hi 👋 I'm REPERI AI. Tell me what's wrong with your vehicle — or upload a photo and I'll recommend the right service.",
      });
    } else {
      // Already mid-conversation — the "COMMON ISSUES" starter chips don't
      // belong above a chat that's already going, and jumping straight to
      // the latest message reads as picking up where it left off rather
      // than reopening from scratch.
      _showChips = false;
      _scrollToBottom(delayMs: 200);
    }
    _loadPackageCatalogForAi();
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this sheet dirty on its own
    // when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _scrollToBottom({int delayMs = 100}) {
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// Wipes AiChatSession and reseeds just the greeting — same as a first
  /// open — then shows a brief animated confirmation. Discards whatever
  /// was there; there's no undo, but the conversation is only ever
  /// session-scoped scratch state to begin with, never something booked
  /// or saved server-side.
  void _startNewChat() {
    AiChatSession.clear();
    setState(() {
      _attachedImage = null;
      _showChips = true;
      messages.add({
        'isUser': false,
        'text':
            "Hi 👋 I'm REPERI AI. Tell me what's wrong with your vehicle — or upload a photo and I'll recommend the right service.",
      });
    });
    _showNewChatToast();
  }

  /// A short, self-dismissing "Starting new chat" popup — purely
  /// decorative feedback, not a confirmation prompt (the reset itself
  /// already happened by the time this shows).
  void _showNewChatToast() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const _NewChatToast(),
      transitionBuilder: (_, animation, __, child) {
        final t = Curves.easeOutBack.transform(animation.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
        );
      },
    );
  }

  /// Opens the native phone dialer with the expert number.
  Future<void> _callExpert() async {
    final uri = Uri(scheme: 'tel', path: _expertPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open dialer. Please call +91 93530 94672'),
            backgroundColor: _surfaceSunken,
          ),
        );
      }
    }
  }

  /// Opens the real screen for a suggested package — looked up by
  /// category+name against the Services screen's own catalog via
  /// [buildPackageScreenFor] — so it always lands exactly where that
  /// package actually lives, never a guess. Prompts to add a vehicle first
  /// if none is linked.
  void _openPackage(Map<String, dynamic> pkg) {
    final vehicleId = widget.vehicle?['id']?.toString() ?? '';

    if (vehicleId.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.directions_car_outlined,
                      color: _gold, size: 34),
                ),
                const SizedBox(height: 20),
                Text(
                  'ADD A VEHICLE TO BOOK THIS SERVICE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _white, fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context); // close dialog
                    Navigator.pop(context); // close the AI sheet
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfileScreen(autoOpenAddVehicle: true)),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text('ADD VEHICLE',
                          style: TextStyle(
                              color: AppColors.onAccentDark,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    final targetScreen = buildPackageScreenFor(
      pkg['category'] as String,
      pkg['name'] as String,
      widget.vehicle,
    );

    if (targetScreen == null) {
      // Shouldn't happen — every suggestion comes from that same catalog —
      // but never leave the customer stuck on a dead tap if it does.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open that package right now. Please try again.")),
      );
      return;
    }

    // Pushed on top of this still-open sheet (not after closing it) — so
    // pressing back on the package screen reveals this same conversation
    // again, exactly where it was left, instead of dropping the customer
    // back on whatever screen was open before they asked the AI anything.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => targetScreen),
    );
  }

  // ── Image picker ───────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() => _attachedImage = bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Could not access ${source == ImageSource.camera ? "camera" : "gallery"}'),
            backgroundColor: _surfaceSunken,
          ),
        );
      }
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const Text(
                'ADD VEHICLE PHOTO',
                style: TextStyle(
                    color: _gold, fontSize: 11,
                    fontWeight: FontWeight.w800, letterSpacing: 2.5),
              ),
              const SizedBox(height: 20),
              _imageSourceTile(
                icon: Icons.camera_alt_rounded,
                label: 'Take Photo',
                subtitle: 'Open camera now',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 12),
              _imageSourceTile(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Album',
                subtitle: 'Pick from your gallery',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageSourceTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: _surfaceSunken,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border)),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  color: _gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: _gold, size: 22),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: _white, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(color: _grey, fontSize: 12)),
              ],
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios, color: _grey, size: 14),
          ],
        ),
      ),
    );
  }

  // ── Send ───────────────────────────────────────────────────────────────────
  Future<void> sendMessage([String? prefilled]) async {
    final text = (prefilled ?? _controller.text).trim();
    if (text.isEmpty && _attachedImage == null) return;

    _focusNode.unfocus();
    final imageToSend = _attachedImage;

    setState(() {
      _showChips = false;
      messages.add({
        'isUser': true,
        'text': text.isNotEmpty ? text : '📷 Photo attached',
        'image': _attachedImage,
      });
      _attachedImage = null;
      _isTyping = true;
    });

    _controller.clear();
    _scrollToBottom(delayMs: 80);

    final rec = await _getAiReply(text, image: imageToSend);
    if (!mounted) return;

    setState(() {
      _isTyping = false;
      messages.add({'isUser': false, ...rec});
    });
    _scrollToBottom(delayMs: 120);
  }

  /// Detects the image format from its magic bytes so the API gets the
  /// correct `media_type` regardless of whether the picker returned a
  /// camera JPEG or a gallery PNG/WEBP.
  String _detectImageMediaType(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 3 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  /// Calls the `ask-ai-chat` Supabase Edge Function, which proxies to the
  /// real Claude API. The model is handed the entire real package catalog
  /// (every category, every tier, every screen — see [_loadPackageCatalogForAi])
  /// and picks whichever 0-2 keys — ordered basic to more comprehensive —
  /// genuinely fit the customer's issue, writing a reply that explains what
  /// each includes and how it helps using that real data. It can never
  /// invent a price or recommend a package that doesn't exist, because it
  /// can only choose from keys we actually sent it — and even then, the
  /// price/duration/features shown always come back from our own catalog
  /// lookup afterward, never from the model's own words.
  ///
  /// If the call fails for any reason (no network, function not deployed,
  /// etc.) this surfaces a plain error message — there is no hardcoded
  /// keyword-matching fallback anymore.
  Future<Map<String, dynamic>> _getAiReply(String text, {Uint8List? image}) async {
    try {
      // Conversation so far, excluding the canned opening greeting and the
      // user turn we just appended (that one is sent separately as `text`).
      final history = messages
          .sublist(1, messages.length - 1)
          .where((m) => (m['text'] as String?)?.trim().isNotEmpty == true)
          .map((m) => {
                'role': m['isUser'] == true ? 'user' : 'assistant',
                'text': m['text'],
              })
          .toList();

      final body = <String, dynamic>{
        'message': text,
        'history': history,
        'vehicle': {
          'brand': widget.vehicle?['car_brand'],
          'model': widget.vehicle?['car_model'],
        },
        'catalog': _catalogForAi,
      };
      if (image != null) {
        body['imageBase64'] = base64Encode(image);
        body['imageMediaType'] = _detectImageMediaType(image);
      }

      final response = await Supabase.instance.client.functions.invoke(
        'ask-ai-chat',
        body: body,
      );

      if (response.status != 200) {
        throw Exception('ask-ai-chat failed: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>;
      final reply = data['reply'] as String? ??
          "Sorry, I didn't quite catch that — could you try rephrasing?";
      // Anthropic's strict tool schema can't enforce array length itself
      // (see the Edge Function), so the 2/4 caps are enforced here instead.
      final recommendedKeys = (data['recommended_keys'] as List?)
              ?.whereType<String>()
              .take(2)
              .toList() ??
          const [];
      final hints = (data['follow_up_questions'] as List?)
              ?.whereType<String>()
              .take(4)
              .toList() ??
          const [];

      // Look up each recommended key against our own catalog data — if the
      // model names a key that (for whatever reason) isn't in it, it's
      // silently dropped rather than shown with blank price/features.
      final catalogByKey = {for (final p in _catalogForAi) p['key'] as String: p};
      final packages = recommendedKeys
          .map((key) => catalogByKey[key])
          .whereType<Map<String, dynamic>>()
          .map((row) => {
                'name': row['name'] as String,
                'category': row['category'] as String,
                'price': row['price'] as String,
                'duration': row['duration'] as String,
                'tagline': row['tagline'] as String? ?? '',
                'features': List<String>.from(row['features'] as List),
              })
          .toList();

      return {
        'text': reply,
        if (packages.isNotEmpty) 'recommendation': {'packages': packages},
        if (hints.isNotEmpty) 'hints': hints,
      };
    } catch (e) {
      return {
        'text':
            "Sorry, I'm having trouble connecting right now. Please check your connection and try again in a moment, or tap Expert above to speak with someone directly.",
      };
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Matches _buildInputBar's own height math (44 button + 10 top pad +
    // 10 base bottom pad, plus whatever the keyboard/safe-area add) so the
    // floating New Chat button sits pinned just above it, not on top of it,
    // however tall the input bar currently is.
    final inputBarHeight = 64 +
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHandle(),
                  _buildHeader(),
                  if (_showChips) _buildQuickChips(),
                  _buildDivider(),
                  _buildMessageList(),
                  if (_attachedImage != null) _buildImagePreview(),
                  _buildInputBar(),
                ],
              ),
              Positioned(
                right: 16,
                bottom: inputBarHeight + 14,
                child: _buildNewChatFab(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Floating "start a new chat" hub button — sits above the send button,
  /// not in the header, so it's reachable with a thumb without reaching up
  /// to the top of the sheet.
  Widget _buildNewChatFab() {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.35),
      child: InkWell(
        onTap: _startNewChat,
        customBorder: const CircleBorder(),
        child: Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_gold, _goldLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: _gold.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Icon(Icons.add_comment_rounded, color: AppColors.onAccentDark, size: 22),
        ),
      ),
    );
  }

  Widget _buildHandle() => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Container(
          width: 44, height: 4,
          decoration: BoxDecoration(
              color: _border, borderRadius: BorderRadius.circular(2)),
        ),
      );

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_gold, _goldLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _gold.withOpacity(0.35), blurRadius: 14)],
            ),
            child: Icon(Icons.auto_awesome_rounded, color: AppColors.onAccentDark, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('REPERI AI',
                  style: TextStyle(color: _white, fontSize: 17, fontWeight: FontWeight.w800)),
              Row(
                children: [
                  const CircleAvatar(radius: 4, backgroundColor: _green),
                  const SizedBox(width: 6),
                  Text('Vehicle Service Advisor',
                      style: TextStyle(color: _grey, fontSize: 12)),
                ],
              ),
            ],
          ),
          const Spacer(),
          // Call expert shortcut in header
          GestureDetector(
            onTap: _callExpert,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _surfaceSunken,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.call_rounded, color: _green, size: 15),
                  const SizedBox(width: 6),
                  Text('Expert',
                      style: TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Close
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: _surface, shape: BoxShape.circle,
                  border: Border.all(color: _border)),
              child: Icon(Icons.close, color: _grey, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChips() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 10),
            child: Text('COMMON ISSUES',
                style: TextStyle(
                    color: _grey, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 2)),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _quickPrompts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => sendMessage(_quickPrompts[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _gold.withOpacity(0.3)),
                  ),
                  child: Text(_quickPrompts[i],
                      style: TextStyle(
                          color: _white, fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => Container(height: 1, color: _border);

  Widget _buildMessageList() {
    return Expanded(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: messages.length + (_isTyping ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (_isTyping && i == messages.length) {
            return _animatedIn(child: _buildTypingIndicator());
          }
          return _animatedIn(child: _buildMessage(messages[i]));
        },
      ),
    );
  }

  /// A short fade + rise-in for each message/typing-bubble as it appears —
  /// small enough not to feel laggy on re-scroll, but enough to make new
  /// replies feel like they're arriving rather than just popping in.
  Widget _animatedIn({required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: c),
      ),
      child: child,
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isUser = msg['isUser'] as bool;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (msg['image'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(msg['image'] as Uint8List,
                    width: 220, height: 160, fit: BoxFit.cover),
              ),
            if (msg['image'] != null &&
                (msg['text'] as String?)?.isNotEmpty == true)
              const SizedBox(height: 6),
            // Advice text and the package recommendation used to be
            // either/or — a category match would return both a 'text'
            // (some advice about the issue) and a 'recommendation', but
            // only the card ever rendered, silently dropping the advice.
            // Now both show, advice first, so the bot actually "says
            // something" instead of just dropping a card.
            if ((msg['text'] as String?)?.isNotEmpty == true)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isUser ? _gold : _surfaceSunken,
                  borderRadius: BorderRadius.circular(20).copyWith(
                    bottomRight: isUser
                        ? const Radius.circular(4)
                        : const Radius.circular(20),
                    bottomLeft: isUser
                        ? const Radius.circular(20)
                        : const Radius.circular(4),
                  ),
                  border: isUser ? null : Border.all(color: _border),
                ),
                child: Text(
                  msg['text'] as String,
                  style: TextStyle(
                      color: isUser ? AppColors.onAccentDark : _white,
                      fontSize: 14, height: 1.5),
                ),
              ),
            if ((msg['text'] as String?)?.isNotEmpty == true && msg['recommendation'] != null)
              const SizedBox(height: 10),
            if (msg['recommendation'] != null)
              _buildRecommendationCard(msg['recommendation']),
            // Suggested follow-up questions the AI proposed for this reply —
            // tapping one sends it as the next message, same as the quick
            // chips shown before the conversation starts.
            if (!isUser && (msg['hints'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (msg['hints'] as List)
                    .cast<String>()
                    .map((hint) => _suggestionChip(hint))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _suggestionChip(String label) {
    return GestureDetector(
      onTap: () => sendMessage(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _gold.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withOpacity(0.35)),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: _gold, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _surfaceSunken,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20), topRight: Radius.circular(20),
            bottomRight: Radius.circular(20), bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TypingDot(delay: 0),
            const SizedBox(width: 5),
            _TypingDot(delay: 200),
            const SizedBox(width: 5),
            _TypingDot(delay: 400),
          ],
        ),
      ),
    );
  }

  // ── Recommendation card ────────────────────────────────────────────────────
  // Redesigned as a clean, labeled stack of package tiles (1-2) rather than
  // a single boxed card — each tile is fully self-contained (category tag,
  // tier badge, tagline, price, duration, features, its own LEARN MORE CTA)
  // so it reads well whether one or two packages come back.
  Widget _buildRecommendationCard(Map<String, dynamic> rec) {
    final packages = (rec['packages'] as List).cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _gold, size: 13),
              const SizedBox(width: 6),
              Text('SUGGESTED FOR YOU',
                  style: TextStyle(
                      color: _gold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            ],
          ),
        ),
        for (var i = 0; i < packages.length; i++) ...[
          _buildPackageTile(
            packages[i],
            tierLabel: packages.length > 1
                ? (i == 0 ? 'RECOMMENDED' : 'MORE COMPREHENSIVE')
                : null,
          ),
          if (i != packages.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildPackageTile(Map<String, dynamic> pkg, {String? tierLabel}) {
    final category = pkg['category'] as String;
    final accent = categoryAccentColor(category);
    final icon = categoryIconFor(category);
    final features = (pkg['features'] as List).cast<String>();
    final shownFeatures = features.take(4).toList();
    final moreCount = features.length - shownFeatures.length;
    final tagline = pkg['tagline'] as String? ?? '';

    // The whole tile opens the package's real screen, not just LEARN MORE —
    // same "tap anywhere on the card" behavior as the Services screen's
    // search results. Material+InkWell (not a bare GestureDetector) so
    // tapping anywhere gives real ripple feedback.
    return Container(
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openPackage(pkg),
          splashColor: accent.withOpacity(0.08),
          highlightColor: accent.withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category tag + tier badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: accent, size: 11),
                          const SizedBox(width: 4),
                          Text(category,
                              style: TextStyle(
                                  color: accent, fontSize: 10, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    if (tierLabel != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _gold.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(tierLabel,
                            style: TextStyle(
                                color: _gold, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // Name + price
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(pkg['name'] as String,
                          style: TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Text(pkg['price'] as String,
                        style: const TextStyle(color: _gold, fontWeight: FontWeight.w900, fontSize: 16)),
                  ],
                ),
                if (tagline.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(tagline,
                      style: TextStyle(color: _grey, fontSize: 12.5, height: 1.4)),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.timer_outlined, color: _grey, size: 13),
                    const SizedBox(width: 4),
                    Text(pkg['duration'] as String,
                        style: TextStyle(color: _grey, fontSize: 12)),
                  ],
                ),
                if (shownFeatures.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      ...shownFeatures.map((f) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.chipBg, borderRadius: BorderRadius.circular(6)),
                            child: Text('✓  $f', style: TextStyle(color: _grey, fontSize: 11)),
                          )),
                      if (moreCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: AppColors.chipBg, borderRadius: BorderRadius.circular(6)),
                          child: Text('+$moreCount more',
                              style: TextStyle(color: _grey, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openPackage(pkg),
                    child: Ink(
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_gold, _goldLight]),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: _gold.withOpacity(0.25),
                              blurRadius: 8, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('LEARN MORE',
                                style: TextStyle(
                                    color: AppColors.onAccentDark,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    letterSpacing: 1)),
                            const SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded,
                                color: AppColors.onAccentDark, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Attached image preview ─────────────────────────────────────────────────
  Widget _buildImagePreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(_attachedImage!,
                width: 52, height: 52, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Photo attached',
                    style: TextStyle(
                        color: _white, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text('Add a description or send as-is',
                    style: TextStyle(color: _grey, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _attachedImage = null),
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                  color: AppColors.chipBg, shape: BoxShape.circle),
              child: Icon(Icons.close, color: _grey, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
          color: _bg, border: Border(top: BorderSide(color: _border))),
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Camera
          GestureDetector(
            onTap: _showImageSourceSheet,
            child: Container(
              width: 44, height: 44,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gold.withOpacity(0.3)),
              ),
              child: const Icon(Icons.add_a_photo_rounded, color: _gold, size: 19),
            ),
          ),
          const SizedBox(width: 10),
          // Text field
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _border)),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(color: _white, fontSize: 14),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Describe your issue...',
                    hintStyle: TextStyle(color: _grey, fontSize: 14),
                  ),
                  onSubmitted: (_) => sendMessage(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Send
          GestureDetector(
            onTap: () => sendMessage(),
            child: Container(
              width: 44, height: 44,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_gold, _goldLight]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _gold.withOpacity(0.3),
                      blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Icon(Icons.send_rounded, color: AppColors.onAccentDark, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated typing dot
// ─────────────────────────────────────────────────────────────────────────────
class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({required this.delay});
  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          color: Color.lerp(
              AppColors.mut, const Color(0xFFD4A017), _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Starting new chat" toast — shown by _AiAdvisorSheetState._startNewChat.
// Self-dismissing: pops itself off after a short hold, no tap needed.
// ─────────────────────────────────────────────────────────────────────────────
class _NewChatToast extends StatefulWidget {
  const _NewChatToast();

  @override
  State<_NewChatToast> createState() => _NewChatToastState();
}

class _NewChatToastState extends State<_NewChatToast> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFD4A017).withOpacity(0.35), blurRadius: 16),
                  ],
                ),
                child: Icon(Icons.auto_awesome_rounded, color: AppColors.onAccentDark, size: 26),
              ),
              const SizedBox(height: 18),
              Text(
                'Starting new chat',
                style: TextStyle(color: AppColors.txt, fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Your previous conversation has been cleared',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
