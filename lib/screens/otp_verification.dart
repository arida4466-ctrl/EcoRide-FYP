// OTP verification removed — app now uses email/password authentication.
// This file is kept as a placeholder to avoid import errors.

import 'package:flutter/material.dart';

class Verification extends StatelessWidget {
  final String phoneNum;
  const Verification({Key? key, required this.phoneNum}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('OTP login has been removed.'),
      ),
    );
  }
}