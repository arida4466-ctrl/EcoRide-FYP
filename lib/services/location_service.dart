import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ── Faisalabad bounding box ───────────────────────────────────────────────────
const double _latMin = 31.25;
const double _latMax = 31.65;
const double _lngMin = 72.90;
const double _lngMax = 73.40;

bool _inFsd(double lat, double lng) =>
    lat >= _latMin && lat <= _latMax &&
        lng >= _lngMin && lng <= _lngMax;

// ── Driver location model ─────────────────────────────────────────────────────
class DriverLocation {
  final String uid;
  final double lat;
  final double lng;
  final double heading;
  final String? name;
  final bool isNearest;

  const DriverLocation({
    required this.uid,
    required this.lat,
    required this.lng,
    this.heading  = 0,
    this.name,
    this.isNearest = false,
  });

  DriverLocation copyWith({bool? isNearest}) => DriverLocation(
    uid:       uid,
    lat:       lat,
    lng:       lng,
    heading:   heading,
    name:      name,
    isNearest: isNearest ?? this.isNearest,
  );
}

// ── LocationService ───────────────────────────────────────────────────────────
class LocationService with ChangeNotifier {
  // Singleton
  static final LocationService _instance = LocationService._();
  factory LocationService() => _instance;
  LocationService._();

  final _db   = FirebaseDatabase.instance.ref();
  final _auth = FirebaseAuth.instance;

  // Driver side
  StreamSubscription<Position>? _gpsSub;
  bool get isStreaming => _gpsSub != null;

  // Passenger side
  StreamSubscription<DatabaseEvent>? _busSub;
  List<DriverLocation> _drivers = [];
  List<DriverLocation> get activeDrivers => List.unmodifiable(_drivers);

  Set<Marker> _markers = {};
  Set<Marker> get driverMarkers => Set.unmodifiable(_markers);

  LatLng? passengerLatLng;

  // Nearest first sorted list
  List<DriverLocation> get nearestSorted {
    if (_drivers.isEmpty) return [];
    final copy = [..._drivers];
    if (passengerLatLng != null) {
      copy.sort((a, b) =>
          _km(passengerLatLng!, LatLng(a.lat, a.lng))
              .compareTo(_km(passengerLatLng!, LatLng(b.lat, b.lng))));
    }
    return copy;
  }

  // ── DRIVER: start syncing GPS to RTDB /drivers/{uid} ─────────────────────
  Future<void> startDriverLocationStream() async {
    if (_gpsSub != null) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final ref = _db.child('drivers/$uid');
    await ref.update({'online': true, 'uid': uid});
    await ref.onDisconnect().remove();

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy:       LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((pos) async {
      if (!_inFsd(pos.latitude, pos.longitude)) return;
      await ref.update({
        'lat':       pos.latitude,
        'lng':       pos.longitude,
        'heading':   pos.heading,
        'speed':     pos.speed,
        'timestamp': ServerValue.timestamp,
        'online':    true,
      });
    });

    notifyListeners();
  }

  Future<void> stopDriverLocationStream() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _db.child('drivers/$uid').remove();
    }
    notifyListeners();
  }

  // ── PASSENGER: listen to ALL /drivers/ ───────────────────────────────────
  void startPassengerDriverStream({
    void Function(Set<Marker>)? onUpdate,
  }) {
    _busSub?.cancel();
    _busSub = _db.child('drivers').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        _drivers = [];
        _markers = {};
        onUpdate?.call({});
        notifyListeners();
        return;
      }

      final raw = Map<String, dynamic>.from(snap.value as Map);
      final List<DriverLocation> parsed = [];

      for (final entry in raw.entries) {
        final d = Map<String, dynamic>.from(entry.value as Map);
        if (d['online'] != true) continue;
        final lat = (d['lat'] as num?)?.toDouble();
        final lng = (d['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        if (!_inFsd(lat, lng)) continue;

        parsed.add(DriverLocation(
          uid:     entry.key,
          lat:     lat,
          lng:     lng,
          heading: (d['heading'] as num?)?.toDouble() ?? 0,
          name:    d['name'] as String?,
        ));
      }

      _drivers = _flagNearest(parsed);
      _markers = _buildMarkers(_drivers);
      onUpdate?.call(_markers);
      notifyListeners();
    });
  }

  void stopPassengerDriverStream() {
    _busSub?.cancel();
    _busSub = null;
    _drivers = [];
    _markers = {};
    notifyListeners();
  }

  // ── Show ONLY one accepted driver (when passenger accepted offer) ─────────
  void showOnlyDriver(
      String driverUid, {
        void Function(Set<Marker>)? onUpdate,
      }) {
    _busSub?.cancel();
    _busSub =
        _db.child('drivers/$driverUid').onValue.listen((event) {
          final snap = event.snapshot;
          if (!snap.exists || snap.value == null) {
            _markers = {};
            onUpdate?.call({});
            notifyListeners();
            return;
          }

          final d = Map<String, dynamic>.from(snap.value as Map);
          final lat     = (d['lat'] as num?)?.toDouble();
          final lng     = (d['lng'] as num?)?.toDouble();
          final heading = (d['heading'] as num?)?.toDouble() ?? 0;
          if (lat == null || lng == null) return;

          final driver = DriverLocation(
            uid:       driverUid,
            lat:       lat,
            lng:       lng,
            heading:   heading,
            isNearest: true,
          );

          _drivers = [driver];
          _markers = _buildMarkers([driver]);
          onUpdate?.call(_markers);
          notifyListeners();
        });
  }

  // ── Flag nearest driver ───────────────────────────────────────────────────
  List<DriverLocation> _flagNearest(List<DriverLocation> list) {
    if (list.isEmpty || passengerLatLng == null) return list;
    double minDist = double.infinity;
    String? nearId;
    for (final d in list) {
      final dist = _km(passengerLatLng!, LatLng(d.lat, d.lng));
      if (dist < minDist) {
        minDist = dist;
        nearId  = d.uid;
      }
    }
    return list
        .map((d) => d.copyWith(isNearest: d.uid == nearId))
        .toList();
  }

  // ── Build map markers with heading rotation ───────────────────────────────
  Set<Marker> _buildMarkers(List<DriverLocation> drivers) {
    final Set<Marker> out = {};
    for (final d in drivers) {
      out.add(Marker(
        markerId: MarkerId('driver_${d.uid}'),
        position: LatLng(d.lat, d.lng),
        rotation: d.heading,        // rotates the icon on the map
        flat:     true,             // required for rotation to work correctly
        icon: d.isNearest
            ? BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow)
            : BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(
          title: d.isNearest
              ? '★ ${d.name ?? 'Bus'} — Nearest'
              : (d.name ?? 'Bus'),
          snippet: 'Active driver',
        ),
        zIndex: d.isNearest ? 2 : 1,
      ));
    }
    return out;
  }

  // ── Haversine distance ────────────────────────────────────────────────────
  double _km(LatLng a, LatLng b) {
    const r    = 6371.0;
    final dLat = _rad(b.latitude  - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final x = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) *
            cos(_rad(b.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(x), sqrt(1 - x));
  }

  double _rad(double deg) => deg * pi / 180;

  // ── Distance string for UI ────────────────────────────────────────────────
  String distanceTo(DriverLocation d) {
    if (passengerLatLng == null) return '';
    final km = _km(passengerLatLng!, LatLng(d.lat, d.lng));
    return km < 1
        ? '${(km * 1000).toInt()} m away'
        : '${km.toStringAsFixed(1)} km away';
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _busSub?.cancel();
    super.dispose();
  }
}