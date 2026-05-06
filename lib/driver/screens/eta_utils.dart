import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Shared ETA + distance utilities used by DriverMap and Waiting screens.
class EtaUtils {
  // ── Haversine straight-line distance in km ────────────────────────────────
  static double haversine(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude  - a.latitude)  * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) * cos(b.latitude * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  // ── Seconds from km (realistic speed tiers, never blows up) ──────────────
  static int secsFromKm(double km) {
    if (km < 0.030) return 0;
    if (km < 0.150) return (km / 0.056  * 3600).round(); // ~3.4 km/h walking
    if (km < 0.500) return (km / 0.139  * 3600).round(); // ~8 km/h crawl
    if (km < 2.000) return (km / 0.278  * 3600).round(); // ~17 km/h city
    if (km < 5.000) return (km / 0.417  * 3600).round(); // ~25 km/h
    return              (km / 0.556  * 3600).round();    // ~33 km/h highway
  }

  // ── Human-readable distance string ───────────────────────────────────────
  static String fmtDist(double km) {
    if (km < 0.030) return 'Same location';
    if (km < 1.0)   return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }

  // ── Full ETA label ────────────────────────────────────────────────────────
  static String etaLabel(double km) {
    if (km < 0.030) return '✓ You are at the pickup point';
    final secs = secsFromKm(km);
    final mins = (secs / 60).ceil();
    if (mins <= 1) return '< 1 min away  •  ${fmtDist(km)}';
    return '$mins min away  •  ${fmtDist(km)}';
  }

  // ── Minutes from km ───────────────────────────────────────────────────────
  static int minsFromKm(double km) {
    if (km < 0.030) return 0;
    return (secsFromKm(km) / 60).ceil();
  }

  // ── Validate OSRM result — returns null if the result looks wrong ─────────
  static ({double km, double secs})? validateOsrm(
      double osrmKm, double osrmSecs, double straightKm) {
    if (osrmKm <= 0 || osrmSecs <= 0) return null;
    // Road must not be more than 4× the straight-line distance
    if (osrmKm > straightKm * 4) return null;
    // If OSRM claims > 1 hour for < 10 km, that's garbage data
    if (osrmSecs > 3600 && osrmKm < 10) return null;
    // Implied speed sanity: 1–200 km/h
    final impliedKmh = osrmKm / (osrmSecs / 3600);
    if (impliedKmh < 1 || impliedKmh > 200) return null;
    return (km: osrmKm, secs: osrmSecs);
  }

  // ── Compass bearing (degrees, 0 = North) ─────────────────────────────────
  static double bearing(LatLng a, LatLng b) {
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final la1  = a.latitude  * pi / 180;
    final la2  = b.latitude  * pi / 180;
    return (atan2(sin(dLng) * cos(la2),
                  cos(la1)  * sin(la2) - sin(la1) * cos(la2) * cos(dLng))
            * 180 / pi + 360) % 360;
  }
}
