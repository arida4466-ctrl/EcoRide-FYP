import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:indriver_clone/driver/screens/main_page.dart';
import 'package:indriver_clone/models/user.dart';
import 'package:indriver_clone/screens/homepage.dart';
import 'package:indriver_clone/services/location_service.dart';

enum AuthState { loggedIn, loggedOut }

class Authentication with ChangeNotifier {
  AuthState _loginState = AuthState.loggedOut;
  get loginState => _loginState;

  UserModel loggedUser = UserModel();
  final _firestore = FirebaseFirestore.instance;
  FirebaseAuth auth = FirebaseAuth.instance;
  DatabaseReference db = FirebaseDatabase.instance.ref();

  Authentication() {
    init();
  }

  Future<void> init() async {
    auth.userChanges().listen((user) async {
      _loginState =
      user != null ? AuthState.loggedIn : AuthState.loggedOut;
      notifyListeners();
    });
    loggedUser = await returnUser();
    notifyListeners();
  }

  UserModel? getUser(User? user) =>
      user == null ? null : UserModel(id: user.uid);

  Stream<UserModel?> onAuthStateChanged() =>
      auth.authStateChanges().map(getUser);

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    await LocationService().stopDriverLocationStream();
    await auth.signOut();
    notifyListeners();
  }

  // ── Email / Password LOGIN ─────────────────────────────────────────────────
  Future<void> loginWithEmail({
    required String email,
    required String password,
    required bool isDriver,
    required BuildContext context,
  }) async {
    try {
      final result = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final doc = await _firestore
          .collection('users')
          .doc(result.user!.uid)
          .get();

      if (!doc.exists) {
        _snack(context, 'Account not found. Please register first.');
        await auth.signOut();
        return;
      }

      final accountIsDriver = doc.data()!['isDriver'] == true;

      // Block wrong tab login
      if (accountIsDriver != isDriver) {
        await auth.signOut();
        _snack(
          context,
          isDriver
              ? 'This is a Passenger account. Use the Passenger tab.'
              : 'This is a Driver account. Use the Driver tab.',
        );
        return;
      }

      loggedUser = await returnUser();
      notifyListeners();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => isDriver ? MainDriverPage() : HomePage(),
        ),
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _snack(context, e.message ?? 'Login failed');
    }
  }

  // ── Email / Password REGISTER ──────────────────────────────────────────────
  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String username,
    required String phone,
    required bool isDriver,
    required BuildContext context,
  }) async {
    try {
      final result = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = result.user!.uid;

      await _firestore.collection('users').doc(uid).set({
        'id': uid,
        'firstName': firstName,
        'lastName': lastName,
        'username': username,
        'email': email,
        'phoneNumber': phone,
        'isOnline': false,
        'isDriver': isDriver,
        'driverAccount': isDriver,
        'token': '',
        'photo': '',
        'votes': 0,
        'trips': 0,
        'rating': 0.0,
        'isAdmin': false,
        'submittedStatus': isDriver ? 'waiting' : '',
        'verified': false,
        'earnings': 0.0,
        'driverName': isDriver ? '$firstName $lastName' : '',
        'driverNumber': isDriver ? phone : '',
        'licenceNo': '',
        'carplatenum': '',
        'idNo': '',
        'dob': '',
      });

      loggedUser = await returnUser();
      notifyListeners();

      _snack(context, 'Account created! Welcome 🎉');

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => isDriver ? MainDriverPage() : HomePage(),
        ),
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _snack(context, e.message ?? 'Registration failed');
    }
  }

  // ── completeprofile (used by account_details.dart) ────────────────────────
  Future<void> completeprofile(
      String firstname,
      String lastname,
      String username,
      String dob,
      String email,
      BuildContext context,
      ) async {
    final uid = auth.currentUser!.uid;
    Map<String, dynamic> usermap = {
      'id': uid,
      'firstName': firstname,
      'phoneNumber': auth.currentUser!.phoneNumber ?? '',
      'username': username,
      'isOnline': false,
      'isDriver': false,
      'lastName': lastname,
      'email': email,
      'token': '',
      'photo': '',
      'licenceNo': '',
      'carplatenum': '',
      'idNo': '',
      'votes': 0,
      'trips': 0,
      'rating': 0.0,
      'dob': dob,
      'driverAccount': false,
      'isAdmin': false,
      'submittedStatus': '',
      'verified': false,
      'earnings': 0,
      'driverName': '',
      'driverNumber': '',
    };
    try {
      await _firestore.collection('users').doc(uid).set(usermap);
      loggedUser = await returnUser();
      notifyListeners();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomePage()),
            (route) => false,
      );
    } on FirebaseException catch (e) {
      _snack(context, e.message ?? 'Could not complete profile');
    }
  }

  // ── updateProfile ─────────────────────────────────────────────────────────
  Future<void> updateProfile(
      String firstname,
      String lastname,
      String username,
      String dob,
      String email,
      BuildContext context,
      ) async {
    try {
      await _firestore.collection('users').doc(loggedUser.id).update({
        'firstName': firstname,
        'lastName': lastname,
        'username': username,
        'email': email,
        'dob': dob,
      });
      loggedUser = await returnUser();
      notifyListeners();
    } on FirebaseException catch (e) {
      debugPrint(e.message);
    }
  }

  // ── updateDriverProfile ───────────────────────────────────────────────────
  Future<void> updateDriverProfile(
      String driverName,
      String driverNumber,
      BuildContext context,
      ) async {
    try {
      await _firestore.collection('users').doc(loggedUser.id).update({
        'driverName': driverName,
        'driverNumber': driverNumber,
        'submittedStatus': 'waiting',
      });
      loggedUser = await returnUser();
      notifyListeners();
    } on FirebaseException catch (e) {
      _snack(context, e.message ?? 'Could not update driver profile');
    }
  }

  // ── returnUser ────────────────────────────────────────────────────────────
  Future<UserModel> returnUser() async {
    final currentUser = auth.currentUser;
    var user = UserModel();
    if (currentUser == null) return user;
    try {
      final doc =
      await _firestore.collection('users').doc(currentUser.uid).get();
      user = UserModel.fromSnapshot(doc);
    } on FirebaseException catch (e) {
      debugPrint('returnUser error: $e');
    }
    return user;
  }

  // ── setDriver / setPassenger (kept for admin use only) ────────────────────
  void setDriver(BuildContext context) async {
    await _firestore
        .collection('users')
        .doc(auth.currentUser!.uid)
        .update({'isDriver': true});
    loggedUser = await returnUser();
    notifyListeners();
  }

  void setPassenger(BuildContext context) async {
    await _firestore
        .collection('users')
        .doc(auth.currentUser!.uid)
        .update({'isDriver': false});
    loggedUser = await returnUser();
    notifyListeners();
  }

  // ── Driver online / offline ───────────────────────────────────────────────
  void goOnline(BuildContext context) async {
    await _firestore
        .collection('users')
        .doc(auth.currentUser!.uid)
        .update({'isOnline': true});
    loggedUser = await returnUser();
    await LocationService().startDriverLocationStream();
    notifyListeners();
  }

  void goOffline(BuildContext context) async {
    await _firestore
        .collection('users')
        .doc(auth.currentUser!.uid)
        .update({'isOnline': false});
    loggedUser = await returnUser();
    await LocationService().stopDriverLocationStream();
    notifyListeners();
  }

  // ── Helper ────────────────────────────────────────────────────────────────
  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }
}