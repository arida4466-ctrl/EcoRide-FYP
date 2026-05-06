import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:indriver_clone/driver/screens/eta_utils.dart';
import 'package:indriver_clone/driver/screens/main_page.dart';
import 'package:indriver_clone/providers/auth.dart';
import 'package:indriver_clone/screens/chat_screen.dart';
import 'package:indriver_clone/ui/button.dart';
import 'package:indriver_clone/ui/constants.dart';
import 'package:provider/provider.dart';

class Waiting extends StatefulWidget {
  const Waiting({Key? key}) : super(key: key);

  @override
  _WaitingState createState() => _WaitingState();
}

class _WaitingState extends State<Waiting> with TickerProviderStateMixin {
  // ── Firestore stream ───────────────────────────────────────────────────────
  late Stream<QuerySnapshot> _stream;
  String? _driverUid;

  // ── Map ────────────────────────────────────────────────────────────────────
  final Completer<GoogleMapController> _mapCtrl = Completer();
  Set<Polyline> _polylines = {};
  Set<Marker>   _markers   = {};

  // ── Animated bus ──────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];
  int          _busIdx      = 0;
  double       _busHeading  = 0;
  Timer?       _animTimer;

  // ── GPS ────────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _gpsSub;
  LatLng? _driverLatLng;

