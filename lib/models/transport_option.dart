enum TransportType { walk, transit, car }

class TransportOption {
  final TransportType type;
  final String label;
  final int minutes;
  final int distanceMeters;

  TransportOption({
    required this.type,
    required this.label,
    required this.minutes,
    required this.distanceMeters,
  });
}