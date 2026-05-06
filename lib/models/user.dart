import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  String? id;
  String? firstName;
  String? phoneNumber;
  String? username;
  bool? isOnline;
  bool? isDriver;
  bool? isAdmin;
  bool? driverAccount;
  bool? verified;

  String? lastName;
  String? email;
  String? token;
  String? photo;
  String? dob;

  String? licenceNo;
  String? carplatenum;
  String? idNo;
  String? submittedStatus;
  String? driverName;
  String? driverNumber;

  int? votes;
  int? trips;
  double? earnings;
  double? rating;

  UserModel({
    this.id,
    this.firstName,
    this.username,
    this.email,
    this.isAdmin,
    this.idNo,
    this.dob,
    this.isDriver,
    this.isOnline,
    this.lastName,
    this.licenceNo,
    this.carplatenum,
    this.phoneNumber,
    this.photo,
    this.rating,
    this.token,
    this.trips,
    this.votes,
    this.driverAccount,
    this.submittedStatus,
    this.verified,
    this.earnings,
    this.driverName,
    this.driverNumber,
  });

  factory UserModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel(
      id: data['id'] as String?,
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      email: data['email'] as String?,
      username: data['username'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      trips: ((data['trips'] ?? 0) as num).toInt(),
      photo: data['photo'] as String?,
      idNo: data['idNo'] as String?,
      isDriver: data['isDriver'] as bool?,
      isOnline: data['isOnline'] as bool?,
      carplatenum: data['carplatenum'] as String?,
      rating: ((data['rating'] ?? 0.0) as num).toDouble(),
      token: data['token'] as String?,
      votes: ((data['votes'] ?? 0) as num).toInt(),
      dob: data['dob'] as String?,
      licenceNo: data['licenceNo'] as String?,
      isAdmin: data['isAdmin'] as bool?,
      driverAccount: data['driverAccount'] as bool?,
      verified: data['verified'] as bool?,
      submittedStatus: data['submittedStatus'] as String?,
      earnings: ((data['earnings'] ?? 0.0) as num).toDouble(),
      driverName: data['driverName'] as String?,
      driverNumber: data['driverNumber'] as String?,
    );
  }
}