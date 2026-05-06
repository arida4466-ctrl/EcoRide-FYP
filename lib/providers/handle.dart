import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:indriver_clone/models/address.dart';
import 'package:indriver_clone/models/place_predications.dart';
import 'package:indriver_clone/models/requests.dart';
import 'package:indriver_clone/providers/auth.dart';
import 'package:provider/provider.dart';

// ── Faisalabad strict bounding box ──────────────────────────────────────────
const double _latMin = 31.28;
const double _latMax = 31.62;
const double _lngMin = 72.90;
const double _lngMax = 73.40;
const String _fsdViewbox = '72.90,31.62,73.40,31.28';

bool _inFsd(double lat, double lng) =>
    lat >= _latMin && lat <= _latMax &&
        lng >= _lngMin && lng <= _lngMax;

class AppHandler with ChangeNotifier {
  void init(BuildContext context) {
    locatePosition(context);
    notifyListeners();
  }

  final _firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  RideRequest request = RideRequest();

  Address? pickupLocation, destinationLocation;
  List<Prediction> predictionList = [];

  bool startSelected = false;
  bool endSelected = false;

  String startpoint = 'Start point';
  String endpoint = 'End point';

  late GoogleMapController mapController;
  Position? liveLocation;
  List<LatLng> pLineCoordinates = [];

  Set<Polyline> polylineSet = {};
  Set<Circle> circlesSet = {};
  Set<Marker> markersSet = {};

  // ─── Locate current position ─────────────────────────────────────────────
  void locatePosition(BuildContext context) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _snack(context, 'Please enable location service');
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack(context, 'Location permission denied');
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      liveLocation = position;

      String locationName = 'Current location';
      try {
        final marks = await placemarkFromCoordinates(
            position.latitude, position.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          final parts = <String>[
            if ((p.name ?? '').trim().isNotEmpty) p.name!.trim(),
            if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
          ];
          if (parts.isNotEmpty) locationName = parts.join(', ');
        }
      } catch (_) {}

      updatePickupLocationAdress(Address(
        latitude: position.latitude,
        longitude: position.longitude,
        placeName: locationName,
      ));

