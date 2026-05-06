import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:indriver_clone/models/address.dart';
import 'package:indriver_clone/models/place_predications.dart';
import 'package:indriver_clone/providers/auth.dart';
import 'package:indriver_clone/providers/handle.dart';
import 'package:indriver_clone/screens/account_details.dart';
import 'package:indriver_clone/screens/send_requests.dart';
import 'package:indriver_clone/services/location_service.dart';
import 'package:indriver_clone/ui/app_bar.dart';
import 'package:indriver_clone/ui/button.dart';
import 'package:indriver_clone/ui/constants.dart';
import 'package:indriver_clone/ui/nav_drawer.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final LatLng _center     = const LatLng(31.4504, 73.1350);
  final _locService        = LocationService();
  final _destCtrl          = TextEditingController();
  final _pickupCtrl        = TextEditingController();
  bool _showDestSearch     = false;
  bool _showPickupSearch   = false;
  bool _searching          = false;
  bool _showNearestList    = false; // toggle nearest bus list panel

  late Stream<QuerySnapshot> _userStream;

  void _onMapCreated(GoogleMapController ctrl) {
    final p = Provider.of<AppHandler>(context, listen: false);
    p.mapController = ctrl;
    p.locatePosition(context);
    if (p.liveLocation != null) {
      _locService.passengerLatLng =
          LatLng(p.liveLocation!.latitude, p.liveLocation!.longitude);
    }
  }

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseFirestore.instance
        .collection('users')
        .where('id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .snapshots();

    // ── Start listening to ALL driver buses immediately ──────────────────
    _locService.startPassengerDriverStream(
      onUpdate: (_) { if (mounted) setState(() {}); },
    );
  }

  @override
  void dispose() {
    _locService.stopPassengerDriverStream();
    _destCtrl.dispose();
    _pickupCtrl.dispose();
    super.dispose();
  }

  // ── Select from prediction list ─────────────────────────────────────────
  Future<void> _selectPrediction(
      Prediction p, AppHandler loc, {required bool isDest}) async {
    final address = Address(
      placeId:   p.id,
      placeName: p.mainText,
      latitude:  p.lat,
      longitude: p.lng,
    );
    if (isDest) {
      loc.updateDestinationLocationAdress(address);
      loc.clearPredictions();
      setState(() { _destCtrl.text = p.mainText ?? ''; _showDestSearch = false; });
      await loc.getDirection(context);
    } else {
      loc.updatePickupLocationAdress(address);
      loc.clearPredictions();
      setState(() { _pickupCtrl.text = p.mainText ?? ''; _showPickupSearch = false; });
    }
  }

  // ── Confirm free typed text ─────────────────────────────────────────────
  Future<void> _confirmText(AppHandler loc, {required bool isDest}) async {
    final text = (isDest ? _destCtrl.text : _pickupCtrl.text).trim();
    if (text.isEmpty) return;
    setState(() => _searching = true);
    await loc.findPlace(text);
    setState(() => _searching = false);

    if (loc.predictionList.isNotEmpty) {
      await _selectPrediction(loc.predictionList.first, loc, isDest: isDest);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '⚠️ "$text" not found in Faisalabad. Please select from the list.'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final auth = Provider.of<Authentication>(context, listen: false);

    return StreamBuilder<QuerySnapshot>(
      stream: _userStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snap.data!.docs.isEmpty) return const CompleteSignUp();

        return Scaffold(
          drawer: const NavDrawer(),
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.white,
          appBar: const HomeAppBar(),
          body: Stack(
            children: [
              // ── Full screen map ────────────────────────────────────
              Consumer<AppHandler>(
                builder: (_, loc, __) {
                  if (loc.liveLocation != null) {
                    _locService.passengerLatLng = LatLng(
                        loc.liveLocation!.latitude,
                        loc.liveLocation!.longitude);
                  }
                  // All bus markers + route markers
                  final allMarkers = {
                    ...loc.markersSet,
                    ..._locService.driverMarkers,
                  };
                  return SizedBox(
                    height: size.height,
                    child: GoogleMap(
                      mapType: MapType.normal,
                      myLocationEnabled: true,
                      markers:   allMarkers,
                      circles:   loc.circlesSet,
                      polylines: loc.polylineSet,
                      onMapCreated: _onMapCreated,
                      initialCameraPosition:
                      CameraPosition(target: _center, zoom: 14),
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled:    true,
                      zoomGesturesEnabled:    true,
                    ),
                  );
                },
              ),

              // ── Nearest buses floating button (top right) ──────────
              Positioned(
                top: 100, right: 12,
                child: FloatingActionButton.small(
                  heroTag: 'busListBtn',
                  backgroundColor: _locService.activeDrivers.isEmpty
                      ? Colors.grey
                      : primaryColor,
                  child: const Icon(Icons.directions_bus, color: Colors.white),
                  onPressed: () =>
                      setState(() => _showNearestList = !_showNearestList),
                  tooltip: 'See nearest buses',
                ),
              ),

              // ── Nearest buses panel ────────────────────────────────
              if (_showNearestList)
                Positioned(
                  top: 145, right: 12,
                  child: _NearestBusPanel(
                    locService: _locService,
                    onClose: () =>
                        setState(() => _showNearestList = false),
                  ),
                ),

              // ── Bottom panel ───────────────────────────────────────
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [BoxShadow(
                        color: Colors.black26, blurRadius: 10,
                        offset: Offset(0, -2))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // drag handle
                      Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 6),
                        width: 36, height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)),
                      ),

                      // bus count strip
                      if (_locService.activeDrivers.isNotEmpty)
                        Container(
                          width: double.infinity,
                          color: primaryColor.withOpacity(0.08),
                          padding: const EdgeInsets.symmetric(
                              vertical: 5, horizontal: 14),
                          child: Row(children: [
                            const Icon(Icons.directions_bus,
                                color: primaryColor, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${_locService.activeDrivers.length} active bus(es) near Faisalabad',
                              style: const TextStyle(
                                  color: primaryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                          ]),
                        ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                        child: Consumer<AppHandler>(
                          builder: (_, loc, __) {
                            if (loc.liveLocation != null) {
                              _locService.passengerLatLng = LatLng(
                                  loc.liveLocation!.latitude,
                                  loc.liveLocation!.longitude);
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Pickup
                                _Field(
                                  controller: _pickupCtrl,
                                  hint: loc.startSelected
                                      ? loc.startpoint : 'Pickup location',
                                  icon: Icons.circle, iconColor: startMarker,
                                  isActive: _showPickupSearch, isLoading: false,
                                  onTap: () {
                                    setState(() {
                                      _showPickupSearch = true;
                                      _showDestSearch   = false;
                                    });
                                    _pickupCtrl.text = loc.startSelected
                                        ? loc.startpoint : '';
                                    loc.clearPredictions();
                                  },
                                  onChanged: (v) {
                                    setState(() => _showPickupSearch = true);
                                    loc.findPlace(v);
                                  },
                                  onSubmitted: (_) =>
                                      _confirmText(loc, isDest: false),
                                  onClear: () {
                                    setState(() {
                                      _showPickupSearch = false;
                                      _pickupCtrl.clear();
                                    });
                                    loc.clearPredictions();
                                  },
                                ),
                                const SizedBox(height: 8),

                                // Destination
                                _Field(
                                  controller: _destCtrl,
                                  hint: loc.endSelected
                                      ? loc.endpoint : 'Enter destination',
                                  icon: Icons.location_on,
                                  iconColor: endMarker,
                                  isActive: _showDestSearch,
                                  isLoading: _searching,
                                  onTap: () {
                                    setState(() {
                                      _showDestSearch   = true;
                                      _showPickupSearch = false;
                                    });
                                    _destCtrl.text =
                                    loc.endSelected ? loc.endpoint : '';
                                    loc.clearPredictions();
                                  },
                                  onChanged: (v) {
                                    setState(() => _showDestSearch = true);
                                    loc.findPlace(v);
                                  },
                                  onSubmitted: (_) =>
                                      _confirmText(loc, isDest: true),
                                  onClear: () {
                                    setState(() {
                                      _showDestSearch = false;
                                      _destCtrl.clear();
                                    });
                                    loc.clearPredictions();
                                    loc.destinationLocation = null;
                                    loc.endpoint   = 'End point';
                                    loc.endSelected = false;
                                    loc.notifyListeners();
                                  },
                                ),

                                // Predictions
                                if ((_showDestSearch || _showPickupSearch) &&
                                    loc.predictionList.isNotEmpty)
                                  _PredList(
                                    preds: loc.predictionList,
                                    onTap: (p) => _selectPrediction(p, loc,
                                        isDest: _showDestSearch),
                                  ),

                                const SizedBox(height: 12),

                                // Request button
                                BotButton(
                                  onTap: () {
                                    if (loc.endSelected &&
                                        loc.destinationLocation != null) {
                                      loc.sendRequest(
                                        loc.pickupLocation!.latitude!.toString(),
                                        loc.pickupLocation!.longitude!.toString(),
                                        false,
                                        auth.loggedUser.username!,
                                        DateTime.now().toString(),
                                        '672617465',
                                        loc.pickupLocation!.placeName!,
                                        loc.destinationLocation!.placeName!,
                                        loc.destinationLocation!.latitude!.toString(),
                                        loc.destinationLocation!.longitude!.toString(),
                                        '0',
                                      );
                                      Navigator.push(context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                              const SendingRequests()));
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Please select a destination first'),
                                        duration: Duration(seconds: 2),
                                      ));
                                    }
                                  },
                                  title: 'Request a vehicle',
                                ),
                                const SizedBox(height: 16),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Nearest buses panel ───────────────────────────────────────────────────────
class _NearestBusPanel extends StatelessWidget {
  final LocationService locService;
  final VoidCallback onClose;

  const _NearestBusPanel(
      {required this.locService, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final sorted = locService.nearestSorted;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 230,
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
              child: Row(children: [
                const Icon(Icons.directions_bus,
                    color: primaryColor, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Buses Near You',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: primaryColor)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onClose,
                ),
              ]),
            ),
            const Divider(height: 1),

            if (sorted.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No active buses right now',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d    = sorted[i];
                    final dist = locService.distanceTo(d);
                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: d.isNearest
                              ? Colors.amber.shade100
                              : Colors.blue.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.directions_bus,
                          size: 18,
                          color: d.isNearest ? Colors.amber.shade800 : Colors.blue,
                        ),
                      ),
                      title: Text(
                        d.isNearest ? '★ Recommended' : 'Bus ${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: d.isNearest
                              ? Colors.amber.shade800
                              : Colors.black87,
                        ),
                      ),
                      subtitle: dist.isNotEmpty
                          ? Text(dist,
                          style: const TextStyle(fontSize: 11))
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Search field ──────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final bool isActive, isLoading;
  final VoidCallback onTap, onClear;
  final ValueChanged<String> onChanged, onSubmitted;

  const _Field({
    required this.controller, required this.hint,
    required this.icon, required this.iconColor,
    required this.isActive, required this.isLoading,
    required this.onTap, required this.onClear,
    required this.onChanged, required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? primaryColor : Colors.grey.shade300,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        Expanded(
          child: TextField(
            controller:      controller,
            onTap:           onTap,
            onChanged:       onChanged,
            onSubmitted:     onSubmitted,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
              TextStyle(color: Colors.grey.shade500, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (isActive || controller.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.grey),
            onPressed: onClear,
            padding:     EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
      ]),
    );
  }
}

// ── Prediction list ───────────────────────────────────────────────────────────
class _PredList extends StatelessWidget {
  final List<Prediction> preds;
  final ValueChanged<Prediction> onTap;
  const _PredList({required this.preds, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: preds.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = preds[i];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.location_on,
                size: 18, color: primaryColor),
            title: Text(p.mainText ?? '',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            subtitle: Text(p.subtitle ?? '',
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis),
            onTap: () => onTap(p),
          );
        },
      ),
    );
  }
}