class Vehicle {
  const Vehicle({
    required this.brand,
    required this.model,
    this.active = false,
  });

  final String brand;
  final String model;
  final bool active;
}

const kVehicles = <Vehicle>[
  Vehicle(
    brand: 'MARUTI SUZUKI',
    model: 'Baleno',
    active: true,
  ),
  Vehicle(
    brand: 'MAHINDRA',
    model: 'XUV700',
  ),
];
