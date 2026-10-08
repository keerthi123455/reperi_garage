import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/ask_ai_button.dart';
import '../widgets/bottom_nav_actions.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/emergency_status_banner.dart';
import 'book_service_screen.dart';
import 'car_spa_screen.dart';
import 'denting_tinkering_screen.dart';
import 'detailing_packages_screen.dart';
import 'fleet_management_screen.dart';
import 'claim_screen.dart';
import 'paint_care_package_screen.dart';
import 'paint_care_screen.dart';
import 'payment_screen.dart';
import 'roadside_assistance_screen.dart';
import 'servicing_package_screen.dart';
import 'monthly_wash_screen.dart';
import 'tyre_care_screen.dart';
import 'washing_package_screen.dart';
import 'wheel_management_package_screen.dart';
import '../services/catalog_service.dart';
import '../widgets/catalog_gate.dart';

const String _expertPhone = '9353094672';

/// Builds the "More Details" / "Book Now" destination screen for a
/// [_Package], given the account's active vehicle (may be null).
/// `highlightPackage`, when set, is that exact package's name — the
/// destination screen scrolls to it and selects/opens it on load instead
/// of just landing on the screen generally.
typedef _ScreenBuilder = Widget Function(Map<String, dynamic>? vehicle, {String? highlightPackage});

/// One bookable line item in the unified catalog — every tier from every
/// package screen in the app (Servicing, Washing, Wheel Management, Paint
/// Care Package, Tyre Care, Book Service, Paint Care, Denting & Tinkering,
/// Car Spa, Detailing, Claim Assistance, Monthly Wash, Roadside Assistance),
/// flattened so it's all searchable and browsable from one screen.
class _Package {
  final String key;
  final String category;
  final String name;
  final String price;
  final String duration;
  final String tagline;
  final List<String> features;
  final bool popular;
  final bool comingSoon;
  final bool vehicleRequired;
  // Whether "Book Now" can jump straight to PaymentScreen with this
  // package's price — false for packages whose real cost depends on a
  // choice only their own screen can make (vehicle type, a quote after
  // inspection, a claim with no fixed price).
  final bool directBook;
  final _ScreenBuilder screenBuilder;

  const _Package({
    required this.key,
    required this.category,
    required this.name,
    required this.price,
    required this.duration,
    required this.tagline,
    required this.features,
    required this.screenBuilder,
    this.popular = false,
    this.comingSoon = false,
    this.vehicleRequired = true,
    this.directBook = true,
  });
}

/// A [_Package] that matched a search, plus the specific feature(s) that
/// matched so the card can show *why* it's relevant instead of just its
/// generic tagline — this is what was missing when searching "oil change"
/// used to surface "Essential" with no mention of oil anywhere on the card.
class _SearchHit {
  final _Package package;
  final List<String> matchedFeatures;
  final double score;
  const _SearchHit(this.package, this.matchedFeatures, this.score);
}

const Map<String, Color> _kCategoryAccent = {
  'Periodic Servicing': Color(0xFF4FA3E3),
  'Car Wash & Cleaning': Color(0xFF26C6DA),
  'Wheels & Tyres': Color(0xFFFF8A65),
  'Paint & Body': Color(0xFFBA68C8),
  'Premium Detailing': Color(0xFFD4A017),
  'Claim Assistance': Color(0xFF66BB6A),
  'Monthly Wash': Color(0xFFFFB74D),
  'Roadside Assistance': Color(0xFFEF5350),
  'Business Solutions': Color(0xFF90A4AE),
};

const Map<String, IconData> _kCategoryIcon = {
  'Periodic Servicing': Icons.build_rounded,
  'Car Wash & Cleaning': Icons.local_car_wash_rounded,
  'Wheels & Tyres': Icons.tire_repair_rounded,
  'Paint & Body': Icons.format_paint_rounded,
  'Premium Detailing': Icons.auto_awesome_rounded,
  'Claim Assistance': Icons.verified_user_rounded,
  'Monthly Wash': Icons.subscriptions_rounded,
  'Roadside Assistance': Icons.support_agent_rounded,
  'Business Solutions': Icons.business_rounded,
};

const List<String> _kCategoryOrder = [
  'Periodic Servicing',
  'Car Wash & Cleaning',
  'Wheels & Tyres',
  'Paint & Body',
  'Premium Detailing',
  'Claim Assistance',
  'Monthly Wash',
  'Roadside Assistance',
  'Business Solutions',
];

