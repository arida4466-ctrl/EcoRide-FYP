import 'package:flutter/material.dart';
import 'package:indriver_clone/admin/screens/admin_root.dart';
import 'package:indriver_clone/driver/screens/main_page.dart';
import 'package:indriver_clone/providers/auth.dart';
import 'package:indriver_clone/screens/help.dart';
import 'package:indriver_clone/screens/homepage.dart';
import 'package:indriver_clone/screens/profile_settings.dart';
import 'package:indriver_clone/screens/settings.dart';
import 'package:indriver_clone/screens/support.dart';
import 'package:indriver_clone/ui/button.dart';
import 'package:indriver_clone/ui/constants.dart';
import 'package:provider/provider.dart';

class NavDrawer extends StatefulWidget {
  const NavDrawer({Key? key}) : super(key: key);

  @override
  _NavDrawerState createState() => _NavDrawerState();
}

class _NavDrawerState extends State<NavDrawer> {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Drawer(
      child: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              height: size.height * 0.92,
              child: Column(
                children: [
                  // ── Profile header ─────────────────────────────────────
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const Profile()),
                    ),
                    child: Consumer<Authentication>(
                      builder: (_, Authentication provider, __) {
                        final isDriver =
                            provider.loggedUser.isDriver == true;
                        return DrawerHeader(
                          decoration: BoxDecoration(
                            color: isDriver
                                ? Colors.green.shade700
                                : primaryColor,
                          ),
                          margin: EdgeInsets.zero,
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.white,
                                radius: 36,
                                child: Icon(
                                  isDriver
                                      ? Icons.directions_bus
                                      : Icons.person,
                                  color: isDriver
                                      ? Colors.green.shade700
                                      : primaryColor,
                                  size: 36,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      provider.loggedUser.username ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isDriver
                                            ? '🚌 Driver'
                                            : '👤 Passenger',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Tap to edit profile',
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios,
                                  color: Colors.white70, size: 16),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Home ──────────────────────────────────────────────
                  Consumer<Authentication>(
                    builder: (_, Authentication auth, __) => ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: const Text('Home'),
                      onTap: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                auth.loggedUser.isDriver == true
                                    ? MainDriverPage()
                                    : const HomePage(),
                          ),
                          (route) => false,
                        );
                      },
                    ),
                  ),

                  const Divider(),

                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Settings'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const Setting()),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Help'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const Help()),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.support_agent),
                    title: const Text('Support'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const Support()),
                    ),
                  ),

                  const Divider(),

                  // ── Logout ─────────────────────────────────────────────
                  Consumer<Authentication>(
                    builder: (_, Authentication provider, __) => ListTile(
                      leading:
                          const Icon(Icons.logout, color: Colors.red),
                      title: const Text('Logout',
                          style: TextStyle(color: Colors.red)),
                      onTap: () => provider.logout(),
                    ),
                  ),

                  // NOTE: Switch to driver/passenger REMOVED
                  // Accounts are fixed at registration time.
                ],
              ),
            ),

            // ── Admin panel ────────────────────────────────────────────
            Consumer<Authentication>(
              builder: (_, Authentication auth, __) =>
                  auth.loggedUser.isAdmin == true
                      ? BotButton(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => AdminRoot()),
                          ),
                          title: 'Admin Panel',
                        )
                      : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}