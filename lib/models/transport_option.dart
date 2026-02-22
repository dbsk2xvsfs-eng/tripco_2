enum TransportType { walk, bike, transit, car }

class TransportOption {
  final TransportType type;
  final String label;
  final int minutes;
  final double priceEur;
  final String difficulty;
  final int? distanceMeters;

  TransportOption({
    required this.type,
    required this.label,
    required this.minutes,
    required this.priceEur,
    required this.difficulty,
    this.distanceMeters,
  });

  String get priceText {
    if (priceEur <= 0) return "Free";
    return "€${priceEur.toStringAsFixed(priceEur < 10 ? 2 : 0)}";
  }
}
