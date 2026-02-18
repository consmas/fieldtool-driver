class Evidence {
  Evidence({
    required this.kind,
    required this.photoUrl,
    required this.capturedAt,
  });

  final String kind;
  final String photoUrl;
  final DateTime capturedAt;
}
