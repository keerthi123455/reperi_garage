import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';

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
  /// Pass the active vehicle map from HomeScreen so BOOK NOW
  /// can forward vehicleId → PaymentScreen → bookings table.
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
  static const Color _bg         = Color(0xFF080808);
  static const Color _surface    = Color(0xFF111111);
  static const Color _surfaceAlt = Color(0xFF181818);
  static const Color _gold       = Color(0xFFD4A017);
  static const Color _goldLight  = Color(0xFFF5C842);
  static const Color _white      = Color(0xFFFFFFFF);
  static const Color _grey       = Color(0xFF777777);
  static const Color _border     = Color(0xFF222222);
  static const Color _green      = Color(0xFF4CAF50);

  // ── Messages ───────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> messages = [
    {
      'isUser': false,
      'text':
          "Hi 👋 I'm GarageCo AI. Tell me what's wrong with your vehicle — or upload a photo and I'll recommend the right service.",
    }
  ];

  final List<String> _quickPrompts = [
    'Scratch on bumper',
    "Car won't start",
    'AC not cooling',
    'Tyre vibration',
    'Engine noise',
    'Brake squeaking',
  ];

  // ── Catalog data (fetched from Supabase, used by getRecommendation) ──────
  Map<String, Map<String, dynamic>> _catalogByKey = {};
  Map<String, Map<String, dynamic>> _cheapestByCategory = {};

  int _parsePrice(String price) {
    final digitsOnly = price.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digitsOnly) ?? 0;
  }

  Future<void> _fetchCatalogData() async {
    try {
      final rows = await CatalogService.fetchAll();
      if (!mounted) return;

      final byKey = {for (final row in rows) row['key'] as String: row};

      final cheapest = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final category = row['category'] as String;
       final existing = cheapest[category];
        final newPrice = _parsePrice(row['price'] as String);
        final existingPrice = existing == null ? 999999 : _parsePrice(existing['price'] as String);
        if (existing == null || newPrice < existingPrice) {
          cheapest[category] = row;
        }

      setState(() {
        _catalogByKey = byKey;
        _cheapestByCategory = cheapest;
      });
    } }catch (e) {
      // Keep the hardcoded fallback values in getRecommendation if fetch fails.
    } 
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fetchCatalogData();
  }

  @override
  void dispose() {
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

  /// Opens the native phone dialer with the expert number.
  Future<void> _callExpert() async {
    final uri = Uri(scheme: 'tel', path: _expertPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open dialer. Please call +91 93530 94672'),
            backgroundColor: Color(0xFF1A1A1A),
          ),
        );
      }
    }
  }

  /// Navigates to PaymentScreen. Falls back gracefully if no vehicle linked.
  void _bookNow(Map<String, dynamic> pkg) {
    final vehicleId = widget.vehicle?['id']?.toString() ?? '';

    if (vehicleId.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF111111),
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
                const Text(
                  'No vehicle linked',
                  style: TextStyle(
                      color: _white, fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Please add your vehicle from the Profile screen before booking.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF888888), height: 1.5),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text('OK',
                          style: TextStyle(
                              color: Colors.black,
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

    // Close the AI sheet first, then push PaymentScreen
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title:     pkg['name']  as String,
          price:     pkg['price'] as String,
          duration:  pkg['duration'] ?? '60 mins',
          vehicleId: vehicleId,
        ),
      ),
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
            backgroundColor: const Color(0xFF1A1A1A),
          ),
        );
      }
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
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
                    color: Colors.white24,
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
            color: const Color(0xFF1A1A1A),
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
                    style: const TextStyle(
                        color: _white, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(color: _grey, fontSize: 12)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: _grey, size: 14),
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

    await Future.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;

    final rec = getRecommendation(text);
    setState(() {
      _isTyping = false;
      messages.add({'isUser': false, ...rec});
    });
    _scrollToBottom(delayMs: 120);
  }

  // ── Recommendation engine ──────────────────────────────────────────────────
  // Returns a map that either has:
  //   { 'text': '...' }                    → plain text reply
  //   { 'greeting': true, 'text': '...' }  → greeting reply
  //   { 'recommendation': {...} }           → service card reply
  //   { 'fallback': true, 'text': '...' }  → off-topic reply
  Map<String, dynamic> getRecommendation(String query) {
    final q = query.toLowerCase().trim();

    // ── Greetings ────────────────────────────────────────────────────────────
    final greetings = [
      'hi', 'hello', 'hey', 'sup', 'wassup', "what's up", 'whatsup',
      'howdy', 'hiya', 'yo', 'namaste', 'greetings',
    ];
    if (greetings.any((g) => q == g || q.startsWith('$g ') || q.startsWith('$g!'))) {
      return {
        'text':
            "Hey there! 👋 I'm GarageCo AI — here to help with everything about your vehicle. What's going on with your car today?",
      };
    }

    // ── Courtesy / how are you ────────────────────────────────────────────────
    if (q.contains('how are you') || q.contains('how r u') ||
        q == 'fine' || q == 'good' || q == 'ok' || q == 'okay') {
      return {
        'text':
            "I'm running at full horsepower, thanks for asking! 🚗⚡\n\nHow can I help with your vehicle today?",
      };
    }

    // ── Thank you ─────────────────────────────────────────────────────────────
    if (q.contains('thank') || q.contains('thanks') || q == 'ty' || q == 'thx') {
      return {
        'text': "Happy to help! 😊 Let me know if there's anything else your car needs.",
      };
    }

    // ── Car services ──────────────────────────────────────────────────────────
    if (q.contains('scratch') || q.contains('paint') ||
        q.contains('bumper') || q.contains('dent')) {
      return {
        'recommendation': {
          'issue': '🎨 Paint Damage / Surface Scratches',
          'packages': [
            {
              'name': 'Paint Care',
              'price': '${_cheapestByCategory['Paint Care']?['price'] ?? '₹599'} onwards',
              'duration': _cheapestByCategory['Paint Care']?['duration'] ?? '45 mins',
              'features': ['Scratch removal', 'Paint touch-up', 'Color matching', 'Clear coat protection'],
            },
            {
              'name': 'Denting & Tinkering',
              'price': '${_cheapestByCategory['Denting & Tinkering']?['price'] ?? '₹99'} onwards',
              'duration': _cheapestByCategory['Denting & Tinkering']?['duration'] ?? '20 mins',
              'features': ['Dent correction', 'Panel restoration', 'Body alignment', 'Premium finishing'],
            },
          ],
        },
      };
    }

    if (q.contains('tyre') || q.contains('tire') ||
        q.contains('vibration') || q.contains('alignment') ||
        q.contains('steering')) {
      return {
        'recommendation': {
          'issue': '🔧 Wheel / Tyre Issue',
          'packages': [
            {
              'name': 'Tyre Care',
              'price': '${_cheapestByCategory['Tyre Care']?['price'] ?? '₹299'} onwards',
              'duration': _cheapestByCategory['Tyre Care']?['duration'] ?? '20 mins',
              'features': ['Wheel balancing', 'Wheel alignment', 'Tyre pressure check', 'Suspension inspection'],
            },
          ],
        },
      };
    }

    if (q.contains('ac') || q.contains('cool') || q.contains('air condition')) {
      return {
        'recommendation': {
          'issue': '❄️ AC Performance Issue',
          'packages': [
            {
              'name': 'AC Service',
              'price': _catalogByKey['book_ac_service']?['price'] ?? '₹2499',
              'duration': _catalogByKey['book_ac_service']?['duration'] ?? '2 hrs',
              'features': ['Gas pressure check', 'Cooling efficiency test', 'AC vent cleaning', 'Filter replacement'],
            },
            {
              'name': '21 Step Inspection',
              'price': _catalogByKey['21_step_inspection']?['price'] ?? '₹599',
              'duration': _catalogByKey['21_step_inspection']?['duration'] ?? '45 mins',
              'features': ['Compressor inspection', 'Electrical check', 'Leak detection', 'Vehicle health report'],
            },
          ],
        },
      };
    }

    if (q.contains('brake') || q.contains('squeak') || q.contains('braking')) {
      return {
        'recommendation': {
          'issue': '🛑 Brake System Issue',
          'packages': [
            {
              'name': 'Brake Inspection',
              'price': _catalogByKey['brake_inspection']?['price'] ?? '₹699',
              'duration': _catalogByKey['brake_inspection']?['duration'] ?? '30 mins',
              'features': ['Brake pad inspection', 'Disc rotor check', 'Brake fluid check', 'Road safety inspection'],
            },
          ],
        },
      };
    }

    if (q.contains('battery') || q.contains('start') || q.contains("won't start")) {
      return {
        'recommendation': {
          'issue': '🔋 Battery / Starting Issue',
          'packages': [
            {
              'name': 'Battery Health Check',
              'price': _catalogByKey['battery_health_check']?['price'] ?? '₹399',
              'duration': _catalogByKey['battery_health_check']?['duration'] ?? '20 mins',
              'features': ['Battery voltage test', 'Charging system test', 'Alternator inspection', 'Terminal cleaning'],
            },
          ],
        },
      };
    }

    if (q.contains('engine') || q.contains('noise') ||
        q.contains('pickup') || q.contains('power') ||
        q.contains('book service') || q.contains('general service') ||
        q.contains('maintenance')) {
      return {
        'recommendation': {
          'issue': '⚙️ Engine Performance Issue',
          'packages': [
            {
              'name': 'Book Service',
              'price': '${_cheapestByCategory['Book Service']?['price'] ?? '₹1499'} onwards',
              'duration': _cheapestByCategory['Book Service']?['duration'] ?? '45 mins',
              'features': ['Engine oil replacement', 'Filter replacement', 'Fluid top-up', 'Engine diagnostics'],
            },
            {
              'name': '21 Step Inspection',
              'price': _catalogByKey['21_step_inspection']?['price'] ?? '₹599',
              'duration': _catalogByKey['21_step_inspection']?['duration'] ?? '45 mins',
              'features': ['Engine health check', 'Leak inspection', 'Battery check', 'Brake inspection'],
            },
          ],
        },
      };
    }

    if (q.contains('accident') || q.contains('crash') || q.contains('hit')) {
      return {
        'recommendation': {
          'issue': '🚨 Accident Damage',
          'packages': [
            {
              'name': 'Denting & Tinkering',
              'price': '${_cheapestByCategory['Denting & Tinkering']?['price'] ?? '₹99'} onwards',
              'duration': _cheapestByCategory['Denting & Tinkering']?['duration'] ?? '20 mins',
              'features': ['Panel replacement', 'Body repair', 'Dent removal', 'Paint restoration'],
            },
          ],
        },
      };
    }

    if (q.contains('wash') || q.contains('clean') || q.contains('dirty')) {
      return {
        'recommendation': {
          'issue': '🚿 Vehicle Cleaning',
          'packages': [
            {
              'name': 'Car Spa',
              'price': _catalogByKey['car_spa_quick_refresh']?['price'] ?? '₹399',
              'duration': _catalogByKey['car_spa_quick_refresh']?['duration'] ?? '30 mins',
              'features': ['Exterior wash', 'Interior vacuum', 'Dashboard cleaning', 'Tyre dressing'],
            },
          ],
        },
      };
    }

    // ── Off-topic / fallback ──────────────────────────────────────────────────
    // Check if it looks vehicle-related at all
    final vehicleKeywords = [
      'car', 'vehicle', 'auto', 'motor', 'wheel', 'drive', 'fuel',
      'petrol', 'diesel', 'gear', 'clutch', 'exhaust', 'headlight',
      'wiper', 'mirror', 'door', 'window', 'seat', 'hood', 'boot',
    ];
    final isVehicleRelated = vehicleKeywords.any((kw) => q.contains(kw));

    if (!isVehicleRelated) {
      return {
        'fallback': true,
        'text':
            "I can't help with that, but I'm great with anything car-related! Here's what I can help you with:",
      };
    }

    // Generic vehicle query → 21-step inspection
    return {
      'recommendation': {
        'issue': '🔍 General Vehicle Inspection',
        'packages': [
          {
            'name': '21 Step Inspection',
            'price': _catalogByKey['21_step_inspection']?['price'] ?? '₹599',
            'duration': _catalogByKey['21_step_inspection']?['duration'] ?? '45 mins',
            'features': ['Engine inspection', 'Brake inspection', 'Battery health check', 'Complete vehicle report'],
          },
        ],
      },
    };
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: const BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
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
        ),
      ),
    );
  }

  Widget _buildHandle() => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Container(
          width: 44, height: 4,
          decoration: BoxDecoration(
              color: Colors.white12, borderRadius: BorderRadius.circular(2)),
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
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('GarageCo AI',
                  style: TextStyle(color: _white, fontSize: 17, fontWeight: FontWeight.w800)),
              Row(
                children: [
                  const CircleAvatar(radius: 4, backgroundColor: _green),
                  const SizedBox(width: 6),
                  const Text('Vehicle Service Advisor',
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
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.call_rounded, color: _green, size: 15),
                  SizedBox(width: 6),
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
              child: const Icon(Icons.close, color: _grey, size: 16),
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
          const Padding(
            padding: EdgeInsets.only(left: 20, bottom: 10),
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
                      style: const TextStyle(
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
          if (_isTyping && i == messages.length) return _buildTypingIndicator();
          return _buildMessage(messages[i]);
        },
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isUser = msg['isUser'] as bool;

    // ── Fallback (off-topic) message ─────────────────────────────────────────
    if (!isUser && msg['fallback'] == true) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4), topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20),
                  ),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  msg['text'] as String,
                  style: const TextStyle(color: _white, fontSize: 14, height: 1.5),
                ),
              ),
              const SizedBox(height: 10),
              // Suggestion chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _suggestionChip('🔧 Book Service'),
                  _suggestionChip('🎨 Denting & Paint'),
                  _suggestionChip('❄️ AC Service'),
                  _suggestionChip('🛑 Brake Check'),
                  _suggestionChip('🔋 Battery Issue'),
                  _suggestionChip('🚿 Car Spa'),
                ],
              ),
            ],
          ),
        ),
      );
    }

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
            if (msg['recommendation'] != null)
              _buildRecommendationCard(msg['recommendation'])
            else if ((msg['text'] as String?)?.isNotEmpty == true)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isUser ? _gold : const Color(0xFF141414),
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
                      color: isUser ? Colors.black : _white,
                      fontSize: 14, height: 1.5),
                ),
              ),
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
          color: const Color(0xFF141414),
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
  Widget _buildRecommendationCard(Map<String, dynamic> rec) {
    final packages = rec['packages'] as List;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4), topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20),
        ),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Issue header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4), topRight: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: _gold.withOpacity(0.15))),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: _gold, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(rec['issue'] as String,
                      style: const TextStyle(
                          color: _gold, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ],
            ),
          ),
          // Package tiles
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: packages
                  .map<Widget>((pkg) => _buildPackageTile(pkg as Map<String, dynamic>))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageTile(Map<String, dynamic> pkg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + price
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(pkg['name'] as String,
                      style: const TextStyle(
                          color: _white, fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: _gold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(pkg['price'] as String,
                      style: const TextStyle(
                          color: _gold, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ],
            ),
          ),

          // Duration
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: _grey, size: 13),
                const SizedBox(width: 4),
                Text(pkg['duration'] as String,
                    style: const TextStyle(color: _grey, fontSize: 12)),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Feature chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(
              spacing: 6, runSpacing: 6,
              children: (pkg['features'] as List<String>)
                  .map((f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text('✓  $f',
                            style: const TextStyle(
                                color: Color(0xFFAAAAAA), fontSize: 11)),
                      ))
                  .toList(),
            ),
          ),

          const SizedBox(height: 14),

          // ── CTA row: BOOK NOW  +  CALL EXPERT ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                // BOOK NOW → PaymentScreen
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () => _bookNow(pkg),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_gold, _goldLight]),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: _gold.withOpacity(0.28),
                              blurRadius: 10, offset: const Offset(0, 4))
                        ],
                      ),
                      child: const Center(
                        child: Text('BOOK NOW',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 1)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // CALL EXPERT → phone dialer
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _callExpert,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _green.withOpacity(0.35)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.call_rounded, color: _green, size: 15),
                          SizedBox(width: 6),
                          Text('CALL',
                              style: TextStyle(
                                  color: _green,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  letterSpacing: 0.8)),
                        ],
                      ),
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
              children: const [
                Text('Photo attached',
                    style: TextStyle(
                        color: _white, fontWeight: FontWeight.w600, fontSize: 13)),
                SizedBox(height: 2),
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
                  color: Colors.white.withOpacity(0.06), shape: BoxShape.circle),
              child: const Icon(Icons.close, color: _grey, size: 14),
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
                  style: const TextStyle(color: _white, fontSize: 14),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Describe your issue...',
                    hintStyle: TextStyle(color: Color(0xFF444444), fontSize: 14),
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
              child: const Icon(Icons.send_rounded, color: Colors.black, size: 18),
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
  }

  @override
  void dispose() {
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
              const Color(0xFF444444), const Color(0xFFD4A017), _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}