class MediaLocation {
  const MediaLocation({
    required this.latitude,
    required this.longitude,
    this.altitude,
  });

  final double latitude;
  final double longitude;
  final double? altitude;

  Map<String, Object?> toJson() => <String, Object?>{
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
  };

  factory MediaLocation.fromJson(Map<String, dynamic> json) {
    return MediaLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
    );
  }
}
