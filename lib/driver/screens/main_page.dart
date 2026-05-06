import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_toggle_tab/flutter_toggle_tab.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:indriver_clone/driver/screens/earnings.dart';
import 'package:indriver_clone/driver/screens/rating.dart';
import 'package:indriver_clone/driver/screens/ride_requests.dart';
import 'package:indriver_clone/providers/auth.dart';
import 'package:indriver_clone/services/location_service.dart';
import 'package:indriver_clone/ui/constants.dart';
import 'package:indriver_clone/ui/nav_drawer.dart';
import 'package:provider/provider.dart';

const LatLng _fsdCenter = LatLng(31.4504, 73.1350);

class MainDriverPage extends StatefulWidget {
  MainDriverPage({Key? key}) : super(key: key);

  @override
  _MainDriverPageState createState() => _MainDriverPageState();
}

class _MainDriverPageState extends State<MainDriverPage> {
  PageController? pageController;
  int _selectedIndex = 0;
  int toggleIndex = 0;

  // ── Self-location map ──────────────────────────────────────────────────────
  final Completer<GoogleMapController> _mapCtrl = Completer();
  LatLng _currentPos = _fsdCenter;
  Set<Marker> _selfMarker = {};
  StreamSubscription<Position>? _posSub;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    pageController = PageController();
    final user =
        Provider.of<Authentication>(context, listen: false).loggedUser;
    toggleIndex = user.isOnline == true ? 1 : 0;

    // If driver was already online when screen opens, resume tracking
    if (toggleIndex == 1) _startTracking();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    pageController!.dispose();
    super.dispose();
  }

  // ── Start GPS tracking + RTDB sync ────────────────────────────────────────
  Future<void> _startTracking() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enable Location Services'),
        ));
      }
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) async {
      if (!mounted) return;
      final latlng = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _currentPos = latlng;
        _selfMarker = {
          Marker(
            markerId: const MarkerId('self'),
            position: latlng,
            // Green hue so driver can clearly see their own bus
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(
              title: '🚌 You are here',
              snippet: 'Your live position',
            ),
            zIndex: 3,
          ),
        };
      });

      // Pan camera to follow driver
      if (_mapReady) {
        final ctrl = await _mapCtrl.future;
        ctrl.animateCamera(CameraUpdate.newLatLng(latlng));
      }
    });
  }

  void _stopTracking() {
    _posSub?.cancel();
    _posSub = null;
    setState(() => _selfMarker = {});
  }

  void _onTapped(int index) {
    setState(() => _selectedIndex = index);
    pageController!.jumpToPage(index);
  }

  void onPageChanged(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = toggleIndex == 1;

    return Scaffold(
      drawer: const NavDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: primaryColor),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Center(
          child: FlutterToggleTab(
            selectedBackgroundColors: const [primaryColor],
            width: 40,
            height: 30,
            borderRadius: 25,
            selectedTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            unSelectedTextStyle: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            labels: const ['offline', 'online'],
            selectedLabelIndex: (index) {
              final provider =
              Provider.of<Authentication>(context, listen: false);
              setState(() => toggleIndex = index);
              if (toggleIndex == 1) {
                provider.goOnline(context);
                _startTracking();
              } else {
                provider.goOffline(context);
                _stopTracking();
              }
            },
            selectedIndex: toggleIndex,
          ),
        ),
        actions: [
          // Status dot
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? Colors.green : Colors.grey,
                  boxShadow: isOnline
                      ? [
                    BoxShadow(
                        color: Colors.green.withOpacity(0.5),
                        blurRadius: 6)
                  ]
                      : [],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Live location mini-map (only when ONLINE) ──────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: isOnline ? 200 : 0,
            child: isOnline
                ? Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPos,
                    zoom: 15,
                  ),
                  onMapCreated: (ctrl) {
                    if (!_mapCtrl.isCompleted) {
                      _mapCtrl.complete(ctrl);
                    }
                    setState(() => _mapReady = true);
                  },
                  myLocationEnabled: false,
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  markers: _selfMarker,
                  mapType: MapType.normal,
                ),

                // Green "Live" label
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4)
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.location_on,
                            color: Colors.white, size: 13),
                        SizedBox(width: 4),
                        Text('Live Location',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

                // Coordinates badge
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_currentPos.latitude.toStringAsFixed(4)}, '
                          '${_currentPos.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ],
            )
                : const SizedBox.shrink(),
          ),

          // ── Offline banner ─────────────────────────────────────────────
          if (!isOnline)
            Container(
              width: double.infinity,
              color: Colors.grey.shade200,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: const Center(
                child: Text(
                  '⚫ You are offline — toggle to go online',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ),

          // ── Page view: requests / earnings / ratings ───────────────────
          Expanded(
            child: PageView(
              controller: pageController,
              onPageChanged: onPageChanged,
              children: [
                const RideRequests(),
                Earnings(),
                Ratings(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        onTap: _onTapped,
        currentIndex: _selectedIndex,
        selectedItemColor: primaryColor,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.menu), label: 'Ride Requests'),
          BottomNavigationBarItem(
              icon: Icon(Icons.attach_money), label: 'My earnings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.star_border), label: 'Rating'),
        ],
      ),
    );
  }
}