import 'package:geolocator/geolocator.dart';

import '../models/media_location.dart';

class LocationMetadataException implements Exception {
  const LocationMetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocationMetadataService {
  const LocationMetadataService._();

  static Future<MediaLocation> getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationMetadataException(
        'Location services are turned off.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationMetadataException(
        'Location permission was not granted.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationMetadataException(
        'Location permission was permanently denied. Allow it in Settings.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return MediaLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
    );
  }
}
