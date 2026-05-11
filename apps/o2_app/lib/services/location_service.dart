/// O2 Platform — Location / GPS Service
///
/// Uses geolocator package for GPS auto-tag on visit logs.
/// NHM compliance requires GPS-tagged visit logs.

import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Check location permissions and get current position.
  /// Returns {latitude, longitude} or throws on failure.
  Future<Position> getCurrentPosition() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException('Location services are disabled');
    }

    // Check permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationException('Location permission denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationException('Location permission permanently denied');
    }

    // Get position with high accuracy for NHM compliance
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  /// Check if device is at a patient's home (within [meters] of [lat]/[lng]).
  /// Returns true if within range — used for GPS proof-of-presence.
  Future<bool> isAtLocation(double lat, double lng, {double meters = 100}) async {
    try {
      final pos = await getCurrentPosition();
      final distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
      return distance <= meters;
    } catch (e) {
      return false;
    }
  }

  /// Format coordinates for display.
  String formatCoordinates(double lat, double lng) {
    return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  }
}

class LocationException implements Exception {
  final String message;
  LocationException(this.message);

  @override
  String toString() => 'LocationException: $message';
}