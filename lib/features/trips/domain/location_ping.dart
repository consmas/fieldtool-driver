class LocationPing {
  LocationPing({
    required this.tripId,
    required this.lat,
    required this.lng,
    required this.speed,
    required this.heading,
    required this.recordedAt,
  });

  final int tripId;
  final double lat;
  final double lng;
  final double speed;
  final double heading;
  final DateTime recordedAt;

  Map<String, dynamic> toJson() => {
        'trip_id': tripId,
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'heading': heading,
        'recorded_at': recordedAt.toIso8601String(),
      };
}
