/// Asset paths for the Home screen's image banners (see
/// `assets/images/README.md` for where to drop the actual files).

/// Shown in the 3D coverflow (portrait, 9:16).
const List<String> kCoverflowBanners = [
  'assets/images/wheelmanagement.jpg',
  'assets/images/paintcare.jpg',
  'assets/images/washing.jpg',
  'assets/images/service.jpg',
  'assets/images/ac.jpg',
];

/// Which [kCoverflowBanners] entry is centered/selected when the coverflow
/// first appears — looked up by filename (not a hardcoded index) so it
/// still points at the right slide if the list above gets reordered. Also
/// the one slide the "OUR PACKAGES" side heading is visible at.
const String kDefaultCoverflowBanner = 'assets/images/wheelmanagement.jpg';

/// Shown in the flat 2-up horizontal-scroll row below the coverflow
/// (landscape, 3:2 — matches the images' native 1536x1024 size).
const List<String> kServiceBanners = [
  'assets/images/tyres.jpeg',
  'assets/images/spares.jpeg',
  'assets/images/servicing.jpeg',
  'assets/images/painting.jpeg',
  'assets/images/detailing.jpeg',
  'assets/images/dent.jpeg',
  'assets/images/carspa.jpeg',
  'assets/images/insurance.jpeg',
];

/// The single promo banner shown under "Keep your car showroom-new
/// everyday :", below the 2-up scroll row.
const String kSubscriptionBanner = 'assets/images/subscription.jpeg';

/// Shown under "Get your paint protected :", below the services grid.
const String kPpfBanner = 'assets/images/PPFbanner.jpeg';

/// Shown under "Stranded somewhere ?", below the PPF banner.
const String kEmergencyBanner = 'assets/images/emergency.jpeg';