// ── Search ────────────────────────────────────────────────────────────
// The old search only matched if the *exact typed phrase* appeared
// somewhere (e.g. "brake fail" would never match a feature called "Brake
// inspection" since "brake fail" isn't a substring of it). Real users —
// especially older ones less familiar with app search — type symptoms in
// their own words, plural or singular, sometimes misspelled ("brake
// fail", "car not starting", "tyres", "olie chnage"), not the exact
// package wording. So search now:
//   1. splits the query into words and matches each one independently,
//   2. expands everyday words into the service-catalog terms they mean
//      (a large, ever-growing dictionary below — not just a handful of
//      phrases someone happened to test),
//   3. tries the singular form of plurals ("tyres" → "tyre"),
//   4. and falls back to fuzzy (typo-tolerant) matching against every
//      word that actually appears in the catalog, so even a misspelled
//      or unlisted word still finds the closest relevant package instead
//      of nothing at all.
const Set<String> _kSearchStopWords = {
  'a', 'an', 'the', 'is', 'my', 'me', 'i', 'to', 'of', 'in', 'on', 'for',
  'and', 'or', 'not', 'no', 'it', 'car', 'please', 'need', 'want', 'have',
  'has', 'with', 'issue', 'problem', 'help', 'why', 'what', 'how', 'doing',
  'im', 'am', 'are', 'this', 'that', 'some', 'any', 'get', 'getting',
};

// Everyday words and car-part/symptom names → the terms actually used in
// the catalog. Lets someone search how a problem *feels*, or name a part
// in plain language, and still land on the closest relevant package —
// covering far more than oil/brake/paint so "anything people put" has a
// real shot at finding something.
const Map<String, List<String>> _kSearchSynonyms = {
  // Symptoms
  'fail': ['brake', 'battery'],
  'failing': ['brake', 'battery'],
  'failed': ['brake', 'battery'],
  'start': ['battery', 'engine'],
  'starting': ['battery', 'engine'],
  'dead': ['battery'],
  'jump': ['battery', 'roadside'],
  'jumpstart': ['battery', 'roadside'],
  'noise': ['engine', 'diagnostic'],
  'noisy': ['engine', 'diagnostic'],
  'sound': ['engine', 'diagnostic'],
  'sounds': ['engine', 'diagnostic'],
  'smoke': ['engine'],
  'smoking': ['engine'],
  'overheat': ['engine', 'ac'],
  'overheating': ['engine', 'ac'],
  'heating': ['engine', 'ac'],
  'hot': ['ac', 'cooling'],
  'cool': ['ac', 'cooling'],
  'cooling': ['ac'],
  'shake': ['balancing', 'alignment'],
  'shaking': ['balancing', 'alignment'],
  'vibration': ['balancing', 'alignment'],
  'vibrating': ['balancing', 'alignment'],
  'pull': ['alignment'],
  'pulling': ['alignment'],
  'scratch': ['paint', 'polish'],
  'scratches': ['paint', 'polish'],
  'scratched': ['paint', 'polish'],
  'fade': ['paint', 'polish'],
  'faded': ['paint', 'polish'],
  // No 'change'/'replace' → 'replacement' entry here on purpose: those
  // words already literally appear inside features like "Engine Oil
  // Change" and "Air Filter Replacement" ("replace" is even a literal
  // substring of "replacement"), so they match directly. Mapping them to
  // the single generic word "replacement" used to flood totally
  // unrelated queries (e.g. "windshield change") with servicing results
  // just because "replacement" appears in a dozen unrelated features.
  'dent': ['dent'],
  'dents': ['dent'],
  'dented': ['dent'],
  'rust': ['rust'],
  'rusting': ['rust'],
  'rusted': ['rust'],
  'leak': ['oil', 'ac', 'coolant'],
  'leaking': ['oil', 'ac', 'coolant'],
  'puncture': ['tyre'],
  'punctured': ['tyre'],
  'flat': ['tyre', 'roadside'],
  'break': ['brake'],
  'breaks': ['brake'],
  'breakdown': ['roadside', 'battery'],
  'stuck': ['alignment', 'suspension'],
  'accident': ['accident', 'dent', 'insurance'],
  'damage': ['dent', 'paint', 'insurance'],
  'damaged': ['dent', 'paint', 'insurance'],
  'shine': ['polish', 'wax', 'wash'],
  'shiny': ['polish', 'wax', 'wash'],
  'dull': ['polish', 'paint'],
  'smell': ['odour', 'sanitization'],
  'smelly': ['odour', 'sanitization'],
  'dirty': ['wash', 'clean'],
  'sticky': ['wash', 'clean', 'sanitization'],
  'squeak': ['brake', 'suspension'],
  'squeaking': ['brake', 'suspension'],
  'grinding': ['brake', 'suspension'],
  'wobble': ['balancing', 'alignment'],
  'wobbling': ['balancing', 'alignment'],
  'bumpy': ['suspension', 'alignment'],
  'hard': ['alignment', 'suspension'],
  'stiff': ['alignment', 'suspension'],
  'tight': ['alignment', 'suspension'],
  'tighten': ['alignment', 'suspension'],
  'heavy': ['alignment', 'suspension'],
  'loose': ['alignment', 'suspension'],
  'slow': ['brake', 'engine'],
  'slipping': ['brake', 'balancing'],
  'burning': ['brake', 'engine'],
  'warning': ['diagnostic'],
  'light': ['diagnostic'],
  'lights': ['diagnostic'],
  'error': ['diagnostic'],
  'sensor': ['diagnostic'],
  'mileage': ['diagnostic', 'engine'],
  'fuel': ['diagnostic', 'engine'],
  'efficiency': ['diagnostic', 'engine'],
  'performance': ['diagnostic', 'engine'],
  'pickup': ['diagnostic', 'engine'],
  // Parts & systems
  'brakes': ['brake'],
  'engine': ['engine'],
  'tyre': ['tyre'],
  'tyres': ['tyre'],
  'tire': ['tyre'],
  'tires': ['tyre'],
  'wheel': ['wheel', 'alignment'],
  'wheels': ['wheel', 'alignment'],
  'alloy': ['alloy', 'wheel'],
  'alloys': ['alloy', 'wheel'],
  'battery': ['battery'],
  'batteries': ['battery'],
  'clutch': ['engine', 'diagnostic'],
  'gear': ['engine', 'diagnostic'],
  'gears': ['engine', 'diagnostic'],
  'gearbox': ['engine', 'diagnostic'],
  'transmission': ['engine', 'diagnostic'],
  'steering': ['alignment', 'suspension'],
  'suspension': ['suspension'],
  'shocker': ['suspension'],
  'shockers': ['suspension'],
  'exhaust': ['engine', 'diagnostic'],
  'silencer': ['engine', 'diagnostic'],
  'radiator': ['ac', 'engine'],
  'coolant': ['ac', 'coolant'],
  'electrical': ['diagnostic'],
  'electric': ['diagnostic'],
  'wiring': ['diagnostic'],
  'horn': ['diagnostic'],
  // "wash" was dropped from wiper/window on purpose: "wash" is such a
  // common word across the catalog (it's in nearly every wash package's
  // features) that it drowned out the more relevant diagnostics result
  // for a malfunction complaint like "window issue".
  'wiper': ['diagnostic'],
  'wipers': ['diagnostic'],
  'window': ['diagnostic'],
  'windows': ['diagnostic'],
  'lock': ['diagnostic'],
  'locking': ['diagnostic'],
  'key': ['diagnostic'],
  'remote': ['diagnostic'],
  'windshield': ['glass'],
  'windscreen': ['glass'],
  'mirror': ['glass', 'wash'],
  'mirrors': ['glass', 'wash'],
  'bumper': ['dent', 'paint'],
  'panel': ['dent', 'paint'],
  'body': ['dent', 'paint'],
  'seat': ['wash', 'clean'],
  'seats': ['wash', 'clean'],
  'upholstery': ['wash', 'clean'],
  'interior': ['wash', 'clean', 'vacuum'],
  'ac': ['ac'],
  'aircon': ['ac'],
  'compressor': ['ac'],
  'insurance': ['insurance'],
  'claim': ['insurance'],
  'subscription': ['subscription'],
  'monthly': ['subscription'],
  'towing': ['roadside', 'towing'],
  'tow': ['roadside', 'towing'],
  'stranded': ['roadside'],
  'coating': ['coating', 'ceramic'],
  'wrap': ['wrap'],
  'film': ['film', 'ppf'],
  'polish': ['polish'],
  'polishing': ['polish'],
  'wash': ['wash'],
  'washing': ['wash'],
  'clean': ['wash', 'clean'],
  'cleaning': ['wash', 'clean'],
  'detailing': ['detailing'],
  'detail': ['detailing'],
};

