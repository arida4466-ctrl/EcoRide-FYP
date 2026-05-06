import 'package:flutter/material.dart';
import 'package:indriver_clone/driver/screens/main_page.dart';
import 'package:indriver_clone/main.dart';
import 'package:indriver_clone/models/user.dart';
import 'package:indriver_clone/providers/auth.dart';
import 'package:indriver_clone/screens/homepage.dart';
import 'package:provider/provider.dart';

class Root extends StatelessWidget {
  const Root({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<Authentication>(context, listen: false);

    return StreamBuilder<UserModel?>(
      stream: auth.onAuthStateChanged(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user == null) return const Login();

          return FutureBuilder<UserModel>(
            future: auth.returnUser(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final fullUser = userSnapshot.data;
              if (fullUser == null) return const Login();

              auth.loggedUser = fullUser;

              // No const here — HomePage is not a const constructor
              return fullUser.isDriver == true
                  ? MainDriverPage()
                  : HomePage();
            },
          );
        }

        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}