      mapController.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
            target: LatLng(position.latitude, position.longitude), zoom: 14),
      ));
      notifyListeners();
    } catch (e) {
      _snack(context, 'Could not fetch current location');
    }
  }

  void updatePickupLocationAdress(Address a) {
    pickupLocation = a;
    startpoint = a.placeName!;
    startSelected = true;
    notifyListeners();
  }

  void updateDestinationLocationAdress(Address a) {
    destinationLocation = a;
    endpoint = a.placeName!;
    endSelected = true;
    notifyListeners();
  }

  // ─── OSM Nominatim Search ────────────────────────────────────────────────
  // STRICT: Only shows results that are actually inside Faisalabad.
  // No fake fallback coords — if not found, list stays empty.
  Future<void> findPlace(String placename) async {
    if (placename.trim().length < 2) {
      clearPredictions();
      return;
    }

    try {
      final query = '${placename.trim()} Faisalabad Pakistan';

      // Try 1: bounded search
      List raw = await _nominatim(query, bounded: true);

      // Try 2: unbounded but still filtered by coords below
      if (raw.isEmpty) {
        raw = await _nominatim(query, bounded: false);
      }

      // STRICT FILTER: only keep results inside Faisalabad box
      final filtered = raw.where((item) {
        final lat = double.tryParse(item['lat'].toString()) ?? 0;
        final lng = double.tryParse(item['lon'].toString()) ?? 0;
        return _inFsd(lat, lng);
      }).toList();

      if (filtered.isEmpty) {
        clearPredictions();
        return;
      }

      predictionList = filtered.map<Prediction>((item) {
        final addr = item['address'] as Map<String, dynamic>? ?? {};
        final mainText = ((item['name'] as String?) ?? '').isNotEmpty
            ? item['name'] as String
            : addr['road'] as String? ??
            addr['suburb'] as String? ??
            placename;

        final subParts = <String>[];
        final suburb = addr['suburb'] as String? ?? '';
        if (suburb.isNotEmpty && suburb != mainText) subParts.add(suburb);
        final city = addr['city'] as String? ??
            addr['town'] as String? ??
            addr['county'] as String? ??
            'Faisalabad';
        if (city.isNotEmpty) subParts.add(city);

        return Prediction(
          id: item['place_id'].toString(),
          mainText: mainText,
          subtitle: subParts.isNotEmpty ? subParts.join(', ') : 'Faisalabad',
          // REAL coords only — no fake fallback
          lat: double.tryParse(item['lat'].toString())!,
          lng: double.tryParse(item['lon'].toString())!,
        );
      }).toList();

      notifyListeners();
    } catch (e) {
      debugPrint('findPlace error: $e');
      clearPredictions();
    }
  }

  Future<List> _nominatim(String query, {required bool bounded}) async {
    final encoded = Uri.encodeComponent(query);
    final boundPart = bounded
        ? '&viewbox=$_fsdViewbox&bounded=1'
        : '&viewbox=$_fsdViewbox';
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
          '?q=$encoded'
          '&format=json'
          '&addressdetails=1'
          '&limit=8'
          '$boundPart',
    );
    try {
      final resp = await http.get(url, headers: {
        'User-Agent': 'SafeDriveApp/1.0',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) return jsonDecode(resp.body) as List;
    } catch (_) {}
    return [];
  }

  void clearPredictions() {
    predictionList = [];
    notifyListeners();
  }

  // ─── OSRM Directions ─────────────────────────────────────────────────────
  // Returns true = success, false = failed (caller shows error).
  // NO straight-line fallback — if coords are wrong, user must re-enter.
  Future<bool> getDirection(BuildContext context) async {
    final start = pickupLocation;
    final end = destinationLocation;
    if (start == null || end == null) return false;

    // Validate both coords are inside Faisalabad
    if (!_inFsd(start.latitude!, start.longitude!)) {
      _snackLong(context,
          '⚠️ Pickup location not found in Faisalabad. Please select a correct location from the list.');
      // Reset pickup so user must re-enter
      pickupLocation = null;
      startpoint = 'Start point';
      startSelected = false;
      notifyListeners();
      return false;
    }

    if (!_inFsd(end.latitude!, end.longitude!)) {
      _snackLong(context,
          '⚠️ Destination not found in Faisalabad. Please enter a correct location.');
      // Reset destination so user must re-enter
      destinationLocation = null;
      endpoint = 'End point';
      endSelected = false;
      notifyListeners();
      return false;
    }

    final startLL = LatLng(start.latitude!, start.longitude!);
    final endLL = LatLng(end.latitude!, end.longitude!);

    // Show loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    String? encodedPolyline;

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
            '${start.longitude},${start.latitude};'
            '${end.longitude},${end.latitude}'
            '?overview=full&geometries=polyline',
      );
      final resp = await http
          .get(url, headers: {'User-Agent': 'SafeDriveApp/1.0'})
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['code'] == 'Ok' &&
            (data['routes'] as List).isNotEmpty) {
          encodedPolyline = data['routes'][0]['geometry'] as String;
        }
      }
    } catch (_) {}

    // Dismiss loader
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    // If OSRM failed — show error, reset destination, force re-entry
    if (encodedPolyline == null) {
      _snackLong(context,
          '⚠️ Could not find a road route to this destination. Please enter a correct location in Faisalabad.');
      destinationLocation = null;
      endpoint = 'End point';
      endSelected = false;
      notifyListeners();
      return false;
    }

    // Draw route polyline
    final decoded = PolylinePoints().decodePolyline(encodedPolyline);
    pLineCoordinates
      ..clear()
      ..addAll(decoded.map((p) => LatLng(p.latitude, p.longitude)));

    polylineSet
      ..clear()
      ..add(Polyline(
        polylineId: const PolylineId('route'),
        color: Colors.blue.shade700,
        width: 5,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: true,
        points: pLineCoordinates,
      ));

    // Markers
    markersSet
      ..removeWhere((m) =>
      m.markerId.value == 'StartId' || m.markerId.value == 'EndId')
      ..add(Marker(
        markerId: const MarkerId('StartId'),
        position: startLL,
        icon:
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: start.placeName, snippet: 'Pickup'),
      ))
      ..add(Marker(
        markerId: const MarkerId('EndId'),
        position: endLL,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: end.placeName, snippet: 'Destination'),
      ));

    // Circles
    circlesSet
      ..removeWhere((c) =>
      c.circleId.value == 'StartId' || c.circleId.value == 'EndId')
      ..add(Circle(
        circleId: const CircleId('StartId'),
        center: startLL,
        radius: 12,
        fillColor: Colors.green,
        strokeColor: Colors.greenAccent,
        strokeWidth: 3,
      ))
      ..add(Circle(
        circleId: const CircleId('EndId'),
        center: endLL,
        radius: 12,
        fillColor: Colors.red,
        strokeColor: Colors.redAccent,
        strokeWidth: 3,
      ));

    // Fit camera
    final bounds = _boundsFrom([startLL, endLL]);
    mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
    notifyListeners();
    return true;
  }

  LatLngBounds _boundsFrom(List<LatLng> pts) {
    double minLat = pts[0].latitude, maxLat = pts[0].latitude;
    double minLng = pts[0].longitude, maxLng = pts[0].longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _snackLong(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 4),
      backgroundColor: Colors.red.shade700,
    ));
  }

  // ─── Ride request methods (unchanged) ───────────────────────────────────
  bool requesting = false;
  bool deleted = false;

  void sendRequest(
      String startLat,
      String startLong,
      bool accepted,
      String username,
      String timeCreated,
      String phoneNum,
      String startAddress,
      String endAddress,
      String endLat,
      String endLong,
      String price,
      ) async {
    requesting = true;
    deleted = false;
    Map<String, dynamic> rideinfo = {
      'id': auth.currentUser!.uid,
      'startLat': startLat,
      'startLong': startLong,
      'endLat': endLat,
      'endLong': endLong,
      'startAddress': startAddress,
      'endAddress': endAddress,
      'price': price,
      'accepted': accepted,
      'username': username,
      'phoneNum': phoneNum,
      'timeCreated': timeCreated,
      'driverId': '',
      'driverArrived': false,
      'driverName': '',
      'driverPic': '',
      'arrivalTime': '',
      'answered': false,
      'driverAccepted': false,
      'journeyStarted': false,
    };
    try {
      await _firestore
          .collection('request')
          .doc(auth.currentUser!.uid)
          .set(rideinfo)
          .then((_) async {
        await _firestore
            .collection('request')
            .doc(auth.currentUser!.uid)
            .get()
            .then((value) {
          request = RideRequest.fromDocument(value);
          getRequests();
          notifyListeners();
        });
        requesting = false;
      });
    } on FirebaseException catch (e) {
      debugPrint('sendRequest: $e');
    }
  }

  Future<void> removeRequest() async {
    try {
      await _firestore
          .collection('request')
          .doc(auth.currentUser!.uid)
          .delete()
          .then((_) => deleted = true);
    } on FirebaseException catch (e) {
      debugPrint(e.message);
    }
  }

  List<RideRequest> requests = [];

  void getRequests() async {
    await _firestore
        .collection('request')
        .where('accepted', isEqualTo: false)
        .get()
        .then((value) {
      requests =
          value.docs.map((e) => RideRequest.fromDocument(e)).toList();
      notifyListeners();
    });
  }

  void acceptRequest(String id, BuildContext context, String time) async {
    final cu = Provider.of<Authentication>(context, listen: false);
    await _firestore.collection('request').doc(id).update({
      'driverAccepted': true,
      'driverId': cu.auth.currentUser!.uid,
      'driverName': (cu.loggedUser.driverName?.isNotEmpty == true)
          ? cu.loggedUser.driverName
          : cu.loggedUser.username,
      'arrivalTime': time,
      'driverPic': cu.loggedUser.carplatenum ?? '',
    }).then((_) {
      requests = [];
      notifyListeners();
    });
  }
}