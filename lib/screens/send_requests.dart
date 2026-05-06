import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:indriver_clone/models/requests.dart';
import 'package:indriver_clone/models/user.dart';
import 'package:indriver_clone/providers/auth.dart';
import 'package:indriver_clone/providers/handle.dart';
import 'package:indriver_clone/screens/chat_screen.dart';
import 'package:indriver_clone/screens/homepage.dart';
import 'package:indriver_clone/services/location_service.dart';
import 'package:indriver_clone/ui/button.dart';
import 'package:indriver_clone/ui/constants.dart';
import 'package:provider/provider.dart';

class SendingRequests extends StatefulWidget {
  const SendingRequests({Key? key}) : super(key: key);
  @override
  _SendingRequestsState createState() => _SendingRequestsState();
}

class _SendingRequestsState extends State<SendingRequests> {
  Stream<QuerySnapshot>? _stream;
  UserModel? _user;
  String? _passengerId;
  final _locService = LocationService();
  String? _watchingDriverId;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<Authentication>(context, listen: false);
    _user        = auth.loggedUser;
    _passengerId = auth.auth.currentUser!.uid;

    _stream = FirebaseFirestore.instance
        .collection('request')
        .where('id', isEqualTo: _passengerId)
        .snapshots();

    // Show all buses while waiting
    _locService.startPassengerDriverStream(
        onUpdate: (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _locService.stopPassengerDriverStream();
    super.dispose();
  }

  void _watchDriver(String uid) {
    if (_watchingDriverId == uid) return;
    _watchingDriverId = uid;
    _locService.showOnlyDriver(uid,
        onUpdate: (_) { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    final loc = Provider.of<AppHandler>(context, listen: false);

    return Scaffold(
      backgroundColor: Colors.white,
      body: WillPopScope(
        onWillPop: () async => false,
        child: StreamBuilder<QuerySnapshot>(
          stream: _stream,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting)
              return _loader('Connecting...');
            if (snap.hasError)
              return _msg('Something went wrong.');

            // Request gone — passenger cancelled or driver removed it
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.pushAndRemoveUntil(ctx,
                    MaterialPageRoute(builder: (_) => HomePage()),
                        (r) => false);
              });
              return _loader('Returning home...');
            }

            final doc        = snap.data!.docs.first;
            final req        = RideRequest.fromDocument(doc);
            final driverId   = (doc['driverId']   as String?) ?? '';
            final driverName = (doc['driverName'] as String?) ?? 'Driver';
            final eta        = (doc['arrivalTime'] as String?) ?? '?';

            // Journey finished
            if (doc['journeyStarted'] == true) {
              return _simpleAction(
                icon: Icons.flag, color: Colors.green,
                title: 'Journey in progress!',
                subtitle: 'Driver: $driverName',
                btnLabel: 'Finish & Rate',
                onTap: () => _showReview(ctx, driverId,
                    _user?.username ?? '', _user?.id ?? '',
                    req.price ?? '0'),
                extra: _chatBtn(ctx, driverId, driverName),
              );
            }

            // Driver arrived
            if (doc['driverArrived'] == true && doc['accepted'] == true) {
              return _simpleAction(
                icon: Icons.directions_bus, color: primaryColor,
                title: '🚌 Driver has arrived!',
                subtitle: 'Driver: $driverName',
                btnLabel: 'Start Journey',
                onTap: () => _startJourney(),
                extra: _chatBtn(ctx, driverId, driverName),
              );
            }

            // Passenger accepted → live moving bus on map
            if (doc['accepted'] == true && doc['answered'] == true &&
                driverId.isNotEmpty) {
              _watchDriver(driverId);
              return _liveDriverView(ctx, driverId, driverName, eta);
            }

            // Driver sent offer
            final arrival = (doc['arrivalTime'] as String?) ?? '';
            if ((doc['driverAccepted'] as bool? ?? false) &&
                arrival.isNotEmpty) {
              return _driverOffer(ctx, driverName, arrival);
            }

            // Waiting — all buses on map + sorted recommendation list
            return _waitingView(ctx, loc);
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  LIVE DRIVER VIEW — bus moves & rotates in real-time
  // ══════════════════════════════════════════════════════════════════════════
  Widget _liveDriverView(BuildContext ctx, String driverId,
      String driverName, String eta) {
    final size = MediaQuery.of(ctx).size;

    return Column(children: [
      // Map with the moving, rotating bus marker
      SizedBox(
        height: size.height * 0.55,
        child: Stack(children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
                target: LatLng(31.4504, 73.1350), zoom: 14),
            myLocationEnabled: true,
            // driverMarkers already has rotation=heading set in LocationService
            markers: _locService.driverMarkers,
            mapType: MapType.normal,
            zoomControlsEnabled: true,
            myLocationButtonEnabled: true,
          ),

          // Overlay: driver info + ETA
          Positioned(
            bottom: 10, left: 10, right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6)
                ],
              ),
              child: Row(children: [
                // Animated rotating bus icon (mirrors real heading)
                _RotatingBus(driverId: driverId),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driverName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Row(children: [
                        const Icon(Icons.access_time,
                            size: 13, color: primaryColor),
                        const SizedBox(width: 4),
                        Text('ETA: $eta min',
                            style: const TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ]),
                    ],
                  ),
                ),
                _chatBtn(ctx, driverId, driverName),
              ]),
            ),
          ),
        ]),
      ),

      // Bottom info
      Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.directions_bus,
                  size: 52, color: primaryColor),
              const SizedBox(height: 10),
              const Text('Bus is on the way!',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('ETA: $eta minutes',
                  style: const TextStyle(
                      fontSize: 16,
                      color: primaryColor,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Watch the bus move on the map above',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WAITING — all buses visible on map + sorted recommendation list
  // ══════════════════════════════════════════════════════════════════════════
  Widget _waitingView(BuildContext ctx, AppHandler loc) {
    final size   = MediaQuery.of(ctx).size;
    final sorted = _locService.nearestSorted;

    return Column(children: [
      SizedBox(
        height: size.height * 0.45,
        child: Stack(children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
                target: LatLng(31.4504, 73.1350), zoom: 13),
            myLocationEnabled: true,
            markers: _locService.driverMarkers,
            mapType: MapType.normal,
            zoomControlsEnabled: true,
            myLocationButtonEnabled: true,
          ),
          Positioned(
            top: 10, left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4)
                  ]),
              child: Row(children: [
                const Icon(Icons.directions_bus,
                    color: primaryColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${_locService.activeDrivers.length} active bus(es)',
                  style: const TextStyle(
                      fontSize: 12,
                      color: primaryColor,
                      fontWeight: FontWeight.bold),
                ),
              ]),
            ),
          ),
        ]),
      ),

      // Recommendation list
      const Padding(
        padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Recommended buses nearby',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: primaryColor)),
        ),
      ),

      Expanded(
        child: sorted.isEmpty
            ? const Center(
            child: Text('Looking for buses...',
                style: TextStyle(color: Colors.grey)))
            : ListView.separated(
          itemCount: sorted.length,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          separatorBuilder: (_, __) =>
          const Divider(height: 1),
          itemBuilder: (_, i) {
            final d    = sorted[i];
            final dist = _locService.distanceTo(d);
            return ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: d.isNearest
                      ? Colors.amber.shade100
                      : Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.directions_bus,
                    size: 22,
                    color: d.isNearest
                        ? Colors.amber.shade800
                        : Colors.blue),
              ),
              title: Text(
                d.isNearest
                    ? '★ Nearest — Recommended'
                    : 'Bus ${i + 1}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: d.isNearest
                        ? Colors.amber.shade800
                        : Colors.black87),
              ),
              subtitle: dist.isNotEmpty
                  ? Text(dist,
                  style: const TextStyle(fontSize: 12))
                  : null,
              trailing: d.isNearest
                  ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius:
                    BorderRadius.circular(12)),
                child: const Text('Closest',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.brown)),
              )
                  : null,
            );
          },
        ),
      ),

      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12)),
          icon: const Icon(Icons.cancel_outlined, color: Colors.red),
          label: const Text('Cancel Request',
              style: TextStyle(color: Colors.red, fontSize: 15)),
          onPressed: () async {
            await loc.removeRequest();
            if (mounted) {
              Navigator.pushAndRemoveUntil(ctx,
                  MaterialPageRoute(builder: (_) => HomePage()),
                      (r) => false);
            }
          },
        ),
      ),
    ]);
  }

  // ── Driver offer ───────────────────────────────────────────────────────────
  Widget _driverOffer(
      BuildContext ctx, String driverName, String arrival) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_bus,
                size: 80, color: primaryColor),
            const SizedBox(height: 16),
            Text(driverName,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.access_time,
                    color: primaryColor, size: 18),
                const SizedBox(width: 6),
                Text('Arrives in $arrival minutes',
                    style: const TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ]),
            ),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding:
                      const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Accept',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16)),
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('request')
                        .doc(_passengerId)
                        .update(
                        {'accepted': true, 'answered': true});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding:
                      const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text('Decline',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16)),
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('request')
                        .doc(_passengerId)
                        .update({
                      'accepted': false,
                      'answered': false,
                      'driverId': '',
                      'driverAccepted': false,
                      'arrivalTime': '',
                      'driverName': '',
                    });
                  },
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _chatBtn(BuildContext ctx, String driverId, String driverName) {
    return IconButton(
      icon: const Icon(Icons.chat_bubble_outline, color: primaryColor),
      tooltip: 'Message driver',
      onPressed: () => Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => ChatScreen(
          requestId: _passengerId!,
          otherName: driverName,
          isDriver:  false,
        ),
      )),
    );
  }

  Widget _loader(String msg) => Center(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(msg,
                style: const TextStyle(color: Colors.grey, fontSize: 15)),
          ]));

  Widget _msg(String m) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(m,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16))));

  Widget _simpleAction({
    required IconData icon, required Color color,
    required String title, String subtitle = '',
    required String btnLabel, required VoidCallback onTap,
    Widget? extra,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 80, color: color),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 15, color: Colors.grey)),
              ],
              if (extra != null) ...[
                const SizedBox(height: 8), extra
              ],
              const SizedBox(height: 28),
              BotButton(onTap: onTap, title: btnLabel),
            ],
          ),
        ),
      );

  Future<void> _startJourney() async {
    await FirebaseFirestore.instance
        .collection('request')
        .doc(_passengerId)
        .update({'journeyStarted': true});
  }

  final _reviewCtrl = TextEditingController();
  void _showReview(BuildContext ctx, String driverId,
      String username, String userId, String price) {
    double rating = 3.0;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dlgCtx) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('Rate Your Driver'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RatingBar.builder(
                initialRating: rating, minRating: 1,
                direction: Axis.horizontal, allowHalfRating: true,
                itemCount: 5,
                itemPadding:
                const EdgeInsets.symmetric(horizontal: 4),
                itemBuilder: (_, __) =>
                const Icon(Icons.star, color: Colors.amber),
                onRatingUpdate: (r) => rating = r,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reviewCtrl,
                decoration: const InputDecoration(
                  hintText: 'Comment (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ]),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor),
              child: const Text('Submit',
                  style: TextStyle(color: Colors.white)),
              onPressed: () async {
                if (driverId.isNotEmpty) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(driverId)
                      .update({
                    'trips':    FieldValue.increment(1),
                    'rating':   FieldValue.increment(rating),
                    'earnings': FieldValue.increment(
                        double.tryParse(price) ?? 0),
                  });
                  await FirebaseFirestore.instance
                      .collection('reviews')
                      .add({
                    'driverId': driverId,
                    'userName': username,
                    'userId':   userId,
                    'review':   _reviewCtrl.text.trim(),
                    'rating':   rating,
                  });
                }
                final l =
                Provider.of<AppHandler>(ctx, listen: false);
                await l.removeRequest();
                if (mounted) {
                  Navigator.of(dlgCtx).pop();
                  Navigator.pushAndRemoveUntil(ctx,
                      MaterialPageRoute(builder: (_) => HomePage()),
                          (r) => false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ROTATING BUS ICON — reads heading from RTDB every second
// ══════════════════════════════════════════════════════════════════════════════
class _RotatingBus extends StatelessWidget {
  final String driverId;
  const _RotatingBus({required this.driverId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance
          .ref('drivers/$driverId/heading')
          .onValue,
      builder: (_, snap) {
        double heading = 0;
        if (snap.hasData && snap.data!.snapshot.value != null) {
          heading =
              (snap.data!.snapshot.value as num).toDouble();
        }
        // Convert degrees to radians for Transform.rotate
        final radians = heading * (3.14159265 / 180.0);
        return Transform.rotate(
          angle: radians,
          child: const Icon(
            Icons.navigation, // arrow pointing up = north
            color: primaryColor,
            size: 36,
          ),
        );
      },
    );
  }
}