import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:indriver_clone/driver/screens/eta_utils.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:indriver_clone/driver/screens/waiting_screen.dart';
import 'package:indriver_clone/models/requests.dart';
import 'package:indriver_clone/providers/handle.dart';
import 'package:indriver_clone/ui/button.dart';
import 'package:indriver_clone/ui/constants.dart';
import 'package:provider/provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  DriverMap — shown when driver taps a request card
// ─────────────────────────────────────────────────────────────────────────────
class DriverMap extends StatefulWidget {
  final RideRequest request;
  const DriverMap({Key? key, required this.request}) : super(key: key);
  @override
  _DriverMapState createState() => _DriverMapState();
}

class _DriverMapState extends State<DriverMap> {
  final Completer<GoogleMapController> _mapCtrl = Completer();

  Set<Polyline> _polylines = {};
  Set<Marker>   _markers   = {};
  List<LatLng>  _route     = [];
  int           _busIdx    = 0;
  double        _busHdg    = 0;
  Timer?        _anim;

  LatLng? _driverPos;
  StreamSubscription<Position>? _gpsSub;

  bool   _loading    = true;
  int    _etaMins    = 0;
  double _distKm     = 0;
  String _etaLabel   = 'Getting your location…';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _anim?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _getGps();
    await _buildRoute();
    _startGps();
    _startAnim();
  }

  // ── Fresh GPS fix ─────────────────────────────────────────────────────────
  Future<void> _getGps() async {
    for (final acc in [LocationAccuracy.bestForNavigation, LocationAccuracy.high]) {
      try {
        final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: acc,
          timeLimit: const Duration(seconds: 8),
        );
        if (p.accuracy <= 100) { // only accept if GPS is reasonably accurate
          _driverPos = LatLng(p.latitude, p.longitude);
          return;
        }
      } catch (_) {}
    }
  }

  // ── Route + ETA calculation ───────────────────────────────────────────────
  Future<void> _buildRoute() async {
    final req = widget.request;
    if (req.startLat == null || req.startLong == null) {
      _done(label: 'Passenger location unavailable');
      return;
    }
    if (_driverPos == null) {
      _done(label: 'Enable GPS and reopen this screen');
      return;
    }

    final passLL = LatLng(double.parse(req.startLat!), double.parse(req.startLong!));
    final straightKm = EtaUtils.haversine(_driverPos!, passLL);
    _distKm = straightKm;

    // Same spot or very close → no OSRM needed
    if (straightKm < 0.20) {
      final secs = EtaUtils.secsFromKm(straightKm);
      _done(
        km:   straightKm,
        mins: (secs / 60).ceil(),
        label: EtaUtils.etaLabel(straightKm),
        route: straightKm < 0.030 ? [] : [_driverPos!, passLL],
        useDash: true,
        passLL: passLL,
      );
      return;
    }

    // Far — try OSRM
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${_driverPos!.longitude},${_driverPos!.latitude};'
        '${passLL.longitude},${passLL.latitude}'
        '?overview=full&geometries=polyline',
      );
      final resp = await http
          .get(url, headers: {'User-Agent': 'SafeDriveApp/1.0'})
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['code'] == 'Ok' && (data['routes'] as List).isNotEmpty) {
          final r = data['routes'][0];
          final validated = EtaUtils.validateOsrm(
            (r['distance'] as num).toDouble() / 1000,
            (r['duration'] as num).toDouble(),
            straightKm,
          );

          if (validated != null) {
            final pts = PolylinePoints()
                .decodePolyline(r['geometry'] as String)
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList();
            final mins = max(1, (validated.secs / 60).ceil());
            _done(
              km:    validated.km,
              mins:  mins,
              label: EtaUtils.etaLabel(validated.km)
                         .replaceFirst(RegExp(r'^\d+ min'), '$mins min'),
              route: pts,
              passLL: passLL,
            );
            return;
          }
          // OSRM result looked wrong → fall through to Haversine
        }
      }
    } catch (_) {}

    // Fallback: straight-line Haversine estimate
    final secs = EtaUtils.secsFromKm(straightKm);
    final mins = max(1, (secs / 60).ceil());
    _done(
      km:    straightKm,
      mins:  mins,
      label: EtaUtils.etaLabel(straightKm),
      route: [_driverPos!, passLL],
      useDash: true,
      passLL: passLL,
    );
  }

  void _done({
    double km = 0,
    int    mins = 0,
    required String label,
    List<LatLng> route = const [],
    bool useDash = false,
    LatLng? passLL,
  }) {
    if (!mounted) return;
    final req = widget.request;
    setState(() {
      _distKm  = km;
      _etaMins = mins;
      _etaLabel = label;
      _loading = false;
      _route   = route;

      _polylines = route.length >= 2
          ? {
              Polyline(
                polylineId: const PolylineId('r'),
                color:      useDash ? primaryColor.withOpacity(0.6) : primaryColor,
                width:      5,
                points:     route,
                patterns:   useDash
                    ? [PatternItem.dash(16), PatternItem.gap(10)]
                    : [],
                jointType:  JointType.round,
                startCap:   Cap.roundCap,
                endCap:     Cap.roundCap,
                geodesic:   true,
              ),
            }
          : {};

      _markers = {
        _busMkr(_driverPos!, 0),
        if (passLL != null)
          Marker(
            markerId: const MarkerId('pass'),
            position: passLL,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(
              title: req.username ?? 'Passenger',
              snippet: req.startAddress ?? '',
            ),
          ),
      };
    });
    if (passLL != null && _driverPos != null) {
      _fitBounds([_driverPos!, passLL]);
    }
  }

  // ── Animate bus along route ────────────────────────────────────────────────
  void _startAnim() {
    _anim = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted || _route.length < 2) return;
      final next = (_busIdx + 1) % _route.length;
      final hdg  = EtaUtils.bearing(_route[_busIdx], _route[next]);
      setState(() {
        _busIdx = next;
        _busHdg = hdg;
        _replaceMarker(_busMkr(_route[next], hdg));
      });
    });
  }

  // ── Live GPS for real-time ETA updates ───────────────────────────────────
  void _startGps() {
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      final req = widget.request;
      if (req.startLat == null || req.startLong == null) return;

      final passLL = LatLng(double.parse(req.startLat!), double.parse(req.startLong!));
      final km = EtaUtils.haversine(ll, passLL);

      // Recalculate ETA live only for short distances (<1km)
      int    mins  = _etaMins;
      String label = _etaLabel;
      if (!_loading && km < 1.0) {
        final secs = EtaUtils.secsFromKm(km);
        mins  = (secs / 60).ceil();
        label = EtaUtils.etaLabel(km);
      }

      setState(() {
        _driverPos = ll;
        _distKm    = km;
        _etaMins   = mins;
        _etaLabel  = label;
        _replaceMarker(_busMkr(ll, pos.heading));
      });
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _replaceMarker(Marker m) {
    _markers = {..._markers.where((x) => x.markerId != m.markerId), m};
  }

  Marker _busMkr(LatLng pos, double h) => Marker(
    markerId: const MarkerId('bus'),
    position: pos, rotation: h, flat: true,
    anchor:   const Offset(0.5, 0.5),
    icon:     BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    infoWindow: const InfoWindow(title: '🚌 Your Bus'),
    zIndex: 3,
  );

  Future<void> _fitBounds(List<LatLng> pts) async {
    if (pts.length < 2) return;
    final ctrl = await _mapCtrl.future;
    double minLat = pts[0].latitude,  maxLat = pts[0].latitude;
    double minLng = pts[0].longitude, maxLng = pts[0].longitude;
    for (final p in pts) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    if ((maxLat - minLat) < 0.002) { minLat -= 0.002; maxLat += 0.002; }
    if ((maxLng - minLng) < 0.002) { minLng -= 0.002; maxLng += 0.002; }
    ctrl.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      80,
    ));
  }

  void _accept() {
    Provider.of<AppHandler>(context, listen: false)
        .acceptRequest(widget.request.id ?? '', context, _etaMins.toString());
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => Waiting()));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final req  = widget.request;
    final initTarget = _driverPos ??
        LatLng(double.tryParse(req.startLat  ?? '31.4504') ?? 31.4504,
               double.tryParse(req.startLong ?? '73.1350') ?? 73.1350);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Ride Request',
            style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Column(children: [
        // ── Map ───────────────────────────────────────────────────────────
        SizedBox(
          height: size.height * 0.50,
          child: Stack(children: [
            GoogleMap(
              mapType:                 MapType.normal,
              myLocationEnabled:       true,
              myLocationButtonEnabled: true,
              markers:   _markers,
              polylines: _polylines,
              onMapCreated: (c) { if (!_mapCtrl.isCompleted) _mapCtrl.complete(c); },
              initialCameraPosition: CameraPosition(target: initTarget, zoom: 15),
            ),
            if (_loading)
              _loadingBadge('Getting your GPS location…'),
            if (!_loading)
              Positioned(
                bottom: 10, left: 10,
                child: _distBadge(),
              ),
          ]),
        ),

        // ── Detail panel ──────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Passenger name
                    Row(children: [
                      const CircleAvatar(
                        backgroundColor: primaryColor, radius: 18,
                        child: Icon(Icons.person, color: Colors.white, size: 18)),
                      const SizedBox(width: 8),
                      Text(req.username ?? 'Passenger',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
                    const SizedBox(height: 12),
                    _row(Icons.trip_origin, Colors.green, 'From', req.startAddress ?? ''),
                    const SizedBox(height: 6),
                    _row(Icons.location_on,  Colors.red,   'To',   req.endAddress   ?? ''),
                    const SizedBox(height: 14),

                    // ETA card
                    _etaCard(),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _loading
                  ? _greyBtn('Getting GPS…')
                  : BotButton(
                      onTap: _accept,
                      title: _etaMins == 0
                          ? 'Accept — You are here ✓'
                          : 'Accept — $_etaLabel',
                    ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Small widgets ─────────────────────────────────────────────────────────
  Widget _etaCard() {
    final isHere = _etaMins == 0 && !_loading;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _loading
            ? Colors.grey.shade100
            : isHere ? Colors.green.shade50 : primaryColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _loading
              ? Colors.grey.shade300
              : isHere ? Colors.green.shade300 : primaryColor.withOpacity(0.3),
        ),
      ),
      child: Row(children: [
        if (_loading)
          const SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor))
        else
          Icon(isHere ? Icons.check_circle : Icons.directions_bus,
              color: isHere ? Colors.green : primaryColor, size: 26),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _loading ? 'Calculating accurate ETA…' : _etaLabel,
            style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15,
              color: isHere ? Colors.green.shade700 : primaryColor,
            ),
          ),
          if (!_loading)
            Text(
              isHere
                  ? 'Driver and passenger are at the same spot'
                  : 'Based on actual road distance & speed',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ])),
      ]),
    );
  }

  Widget _distBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: _etaMins == 0 ? Colors.green : Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(_etaMins == 0 ? Icons.check_circle : Icons.directions_bus,
          color: _etaMins == 0 ? Colors.white : primaryColor, size: 15),
      const SizedBox(width: 5),
      Text(EtaUtils.fmtDist(_distKm),
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold,
            color: _etaMins == 0 ? Colors.white : primaryColor,
          )),
    ]),
  );

  Widget _loadingBadge(String msg) => Positioned(
    top: 12, left: 0, right: 0,
    child: Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor)),
        const SizedBox(width: 8),
        Text(msg, style: const TextStyle(
            color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
      ]),
    )),
  );

  Widget _greyBtn(String t) => Container(
    height: 52,
    decoration: BoxDecoration(color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(24)),
    child: Center(child: Text(t, style: const TextStyle(color: Colors.grey, fontSize: 15))),
  );

  Widget _row(IconData icon, Color color, String label, String val) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 6),
        Expanded(child: RichText(text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(color: Colors.grey)),
            TextSpan(text: val, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ))),
      ]);
}
