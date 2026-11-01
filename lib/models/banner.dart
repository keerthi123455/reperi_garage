import '../services/home_content_service.dart';

/// Home screen banner paths.
///
/// The constants below are the hardcoded defaults — used as a fallback
/// when the CMS can't be reached. In normal operation `HomeContentService`
/// loads the live list from the `home_content` table on launch, and the
/// getters here return THAT instead, so a tile taken offline from the CRM
/// disappears from the home screen without needing an app update.
///
/// A getter returns the `displaySrc` of each live item in the section
/// (the uploaded image URL, or the bundled `assets/images/...` path if no
/// upload yet). The constants are kept so a cold start without network
/// still shows the stock home screen.

/// Fallback — hardcoded 4-wheeler coverflow (portrait, 9:16).
const List<String> _kCoverflowBannersFallback = [
  'assets/images/service.jpg',
  'assets/images/washing.jpg',
  'assets/images/wheelmanagement.jpg',
  'assets/images/paintcare.jpg',
  'assets/images/ac.jpg',
  'assets/images/lighting_services_banner.jpeg',
  'assets/images/other_services_banner.jpeg',
];

List<String> get kCoverflowBanners {
  final cms = HomeContentService.forSection('coverflow');
  if (cms.isEmpty) return _kCoverflowBannersFallback;
  return [for (final i in cms) i.displaySrc ?? ''].where((s) => s.isNotEmpty).toList();
}

/// Which coverflow entry is centered on first open.
const String kDefaultCoverflowBanner = 'assets/images/service.jpg';

/// Fallback — hardcoded 2-up service tiles (landscape, 3:2).
const List<String> _kServiceBannersFallback = [
  'assets/images/tyres.jpeg',
  'assets/images/spares.jpeg',
  'assets/images/servicing.jpeg',
  'assets/images/painting.jpeg',
  'assets/images/detailing.jpeg',
  'assets/images/dent.jpeg',
  'assets/images/carspa.jpeg',
  'assets/images/claim.jpeg',
];

List<String> get kServiceBanners {
  final cms = HomeContentService.forSection('tile');
  if (cms.isEmpty) return _kServiceBannersFallback;
  return [for (final i in cms) i.displaySrc ?? ''].where((s) => s.isNotEmpty).toList();
}

// ── Standalone banners ──────────────────────────────────────────────
// The getter always returns the path to display (CMS upload if any,
// otherwise the bundled asset). To hide a banner on the home screen when
// its CMS row is offline, call isBannerActive() before rendering it:
//
//    if (isBannerActive('banner:emergency'))
//      PromoBanner(assetPath: kEmergencyBanner, …)
//
// Rows the CMS doesn't know about (CMS not loaded yet / brand-new banner
// not seeded in the DB) always count as active, so a cold start without
// network still shows the stock home screen.

// Looks up the banner in CMS. If the row is OFFLINE, returns an empty
// string — PromoBanner renders nothing for '' (see widgets/promo_banner.
// dart), so the tile disappears from the home screen. If the row is live,
// returns its uploaded image URL. If the CMS has never heard of this key
// (CMS not loaded yet / brand-new banner not seeded), returns the bundled
// asset so a cold start still shows the stock home screen.
String _banner(String cmsKey, String fallback) {
  final matches = HomeContentService.all.where((i) => i.key == cmsKey).toList();
  if (matches.isEmpty) return fallback;
  final item = matches.first;
  if (!item.isActive) return ''; // hidden by the CRM
  return item.displaySrc ?? fallback;
}

String get kMonthlyWashBanner => _banner('banner:monthlywash', 'assets/images/monthlywash.jpeg');
String get kPpfBanner          => _banner('banner:ppf',         'assets/images/PPFbanner.jpeg');
String get kEmergencyBanner    => _banner('banner:emergency',   'assets/images/emergency.jpeg');
String get kBatteryBanner      => _banner('banner:battery',     'assets/images/battery.jpeg');
String get kFleetBanner        => _banner('banner:fleet',       'assets/images/fleet.jpeg');
String get kPartnerBanner      => _banner('banner:partner',     'assets/images/partner.jpeg');
String get kPollutionBanner    => _banner('banner:pollution',   'assets/images/pollution.jpeg');
String get kInspectionBanner   => _banner('banner:inspection',  'assets/images/inspection.jpeg');

/// Fallback — hardcoded 2-wheeler coverflow.
const List<String> _kTwoWheelerCoverflowBannersFallback = [
  'assets/images/servicing_twowheeler.jpeg',
  'assets/images/washing_twowheeler.jpeg',
];

List<String> get kTwoWheelerCoverflowBanners {
  final cms = HomeContentService.forSection('twowheeler');
  if (cms.isEmpty) return _kTwoWheelerCoverflowBannersFallback;
  return [for (final i in cms) i.displaySrc ?? ''].where((s) => s.isNotEmpty).toList();
}