// These builders used to force-unwrap the active vehicle (`v!`), which
// only worked because ServicesScreen refused to call them at all without
// one. Package tiers and features should be browsable with no vehicle
// yet — each of these screens only actually reads the vehicle id at the
// moment its own "Book Now" reaches PaymentScreen, which now prompts to
// add a vehicle right there if it's missing — so browsing here just
// falls back to an empty id/map instead of blocking navigation.
Widget _bookService(Map<String, dynamic>? v, {String? highlightPackage}) =>
    BookServiceScreen(vehicle: v ?? const {'id': ''}, highlightPackage: highlightPackage);
Widget _servicingPkg(Map<String, dynamic>? v, {String? highlightPackage}) =>
    ServicingPackageScreen(vehicleId: v?['id']?.toString() ?? '', highlightPackage: highlightPackage);
Widget _washingPkg(Map<String, dynamic>? v, {String? highlightPackage}) =>
    WashingPackageScreen(vehicleId: v?['id']?.toString() ?? '', highlightPackage: highlightPackage);
Widget _carSpa(Map<String, dynamic>? v, {String? highlightPackage}) =>
    CarSpaScreen(vehicle: v ?? const {'id': ''}, highlightPackage: highlightPackage);
Widget _wheelPkg(Map<String, dynamic>? v, {String? highlightPackage}) =>
    WheelManagementPackageScreen(vehicleId: v?['id']?.toString() ?? '', highlightPackage: highlightPackage);
