class Plan {
  const Plan({
    required this.title,
    required this.subtitle,
    required this.photoLabel,
    required this.features,
    required this.scheduleLabel,
    required this.price,
    required this.subscribeMessage,
  });

  final String title;
  final String subtitle;
  final String photoLabel;
  final List<String> features;
  final String scheduleLabel;
  final String price;

  /// Toast text shown on "Subscribe Now" — matches the prototype's
  /// `onSubBasic` / `onSubComplete` / `onSubPremium` literals verbatim.
  final String subscribeMessage;
}

const kPlans = <Plan>[
  Plan(
    title: 'ESSENTIAL WASH',
    subtitle: 'Exterior care',
    photoLabel: 'WASH PHOTO',
    features: ['Foam body wash', 'Interior vacuum', 'Tyre dressing'],
    scheduleLabel: '4 washes / month',
    price: '₹649',
    subscribeMessage: 'Essential Wash selected',
  ),
  Plan(
    title: 'COMPLETE CARE',
    subtitle: 'Periodic service',
    photoLabel: 'SERVICE PHOTO',
    features: ['Engine oil change', '25-point check', 'All fluid top-up'],
    scheduleLabel: '1 service / month',
    price: '₹2,199',
    subscribeMessage: 'Complete Care selected',
  ),
  Plan(
    title: 'PREMIUM CARE',
    subtitle: 'Everything included',
    photoLabel: 'GARAGE PHOTO',
    features: ['All of Complete Care', 'AC + brake service', 'Free pickup & drop'],
    scheduleLabel: '2 services / month',
    price: '₹3,499',
    subscribeMessage: 'Premium Care selected',
  ),
];
