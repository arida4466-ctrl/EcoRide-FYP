import 'package:firebase_database/firebase_database.dart';

class Driver {
  final String id;
  final double lat;
  final double lng;
  final bool isNearest;

  Driver({
    required this.id,
    required this.lat,
    required this.lng,
    this.isNearest = false,
  });

  Driver copyWith({bool? isNearest}) {
    return Driver(
      id: id,
      lat: lat,
      lng: lng,
      isNearest: isNearest ?? this.isNearest,
    );
  }
}

class DriverStreamService {
  final DatabaseReference ref = FirebaseDatabase.instance.ref("drivers");

  Stream<List<Driver>> streamDrivers() {
    return ref.onValue.map((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return [];

      return data.entries.map((e) {
        final val = e.value as Map;

        return Driver(
          id: e.key,
          lat: (val['lat'] as num).toDouble(),
          lng: (val['lng'] as num).toDouble(),
        );
      }).toList();
    });
  }
}