Widget _tyreCare(Map<String, dynamic>? v, {String? highlightPackage}) =>
    TyreCareScreen(vehicle: v ?? const {'id': ''}, highlightPackage: highlightPackage);
Widget _paintPkg(Map<String, dynamic>? v, {String? highlightPackage}) =>
    PaintCarePackageScreen(vehicleId: v?['id']?.toString() ?? '', highlightPackage: highlightPackage);
Widget _paintCare(Map<String, dynamic>? v, {String? highlightPackage}) =>
    PaintCareScreen(vehicle: v ?? const {'id': ''}, highlightPackage: highlightPackage);
Widget _denting(Map<String, dynamic>? v, {String? highlightPackage}) =>
    DentingTinkeringScreen(vehicle: v ?? const {'id': ''}, highlightPackage: highlightPackage);
Widget _detailing(Map<String, dynamic>? v, {String? highlightPackage}) =>
    DetailingPackagesScreen(highlightPackage: highlightPackage);
Widget _claim(Map<String, dynamic>? v, {String? highlightPackage}) => ClaimScreen(
      vehicleId: v?['id']?.toString() ?? '',
      carModel: (v?['car_model'] ?? '').toString(),
      carBrand: (v?['car_brand'] ?? '').toString(),
      carNumber: (v?['car_number'] ?? '').toString(),
      highlightPackage: highlightPackage,
    );
Widget _subscriptions(Map<String, dynamic>? v, {String? highlightPackage}) =>
    MonthlyWashScreen(vehicleId: v?['id']?.toString() ?? '', highlightPackage: highlightPackage);
Widget _roadside(Map<String, dynamic>? v, {String? highlightPackage}) =>
    RoadsideAssistanceScreen(highlightPackage: highlightPackage);
Widget _fleetMgmt(Map<String, dynamic>? v, {String? highlightPackage}) =>
    FleetManagementScreen(highlightPackage: highlightPackage);

/// The full catalog — every tier from every package screen in the app.
/// Which package screen each service opens, keyed by the first entry of
/// its `screens` column in the services table.
const Map<String, _ScreenBuilder> _kScreenBuilders = {
  'book_service': _bookService,
  'servicing': _servicingPkg,
  'washing': _washingPkg,
  'car_spa': _carSpa,
  'wheel': _wheelPkg,
  'tyre_care': _tyreCare,
  'paint_package': _paintPkg,
  'paint_care': _paintCare,
  'denting': _denting,
  'detailing': _detailing,
  'claim': _claim,
  'monthly_wash': _subscriptions,
  'roadside': _roadside,
  'fleet_management': _fleetMgmt,
};

/// Screens whose packages need a choice made on their own screen first
/// (documents, a plan, a slot) — never booked straight from this catalog.
const Set<String> _kOpenScreenFirst = {'claim', 'monthly_wash', 'inspection'};

/// The full catalog — every package with show_in_catalog = true in the
/// Supabase `services` table, so names, prices and features here always
/// match the package screens (one row, one price). Same objects until the
/// catalog changes.
List<_Package>? _kCatalogCache;
int _kCatalogRevision = -1;
List<_Package> get _kCatalog {
  if (_kCatalogCache == null || _kCatalogRevision != CatalogService.revision.value) {
    _kCatalogCache = [
      for (final item in CatalogService.catalog())
        if (item.category != null &&
            item.screens.isNotEmpty &&
            _kScreenBuilders.containsKey(item.screens.first))
          _Package(
            key: item.key,
            category: item.category!,
            name: item.name,
            price: item.priceText,
            duration: item.duration,
            tagline: item.tagline,
            features: item.features,
            screenBuilder: _kScreenBuilders[item.screens.first]!,
            popular: item.popular,
            comingSoon: item.detailBool('coming_soon'),
            vehicleRequired: item.vehicleRequired,
            directBook: item.isDirectlyPayable && !_kOpenScreenFirst.contains(item.screens.first),
          ),
    ];
    _kCatalogRevision = CatalogService.revision.value;
    _kCatalogVocabularyCache = null;
  }
  return _kCatalogCache!;
}

// ── Public catalog access for other screens ─────────────────────────────────
// `_kCatalog`/`_Package` are file-private, so these two top-level functions
// are the only way another screen (namely the AI advisor sheet) can see
// what's actually in it — keeping one single source of truth for "every
// package in the app" instead of a second, separately maintained list that
// can drift out of sync with what this screen actually shows and searches.

/// A plain, serializable view of every real, bookable package in the app —
/// used by the AI advisor to recommend from the exact same catalog this
/// screen searches over, instead of guessing from a smaller hardcoded list.
/// Coming-soon packages are excluded since they can't actually be booked.
List<Map<String, dynamic>> exportPackageCatalogForAi() {
  return _kCatalog
      .where((p) => !p.comingSoon && p.price.isNotEmpty)
      .map((p) => {
            'category': p.category,
            'name': p.name,
            'price': p.price,
            'duration': p.duration,
            'tagline': p.tagline,
            'features': p.features,
          })
      .toList();
}

