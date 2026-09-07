import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'service_tile.dart';

typedef ServiceEntry = ({IconData icon, String label});

const List<ServiceEntry> kCoreServices = [
  (icon: Symbols.build, label: 'Periodic\nService'),
  (icon: Symbols.local_car_wash, label: 'Deep\nCleaning'),
  (icon: Symbols.ac_unit, label: 'AC\nService'),
  (icon: Symbols.tire_repair, label: 'Tyres &\nWheels'),
  (icon: Symbols.car_repair, label: 'Denting'),
  (icon: Symbols.format_paint, label: 'Painting'),
  (icon: Symbols.verified_user, label: 'Insurance\nClaim'),
];

const List<ServiceEntry> kExtraServices = [
  (icon: Symbols.auto_fix_high, label: 'Ceramic\nCoating'),
  (icon: Symbols.support_agent, label: 'Roadside\nHelp'),
  (icon: Symbols.fact_check, label: 'Pre-buy\nInspection'),
];

/// The "What does your car need today?" grid: 7 fixed services plus a
/// "More Services" toggle tile, revealing 3 more when expanded.
class ServicesGrid extends StatelessWidget {
  const ServicesGrid({
    super.key,
    required this.expanded,
    required this.onServiceTap,
    required this.onToggle,
  });

  final bool expanded;
  final ValueChanged<String> onServiceTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (final s in kCoreServices)
        ServiceTile(
          icon: s.icon,
          label: s.label,
          onTap: () => onServiceTap(s.label.replaceAll('\n', ' ')),
        ),
      ServiceTile(icon: Symbols.apps, label: 'More\nServices', onTap: onToggle),
      if (expanded)
        for (final s in kExtraServices)
          ServiceTile(
            icon: s.icon,
            label: s.label,
            onTap: () => onServiceTap(s.label.replaceAll('\n', ' ')),
          ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 1 / 1.12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: tiles,
      ),
    );
  }
}