  // ── Route state ────────────────────────────────────────────────────────────
  bool _routeLoaded  = false;
  bool _routeFetched = false;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final auth = Provider.of<Authentication>(context, listen: false);
    _driverUid = auth.auth.currentUser!.uid;
    _stream = FirebaseFirestore.instance
        .collection('request')
        .where('driverId', isEqualTo: _driverUid)
        .snapshots();
    _startGps();
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }

  // ── Live GPS stream ────────────────────────────────────────────────────────
  void _startGps() {
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _driverLatLng = ll;
        _busHeading   = pos.heading;
        _updateBusMarker(ll, pos.heading);
      });
      if (_mapCtrl.isCompleted) {
        _mapCtrl.future
            .then((c) => c.animateCamera(CameraUpdate.newLatLng(ll)));
      }
    });
  }

  // ── Fetch route + build map state ─────────────────────────────────────────
  Future<void> _fetchRoute(DocumentSnapshot doc) async {
    if (_routeFetched) return;
    _routeFetched = true;

    final passLat = double.tryParse((doc['startLat']  as String?) ?? '');
    final passLng = double.tryParse((doc['startLong'] as String?) ?? '');
    if (passLat == null || passLng == null) {
      if (mounted) setState(() => _routeLoaded = true);
      return;
    }

    final passLL = LatLng(passLat, passLng);

    // Fresh GPS fix
    LatLng driverLL = _driverLatLng ?? passLL;
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      driverLL = LatLng(p.latitude, p.longitude);
      if (mounted) setState(() => _driverLatLng = driverLL);
    } catch (_) {}

    final straightKm = EtaUtils.haversine(driverLL, passLL);

    // ── Same spot / very close → no OSRM ──────────────────────────────────
    if (straightKm < 0.20) {
      final routePts = straightKm < 0.030 ? <LatLng>[] : [driverLL, passLL];
      if (mounted) {
        setState(() {
          _routeLoaded  = true;
          _routePoints  = routePts;
          _polylines    = routePts.length >= 2
              ? {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    color:      primaryColor.withOpacity(0.6),
                    width:      4,
                    points:     routePts,
                    patterns:   [PatternItem.dash(16), PatternItem.gap(10)],
                    geodesic:   true,
                  ),
                }
              : {};
          _markers = {
            _busMkr(driverLL, 0),
            _passMkr(passLL, doc),
          };
        });
        if (routePts.length >= 2) _startBusAnimation();
        _fitBounds([driverLL, passLL]);
      }
      return;
    }

    // ── Far → OSRM with sanity check ──────────────────────────────────────
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${driverLL.longitude},${driverLL.latitude};'
        '${passLL.longitude},${passLL.latitude}'
        '?overview=full&geometries=polyline',
      );
      final resp = await http
          .get(url, headers: {'User-Agent': 'SafeDriveApp/1.0'})
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['code'] == 'Ok' &&
            (data['routes'] as List).isNotEmpty) {
          final r         = (data['routes'] as List)[0] as Map<String, dynamic>;
          final osrmKm    = (r['distance'] as num).toDouble() / 1000;
          final osrmSecs  = (r['duration'] as num).toDouble();
          final validated = EtaUtils.validateOsrm(osrmKm, osrmSecs, straightKm);

          final pts = PolylinePoints()
              .decodePolyline(r['geometry'] as String)
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();

          final routePts =
              (validated != null && pts.length >= 2) ? pts : [driverLL, passLL];
          final useReal = validated != null && pts.length >= 2;

          if (mounted) {
            setState(() {
              _routeLoaded = true;
              _routePoints = routePts;
              _polylines   = {
                Polyline(
                  polylineId: const PolylineId('route'),
                  color:      useReal
                      ? primaryColor
                      : primaryColor.withOpacity(0.6),
                  width:      5,
                  points:     routePts,
                  patterns:   useReal
                      ? []
                      : [PatternItem.dash(16), PatternItem.gap(10)],
                  jointType:  JointType.round,
                  startCap:   Cap.roundCap,
                  endCap:     Cap.roundCap,
                  geodesic:   true,
                ),
              };
              _markers = {
                _busMkr(driverLL, 0),
                _passMkr(passLL, doc),
              };
            });
            _startBusAnimation();
            _fitBounds([driverLL, passLL]);
          }
          return;
        }
      }
    } catch (_) {}

    // ── Fallback: straight-line dashed route ──────────────────────────────
    if (mounted) {
      setState(() {
        _routeLoaded = true;
        _routePoints = [driverLL, passLL];
        _polylines   = {
          Polyline(
            polylineId: const PolylineId('route'),
            color:      primaryColor.withOpacity(0.6),
            width:      4,
            points:     [driverLL, passLL],
            patterns:   [PatternItem.dash(16), PatternItem.gap(10)],
            geodesic:   true,
          ),
        };
        _markers = {
          _busMkr(driverLL, 0),
          _passMkr(passLL, doc),
        };
      });
      _startBusAnimation();
      _fitBounds([driverLL, passLL]);
    }
  }

  // ── Animate bus icon along route ──────────────────────────────────────────
  void _startBusAnimation() {
    _animTimer?.cancel();
    _animTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted || _routePoints.length < 2) return;
      final nextIdx = (_busIdx + 1) % _routePoints.length;
      final from    = _routePoints[_busIdx];
      final to      = _routePoints[nextIdx];
      final heading = EtaUtils.bearing(from, to);
      setState(() {
        _busIdx     = nextIdx;
        _busHeading = heading;
        _updateBusMarker(to, heading);
      });
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _updateBusMarker(LatLng pos, double heading) {
    _markers = {
      ..._markers.where((m) => m.markerId.value != 'bus'),
      _busMkr(pos, heading),
    };
  }

  Marker _busMkr(LatLng pos, double heading) => Marker(
    markerId: const MarkerId('bus'),
    position: pos,
    rotation: heading,
    flat:     true,
    anchor:   const Offset(0.5, 0.5),
    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    infoWindow: const InfoWindow(title: '🚌 Your Bus'),
    zIndex: 3,
  );

  Marker _passMkr(LatLng pos, DocumentSnapshot doc) => Marker(
    markerId: const MarkerId('passenger'),
    position: pos,
    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    infoWindow: InfoWindow(
      title:   (doc['username']     as String?) ?? 'Passenger',
      snippet: (doc['startAddress'] as String?) ?? '',
    ),
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
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      80,
    ));
  }

  void _markArrived(String requestId) {
    FirebaseFirestore.instance
        .collection('request')
        .doc(requestId)
        .update({'driverArrived': true});
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: WillPopScope(
        onWillPop: () async => false,
        child: StreamBuilder<QuerySnapshot>(
          stream: _stream,
          builder: (context, snap) {
            // Loading
            if (snap.connectionState == ConnectionState.waiting) {
              return _loader('Connecting...');
            }

            // Passenger cancelled
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return _centeredCol([
                const Icon(Icons.cancel_outlined, size: 72, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Passenger cancelled the request',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                BotButton(
                  onTap: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => MainDriverPage()),
                    (r) => false,
                  ),
                  title: 'Back to Requests',
                ),
              ]);
            }

            final doc           = snap.data!.docs.first;
            final requestId     = (doc['id']       as String?) ?? doc.id;
            final passengerName = (doc['username'] as String?) ?? 'Passenger';
            final answered      = doc['answered']      as bool? ?? false;
            final accepted      = doc['accepted']      as bool? ?? false;
            final driverArrived = doc['driverArrived'] as bool? ?? false;
            final journeyStarted= doc['journeyStarted']as bool? ?? false;

            // Passenger declined
            if (answered && !accepted) {
              return _centeredCol([
                const Icon(Icons.thumb_down_alt_outlined,
                    size: 72, color: Colors.orange),
                const SizedBox(height: 16),
                const Text('Passenger declined your offer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Looking for another request...',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                BotButton(
                  onTap: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => MainDriverPage()),
                    (r) => false,
                  ),
                  title: 'Back to Requests',
                ),
              ]);
            }

            // Journey in progress
            if (journeyStarted) {
              return _journeyView(doc, requestId, passengerName);
            }

            // Passenger accepted → navigate to pickup
            if (answered && accepted && !driverArrived) {
              _fetchRoute(doc);
              return _navigatingView(doc, requestId, passengerName);
            }

            // Driver arrived at pickup
            if (driverArrived && accepted && !journeyStarted) {
              return _centeredCol([
                const Icon(Icons.location_on, size: 72, color: Colors.green),
                const SizedBox(height: 16),
                const Text('You have arrived!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Waiting for passenger to board and start the journey.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 20),
                _chatBtn(requestId, passengerName),
              ]);
            }

            // Waiting for passenger to accept
            return _centeredCol([
              const SizedBox(
                width: 60, height: 60,
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
              const SizedBox(height: 20),
              const Text('Waiting for passenger to accept...',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Passenger: $passengerName',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              _chatBtn(requestId, passengerName),
            ]);
          },
        ),
      ),
    );
  }

  // ── Navigating to passenger pickup ────────────────────────────────────────
  Widget _navigatingView(
      DocumentSnapshot doc, String requestId, String passengerName) {
    final size      = MediaQuery.of(context).size;
    final etaStr    = (doc['arrivalTime'] as String?) ?? '?';
    final fromAddr  = (doc['startAddress'] as String?) ?? '';
    final toAddr    = (doc['endAddress']   as String?) ?? '';
    final initLL    = _driverLatLng ??
        LatLng(
          double.tryParse((doc['startLat']  as String?) ?? '31.45') ?? 31.45,
          double.tryParse((doc['startLong'] as String?) ?? '73.13') ?? 73.13,
        );

    return Column(children: [
      // Map
      SizedBox(
        height: size.height * 0.60,
        child: Stack(children: [
          GoogleMap(
            mapType:                 MapType.normal,
            myLocationEnabled:       true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled:     true,
            markers:   _markers,
            polylines: _polylines,
            onMapCreated: (c) {
              if (!_mapCtrl.isCompleted) _mapCtrl.complete(c);
            },
            initialCameraPosition: CameraPosition(target: initLL, zoom: 14),
          ),

          // Loading overlay
          if (!_routeLoaded)
            Positioned(
              top: 12, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6)
                    ],
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: primaryColor),
                    ),
                    SizedBox(width: 8),
                    Text('Loading route...',
                        style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ]),
                ),
              ),
            ),

          // Route loaded badge
          if (_routeLoaded)
            Positioned(
              top: 12, left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6)
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _AnimBus(heading: _busHeading),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('En route to passenger',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: primaryColor)),
                      Text('ETA: $etaStr min',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ]),
              ),
            ),

          // Compass chip
          if (_routeLoaded)
            Positioned(
              bottom: 10, right: 12,
              child: _DirectionChip(heading: _busHeading),
            ),
        ]),
      ),

      // Bottom panel
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _infoRow(Icons.person,       passengerName, Colors.black87),
              const SizedBox(height: 6),
              _infoRow(Icons.trip_origin,  fromAddr,      Colors.green),
              const SizedBox(height: 6),
              _infoRow(Icons.location_on,  toAddr,        Colors.red),
              const Spacer(),
              Row(children: [
                Expanded(child: _chatBtn(requestId, passengerName)),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.location_on, color: Colors.white),
                    label: const Text("I've Arrived",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    onPressed: () => _markArrived(requestId),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    ]);
  }

  // ── Journey in progress ────────────────────────────────────────────────────
  Widget _journeyView(
      DocumentSnapshot doc, String requestId, String passengerName) {
    final size     = MediaQuery.of(context).size;
    final initLL   = _driverLatLng ?? const LatLng(31.4504, 73.1350);
    final toAddr   = (doc['endAddress'] as String?) ?? '';

    return Column(children: [
      SizedBox(
        height: size.height * 0.55,
        child: Stack(children: [
          GoogleMap(
            mapType:                 MapType.normal,
            myLocationEnabled:       true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled:     true,
            markers: _markers
                .where((m) => m.markerId.value == 'bus')
                .toSet(),
            onMapCreated: (c) {
              if (!_mapCtrl.isCompleted) _mapCtrl.complete(c);
            },
            initialCameraPosition:
                CameraPosition(target: initLL, zoom: 15),
          ),
          Positioned(
            top: 12, left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _AnimBus(heading: _busHeading, color: Colors.white),
                const SizedBox(width: 8),
                const Text('Journey in progress',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ]),
            ),
          ),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Icon(Icons.directions_bus, size: 48, color: primaryColor),
            const SizedBox(height: 8),
            const Text('Journey in progress!',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Passenger: $passengerName',
                style: const TextStyle(
                    fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 6),
            _infoRow(Icons.location_on, toAddr, Colors.red),
            const Spacer(),
            const Text(
              'Drop the passenger and wait for them to end the trip.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _chatBtn(requestId, passengerName),
          ]),
        ),
      ),
    ]);
  }

  // ── Small reusable widgets ────────────────────────────────────────────────
  Widget _infoRow(IconData icon, String text, Color color) =>
      Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
      ]);

  Widget _chatBtn(String requestId, String passengerName) =>
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
        ),
        icon: const Icon(Icons.chat_bubble_outline, color: primaryColor),
        label: const Text('Message Passenger',
            style: TextStyle(color: primaryColor, fontSize: 13)),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              requestId: requestId,
              otherName: passengerName,
              isDriver:  true,
            ),
          ),
        ),
      );

  Widget _centeredCol(List<Widget> children) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: children),
        ),
      );

  Widget _loader(String msg) => Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(msg,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 15)),
            ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Animated rotating navigation icon (bus direction)
// ─────────────────────────────────────────────────────────────────────────────
class _AnimBus extends StatefulWidget {
  final double heading;
  final Color  color;
  const _AnimBus({required this.heading, this.color = primaryColor});

  @override
  State<_AnimBus> createState() => _AnimBusState();
}

class _AnimBusState extends State<_AnimBus>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  double _prev = 0;

  @override
  void initState() {
    super.initState();
    _prev = widget.heading * pi / 180;
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _anim = Tween<double>(begin: _prev, end: _prev)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _AnimBus old) {
    super.didUpdateWidget(old);
    if (old.heading != widget.heading) {
      final next = widget.heading * pi / 180;
      _anim = Tween<double>(begin: _prev, end: next)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
      _prev = next;
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Transform.rotate(
          angle: _anim.value,
          child: Icon(Icons.navigation, color: widget.color, size: 22),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Compass direction chip  N / NE / E / SE / S / SW / W / NW
// ─────────────────────────────────────────────────────────────────────────────
class _DirectionChip extends StatelessWidget {
  final double heading;
  const _DirectionChip({required this.heading});

  String get _label {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((heading + 22.5) / 45).floor() % 8];
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.explore, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(_label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ]),
      );
}