/// Opens the exact same screen this catalog would send this package to —
/// looked up by category+name, the same pair returned by
/// [exportPackageCatalogForAi] — so a package recommended elsewhere in the
/// app (the AI advisor) always lands on the real screen for it, not a
/// guess based on matching words in its name. Returns null if no package
/// matches (e.g. stale data), letting the caller fall back gracefully.
Widget? buildPackageScreenFor(String category, String name, Map<String, dynamic>? vehicle) {
  for (final p in _kCatalog) {
    if (p.category == category && p.name == name) {
      return p.screenBuilder(vehicle, highlightPackage: name);
    }
  }
  return null;
}

/// This screen's own category accent color — exposed so anything showing a
/// package by category (the AI advisor's package cards) can tag it with
/// the same color used here, instead of picking its own.
Color categoryAccentColor(String category) =>
    _kCategoryAccent[category] ?? AppColors.mut;

/// This screen's own category icon, for the same reason.
IconData categoryIconFor(String category) =>
    _kCategoryIcon[category] ?? Icons.build_circle_outlined;

// Every distinct word (3+ letters) appearing anywhere in the catalog —
// built once, lazily, the first time search is used. This is the
// dictionary fuzzy matching checks a typed word against, so a typo like
// "olie" or "brek" still lands on "oil" / "brake" instead of nothing.
Set<String>? _kCatalogVocabularyCache;
Set<String> get _kCatalogVocabulary {
  final catalog = _kCatalog; // rebuilds (and clears the cache) on catalog changes
  final cached = _kCatalogVocabularyCache;
  if (cached != null) return cached;
  final words = <String>{};
  final wordPattern = RegExp(r'[a-z]+');
  for (final pkg in catalog) {
    for (final text in [pkg.name, pkg.category, pkg.tagline, ...pkg.features]) {
      for (final match in wordPattern.allMatches(text.toLowerCase())) {
        final w = match.group(0)!;
        if (w.length >= 3) words.add(w);
      }
    }
  }
  return _kCatalogVocabularyCache = words;
}

// Words so generic they appear in nearly every package ("check",
// "inspection", "cleaning", "change"...). Two problems come from that:
//   1. Fuzzy typo-matching against one of these by spelling alone is more
//      likely coincidence than intent (e.g. "crack" is only 2 edits from
//      "check"), so fuzzy matching skips them entirely.
//   2. Someone typing one of these words outright ("windshield change")
//      would otherwise have it outscore a rarer, far more specific word
//      in the same query ("glass") just because it happens to also
//      appear in a couple of unrelated oil-change features — so ranking
//      gives them a fixed discount instead of full weight.
// They're still fully searchable if someone types them outright — just
// not allowed to drown out a more specific word in the same search.
const Set<String> _kGenericCatalogWords = {
  'check', 'checks', 'inspection', 'cleaning', 'clean', 'quality',
  'final', 'complete', 'everything', 'package', 'service', 'services',
  'premium', 'free', 'point', 'report', 'level', 'system', 'digital',
  'health', 'basic', 'full', 'advanced', 'general', 'change', 'changed',
  'changing', 'replace', 'replacement', 'replacements',
};

