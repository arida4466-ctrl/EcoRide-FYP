import 'dart:math';
import '../services/driver_stream_service.dart';
import '../services/driver_stream_service.dart';

class LocationUtils {
  static double _deg2rad(double deg) => deg * (pi / 180);

  static double distance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;

    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static List<Driver> markNearest({
    required double userLat,
    required double userLng,
    required List<Driver> drivers,
  }) {
    if (drivers.isEmpty) return drivers;

    double minDist = double.infinity;
    String nearestId = "";

    for (var d in drivers) {
      final dist = distance(userLat, userLng, d.lat, d.lng);

      if (dist < minDist) {
        minDist = dist;
        nearestId = d.id;
      }
    }

    return drivers.map((d) {
      return d.copyWith(isNearest: d.id == nearestId);
    }).toList();
  }
}