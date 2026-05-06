import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:indriver_clone/driver/screens/drivermap.dart';
import 'package:indriver_clone/models/requests.dart';
import 'package:indriver_clone/ui/constants.dart';

class RideRequests extends StatefulWidget {
  const RideRequests({Key? key}) : super(key: key);
  @override
  _RideRequestsState createState() => _RideRequestsState();
}

class _RideRequestsState extends State<RideRequests>
    with AutomaticKeepAliveClientMixin {

  // NO orderBy — avoids composite-index requirement that silently kills the
  // stream on most projects. We sort newest-first client-side instead.
  final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('request')
      .where('accepted', isEqualTo: false)
      .where('driverAccepted', isEqualTo: false)
      .snapshots();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.wifi_off, size: 60, color: Colors.red.shade300),
                  const SizedBox(height: 12),
                  Text('Error: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                  const SizedBox(height: 8),
                  const Text(
                    'Check Firestore rules or index.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ]),
              ),
            );
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.inbox_outlined, size: 72, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text('No ride requests right now',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 6),
                const Text('New requests appear here instantly',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              ]),
            );
          }

          // Sort newest-first client-side
          final docs = [...snap.data!.docs];
          docs.sort((a, b) {
            final ta = (a['timeCreated'] as String?) ?? '';
            final tb = (b['timeCreated'] as String?) ?? '';
            return tb.compareTo(ta);
          });

          return Column(children: [
            Container(
              width: double.infinity,
              color: primaryColor.withOpacity(0.08),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              child: Text(
                '${docs.length} pending request${docs.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: docs.length,
                padding: const EdgeInsets.all(10),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final req = RideRequest.fromDocument(docs[i]);
                  return _RequestCard(request: req);
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final RideRequest request;
  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(
              backgroundColor: primaryColor,
              radius: 18,
              child: Icon(Icons.person, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(request.username ?? 'Passenger',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(_timeAgo(request.timeCreated),
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Text('New',
                  style: TextStyle(
                      color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 12),
          _row(Icons.trip_origin, Colors.green, 'From', request.startAddress ?? 'Unknown'),
          const SizedBox(height: 4),
          _row(Icons.location_on, Colors.red, 'To', request.endAddress ?? 'Unknown'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.directions_bus, color: Colors.white, size: 18),
              label: const Text('View Details & Accept',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DriverMap(request: request)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(IconData icon, Color color, String label, String val) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              children: [
                TextSpan(text: '$label: ', style: const TextStyle(color: Colors.grey)),
                TextSpan(text: val, style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ]);

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final t = DateTime.parse(iso);
      final ago = DateTime.now().difference(t);
      if (ago.inSeconds < 60) return 'Just now';
      if (ago.inMinutes < 60) return '${ago.inMinutes}m ago';
      return '${ago.inHours}h ago';
    } catch (_) {
      return '';
    }
  }
}