/// Naive English singularizer — good enough to turn "tyres"/"brakes"/
/// "batteries" back into words that actually appear in the catalog
/// without needing a plural entry for every single one.
String _singularize(String word) {
  if (word.length > 4 && word.endsWith('ies')) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.length > 4 && word.endsWith('ses')) {
    return word.substring(0, word.length - 2);
  }
  if (word.length > 4 && word.endsWith('es')) {
    return word.substring(0, word.length - 2);
  }
  if (word.length > 3 && word.endsWith('s') && !word.endsWith('ss')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

/// Classic edit-distance — counts the single-character insertions,
/// deletions or substitutions needed to turn [a] into [b]. Used to find
/// the catalog word closest to a misspelled search term.
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final deletion = curr[j - 1] + 1;
      final insertion = prev[j] + 1;
      final substitution = prev[j - 1] + cost;
      curr[j] = [deletion, insertion, substitution].reduce((x, y) => x < y ? x : y);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// Finds catalog words close enough to [word] to be a likely typo of it,
/// so search still works even for a word we never explicitly listed as a
/// synonym and that doesn't literally appear anywhere in the catalog.
Set<String> _fuzzyCatalogMatches(String word) {
  if (word.length < 3) return const {};
  final maxDistance = word.length <= 4 ? 1 : (word.length <= 7 ? 2 : 3);
  final matches = <String>{};
  for (final vocabWord in _kCatalogVocabulary) {
    if (_kGenericCatalogWords.contains(vocabWord)) continue;
    if ((vocabWord.length - word.length).abs() > maxDistance) continue;
    if (_levenshtein(word, vocabWord) <= maxDistance) matches.add(vocabWord);
  }
  return matches;
}

class ServicesScreen extends StatefulWidget {
  final Map<String, dynamic>? activeVehicle;

  /// When true, the search field grabs focus (and pops the keyboard open)
  /// as soon as this screen appears — used by the home screen's search
  /// icon, which should land the user ready to type immediately instead
  /// of just showing the catalog.
  final bool autoFocusSearch;

  const ServicesScreen({super.key, this.activeVehicle, this.autoFocusSearch = false});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  static const Color _gold = Color(0xFFD4A017);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    if (widget.autoFocusSearch) {
      // Requested after the first frame — the focus system isn't ready
      // to hand focus to a not-yet-laid-out field during initState itself.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // The catalog view shown when nothing is being searched.
  List<_Package> get _filtered => _searchQuery.isEmpty ? _kCatalog : const [];

  /// Search terms for the current query, mapped to a confidence tier
  /// (1 = primary, 0 = fuzzy fallback). Primary terms are the words the
  /// user actually typed (stopwords removed), their singular forms
  /// ("tyres" → "tyre"), the everyday-language synonyms expanded from
  /// either form (e.g. "brake fail" → {brake, fail, battery}), and the
  /// full phrase itself (so an exact match like "car wash" scores
  /// highest). Fuzzy terms are, for any word that still isn't recognised
  /// anywhere, the closest catalog word by spelling — kept separate and
  /// scored lower so a typo guess never outranks something the user
  /// actually meant.
  Map<String, int> get _searchTerms {
    if (_searchQuery.isEmpty) return const {};
    final words = _searchQuery
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !_kSearchStopWords.contains(w))
        .toSet();
    final terms = <String, int>{};
    void addPrimary(String t) => terms[t] = 1;
    void addFuzzy(String t) => terms.putIfAbsent(t, () => 0);
    if (_searchQuery.length >= 2) addPrimary(_searchQuery);
    for (final w in words) {
      addPrimary(w);
      final singular = _singularize(w);
      addPrimary(singular);
      final synonyms = _kSearchSynonyms[w] ?? _kSearchSynonyms[singular];
      var recognised = synonyms != null;
      if (synonyms != null) {
        for (final s in synonyms) {
          addPrimary(s);
        }
      }
      if (_kCatalogVocabulary.contains(w) || _kCatalogVocabulary.contains(singular)) {
        recognised = true;
      }
      // This word means nothing to the catalog on its own — it might be
      // a typo of a word that does (e.g. "olie" meant "oil"). Look for
      // the closest real catalog word instead of giving up on it, but
      // mark it low-confidence so it only ever fills in gaps.
      if (!recognised) {
        for (final f in _fuzzyCatalogMatches(w)) {
          addFuzzy(f);
        }
      }
    }
    return terms;
  }

  /// Every package that matches at least one search term, ranked by
  /// relevance (name matches count most, then features, then category and
  /// tagline; a term found only via typo-guessing counts for much less,
  /// and an overly generic catalog word counts for less too, so it can't
  /// bury a rarer, more specific word from the same search), each
  /// carrying the specific feature(s) that matched so the UI can show
  /// exactly why it was suggested.
  List<_SearchHit> get _searchHits {
    final terms = _searchTerms;
    if (terms.isEmpty) return const [];
    final hits = <_SearchHit>[];
    for (final pkg in _kCatalog) {
      double score = 0;
      final matched = <String>{};
      final name = pkg.name.toLowerCase();
      final category = pkg.category.toLowerCase();
      final tagline = pkg.tagline.toLowerCase();
      for (final entry in terms.entries) {
        final term = entry.key;
        final isPrimary = entry.value == 1;
        final genericPenalty = _kGenericCatalogWords.contains(term) ? 0.3 : 1.0;
        if (name.contains(term)) score += (isPrimary ? 6 : 2) * genericPenalty;
        if (category.contains(term)) score += (isPrimary ? 2 : 1) * genericPenalty;
        if (tagline.contains(term)) score += (isPrimary ? 2 : 1) * genericPenalty;
        for (final feature in pkg.features) {
          if (feature.toLowerCase().contains(term)) {
            score += (isPrimary ? 4 : 1) * genericPenalty;
            if (isPrimary) matched.add(feature);
          }
        }
      }
      if (score > 0) {
        hits.add(_SearchHit(pkg, matched.take(2).toList(), score));
      }
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  // ── Actions ──────────────────────────────────────────────────────────
  Future<void> _callUs() async {
    final uri = Uri(scheme: 'tel', path: _expertPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open dialer. Please call +91 93530 94672'),
          backgroundColor: AppColors.surfaceRaised,
        ),
      );
    }
  }

  // _openMoreDetails and _bookNow used to refuse to navigate at all
  // without an active vehicle — but every package screen they lead to is
  // just tiers/features to browse until its own "Book Now" actually
  // reaches PaymentScreen, which now prompts to add a vehicle right there
  // if one's missing (see PaymentScreen.vehicleRequired). So browsing
  // never needs a vehicle; only that final step does.
  void _openMoreDetails(_Package pkg) {
    if (pkg.comingSoon) {
      _comingSoon(pkg.name);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => pkg.screenBuilder(widget.activeVehicle, highlightPackage: pkg.name),
      ),
    );
  }

  void _bookNow(_Package pkg) {
    if (pkg.comingSoon) {
      _comingSoon(pkg.name);
      return;
    }
    if (!pkg.directBook) {
      // No fixed, immediately-payable price — send them to the real
      // screen instead (vehicle type picker, quote, or claim form).
      _openMoreDetails(pkg);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: pkg.name,
          duration: pkg.duration,
          vehicleId: widget.activeVehicle?['id']?.toString() ?? '',
          vehicleRequired: pkg.vehicleRequired,
          // Priced and routed by the server from this service's row.
          serviceKeys: [pkg.key],
        ),
      ),
    );
  }

  void _comingSoon(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name coming soon'),
        backgroundColor: AppColors.surfaceRaised,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _openPackageSheet(_Package pkg) {
    final accent = _kCategoryAccent[pkg.category] ?? _gold;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            // The BOOK NOW button sits at the very bottom of this sheet —
            // on phones with a gesture nav bar or on-screen back/home/
            // recents buttons, a flat 28px isn't enough clearance and the
            // button ends up partly behind/under it. Add the device's own
            // safe-area bottom inset on top of the usual padding so the
            // button always clears it.
            padding: EdgeInsets.fromLTRB(24, 14, 24, 28 + MediaQuery.of(context).padding.bottom),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(_kCategoryIcon[pkg.category] ?? Icons.star_rounded,
                        color: accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (pkg.popular)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('MOST POPULAR',
                                style: TextStyle(
                                    color: accent, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                          ),
                        Text(pkg.name,
                            style: TextStyle(color: AppColors.txt, fontSize: 22, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(
                          pkg.duration.isEmpty ? pkg.price : '${pkg.price} • ${pkg.duration}',
                          style: TextStyle(color: accent, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(pkg.tagline, style: TextStyle(color: AppColors.mut, fontSize: 15, height: 1.5)),
              const SizedBox(height: 20),
              if (pkg.features.isNotEmpty) ...[
                Text("WHAT'S INCLUDED",
                    style: TextStyle(
                        color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                ...pkg.features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle, color: accent, size: 19),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(f,
                                style: TextStyle(color: AppColors.txt.withOpacity(0.85), fontSize: 15, height: 1.4)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _openMoreDetails(pkg);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: accent.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('MORE DETAILS',
                          style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 14.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _callUs,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF25D366).withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.call_rounded, color: Color(0xFF25D366), size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: pkg.comingSoon
                      ? null
                      : () {
                          Navigator.pop(context);
                          _bookNow(pkg);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    pkg.comingSoon
                        ? 'COMING SOON'
                        : (pkg.directBook ? 'BOOK NOW' : 'VIEW OPTIONS'),
                    style: TextStyle(
                        color: AppColors.onAccentDark, fontWeight: FontWeight.w900, letterSpacing: 0.6, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CatalogGate(builder: (context) {

    final isSearching = _searchQuery.isNotEmpty;
    final searchHits = isSearching ? _searchHits : const <_SearchHit>[];
    final filtered = _filtered;
    final Map<String, List<_Package>> grouped = {};
    for (final pkg in filtered) {
      grouped.putIfAbsent(pkg.category, () => <_Package>[]).add(pkg);
    }

    return Scaffold(
      backgroundColor: AppColors.ink,
      // Tapping anywhere outside the search field (which handles its own
      // taps fine, same as buttons/cards below it) dismisses the keyboard
      // — HitTestBehavior.opaque so empty space between/around slivers
      // still counts as a tap, not just the widgets drawn on it.
      body: EmergencyBannerOverlay(
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHero()),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _buildSearchBar(),
              ),
            ),
          ),
          if (isSearching) ...[
            if (searchHits.isEmpty)
              SliverFillRemaining(child: _buildNoResults())
            else ...[
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: _buildSearchResultsHeader(searchHits.length),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children: searchHits
                          .map((hit) => _buildPackageCard(hit.package,
                              matchedFeatures: hit.matchedFeatures, showCategoryChip: true))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],
          ] else
            for (final category in _kCategoryOrder)
              if (grouped.containsKey(category)) ...[
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: _buildSectionHeader(category, _kCategoryIcon[category] ?? Icons.star_rounded,
                          _kCategoryAccent[category] ?? _gold),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        children: grouped[category]!.map((pkg) => _buildPackageCard(pkg)).toList(),
                      ),
                    ),
                  ),
                ),
              ],
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
        ),
      ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 3,
        onSelect: (i) => handleBottomNavSelect(
          context,
          i,
          currentIndex: 3,
          activeVehicle: widget.activeVehicle,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: AskAiButton(
        onTap: () => openAiAdvisor(context, widget.activeVehicle),
      ),
    );
    });
  }

  // ── Hero ─────────────────────────────────────────────────
  Widget _buildHero() {
    return Stack(
      children: [
        SizedBox(
          height: 200,
          width: double.infinity,
          child: Image.asset(
            'assets/images/service_screen.jpg',
            fit: BoxFit.cover,
          ),
        ),
        Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Colors.black.withOpacity(0.25),
                Colors.black.withOpacity(0.85),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Back',
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _gold.withOpacity(0.4)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 20,
          left: 24,
          right: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _gold.withOpacity(0.5)),
                ),
                child: const Text(
                  'ALL PACKAGES',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'What does your car need today?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Search bar ───────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: _gold.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: TextStyle(color: AppColors.txt, fontSize: 17),
          decoration: InputDecoration(
            hintText: 'e.g. "oil change", "brake fail", "paint fade"…',
            hintStyle: TextStyle(color: AppColors.mut, fontSize: 15),
            prefixIcon: Icon(Icons.search_rounded,
                color: _gold.withOpacity(0.7), size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(Icons.close_rounded,
                        color: AppColors.mut, size: 20),
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  // ── Section header ───────────────────────────────────────
  Widget _buildSectionHeader(String title, IconData icon, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withOpacity(0.3)),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent.withOpacity(0.35), Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search results header ───────────────────────────────────
  Widget _buildSearchResultsHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        count == 1
            ? '1 package matches "$_searchQuery"'
            : '$count packages match "$_searchQuery"',
        style: TextStyle(color: AppColors.mut, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ── Package card ───────────────────────────────────────────
  // [matchedFeatures] — when this card is shown as a search result, the
  // specific feature(s) from the package that matched what was typed
  // (e.g. searching "oil change" shows "Includes: Engine Oil Change"
  // right on the card instead of a generic tagline nobody can connect to
  // their search). [showCategoryChip] labels which section the package
  // is normally found under, since search results aren't grouped by
  // category the way the browse view is.
  Widget _buildPackageCard(_Package pkg, {List<String>? matchedFeatures, bool showCategoryChip = false}) {
    final accent = _kCategoryAccent[pkg.category] ?? _gold;
    final hasMatch = matchedFeatures != null && matchedFeatures.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: GestureDetector(
        onTap: () => _openPackageSheet(pkg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(hasMatch ? 0.55 : 0.22), width: hasMatch ? 1.4 : 1),
            boxShadow: [
              BoxShadow(color: accent.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_kCategoryIcon[pkg.category] ?? Icons.star_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showCategoryChip)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          pkg.category.toUpperCase(),
                          style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pkg.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (pkg.comingSoon)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.chipBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('SOON',
                                style: TextStyle(
                                    color: AppColors.mut, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          )
                        else if (pkg.price.isNotEmpty)
                          Text(pkg.price,
                              style: TextStyle(color: accent, fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (hasMatch)
                      // Plain white-on-black, big and short — a badge
                      // that's easy to spot and easy to read at a
                      // glance, not something you have to stop and parse.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: accent.withOpacity(0.4), width: 1.4),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.black, size: 18),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Matches: ${matchedFeatures.join(', ')}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.black, fontSize: 15, fontWeight: FontWeight.w800, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        pkg.tagline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.mut, fontSize: 14, height: 1.4),
                      ),
                    const SizedBox(height: 10),
                    // A clearly button-shaped hint — filled background,
                    // not just an icon and small text — so it doesn't
                    // read as decoration; it looks like something you tap.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'TAP TO VIEW',
                            style: TextStyle(
                                color: AppColors.onAccentDark, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                          ),
                          const SizedBox(width: 5),
                          Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.onAccentDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── No-results state ──────────────────────────────────────
  // With word-by-word matching plus everyday-language synonyms, this
  // should now be rare — but when it does happen, don't just say "not
  // found" and stop. Point straight at our most popular packages, and
  // put a big, unmissable call button front and center: someone who
  // can't find what they want by typing should never be stuck.
  Widget _buildNoResults() {
    final suggestions = _kCatalog.where((p) => p.popular).toList();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 52, color: AppColors.mut.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              'We couldn\'t match "$_searchQuery" to a package',
              style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Not sure what to search? Just call us and describe the problem — we\'ll tell you exactly what you need.',
              style: TextStyle(color: AppColors.mut, fontSize: 15, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _callUs,
                icon: const Icon(Icons.call_rounded, size: 22),
                label: const Text('CALL AN EXPERT NOW'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6, fontSize: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Or try one of our most popular packages:',
              style: TextStyle(color: AppColors.txt, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: suggestions.map((pkg) {
                final accent = _kCategoryAccent[pkg.category] ?? _gold;
                return GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _openPackageSheet(pkg);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: accent.withOpacity(0.35)),
                    ),
                    child: Text(pkg.name,
                        style: TextStyle(color: accent, fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}