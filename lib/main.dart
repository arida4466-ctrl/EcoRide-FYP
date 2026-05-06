import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:indriver_clone/providers/auth.dart';
import 'package:indriver_clone/providers/handle.dart';
import 'package:indriver_clone/screens/root.dart';
import 'package:indriver_clone/services/location_service.dart';
import 'package:indriver_clone/ui/constants.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyADWCR6joOmco_nDsVPKnXGpaKl_w0cGRw",
      appId: "1:86920325828:android:79830138f36773fccff791",
      messagingSenderId: "86920325828",
      projectId: "ecoride-d4a8b",
      storageBucket: "ecoride-d4a8b.firebasestorage.app",
      databaseURL:
      "https://ecoride-d4a8b-default-rtdb.asia-southeast1.firebasedatabase.app",
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppHandler()),
        ChangeNotifierProvider(create: (_) => Authentication()),
        ChangeNotifierProvider(create: (_) => LocationService()),
      ],
      child: MaterialApp(
        title: 'SafeDrive',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.green,
          colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
          useMaterial3: false,
        ),
        home: const Root(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  LOGIN SCREEN  — Passenger tab | Driver tab   (NO OTP)
// ════════════════════════════════════════════════════════════════════════════
class Login extends StatefulWidget {
  const Login({Key? key}) : super(key: key);

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              color: primaryColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SafeDrive 🚌',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  const Text('Sign in or create an account',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 16),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    tabs: const [
                      Tab(icon: Icon(Icons.person_outline), text: 'Passenger'),
                      Tab(
                          icon: Icon(Icons.directions_bus_outlined),
                          text: 'Driver'),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _AuthForm(isDriver: false),
                  _AuthForm(isDriver: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared form (login + register) used by both tabs ─────────────────────────
class _AuthForm extends StatefulWidget {
  final bool isDriver;
  const _AuthForm({required this.isDriver});

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscure = true;
  bool _isRegister = false;

  @override
  void dispose() {
    for (final c in [
      _emailCtrl, _passCtrl, _firstNameCtrl,
      _lastNameCtrl, _usernameCtrl, _phoneCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final auth = Provider.of<Authentication>(context, listen: false);

    if (_isRegister) {
      await auth.registerWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        isDriver: widget.isDriver,
        context: context,
      );
    } else {
      await auth.loginWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
        isDriver: widget.isDriver,
        context: context,
      );
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final accent =
    widget.isDriver ? Colors.green.shade700 : primaryColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            Text(
              _isRegister
                  ? (widget.isDriver
                  ? '🚌  Create Driver Account'
                  : '👤  Create Passenger Account')
                  : (widget.isDriver ? '🚌  Driver Login' : '👤  Passenger Login'),
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: accent),
            ),
            const SizedBox(height: 18),

            if (_isRegister) ...[
              _field(_firstNameCtrl, 'First Name', Icons.person_outline),
              const SizedBox(height: 10),
              _field(_lastNameCtrl, 'Last Name', Icons.person_outline),
              const SizedBox(height: 10),
              _field(_usernameCtrl, 'Username', Icons.alternate_email),
              const SizedBox(height: 10),
              _field(_phoneCtrl, 'Phone Number', Icons.phone,
                  type: TextInputType.phone),
              const SizedBox(height: 10),
            ],

            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: _dec('Email', Icons.email_outlined),
              validator: (v) =>
              v == null || !v.contains('@') ? 'Enter valid email' : null,
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: _dec('Password', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                      size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) =>
              v == null || v.length < 6 ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 22),

            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _submit,
              child: Text(
                _isRegister ? 'Register' : 'Login',
                style: const TextStyle(
                    fontSize: 16, color: Colors.white),
              ),
            ),
            const SizedBox(height: 10),

            TextButton(
              onPressed: () => setState(() => _isRegister = !_isRegister),
              child: Text(
                _isRegister
                    ? 'Already have an account? Login'
                    : "Don't have an account? Register",
                style: TextStyle(color: accent, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    contentPadding:
    const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
  );

  Widget _field(
      TextEditingController ctrl,
      String label,
      IconData icon, {
        TextInputType type = TextInputType.text,
      }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: type,
        decoration: _dec(label, icon),
        validator: (v) =>
        v == null || v.trim().isEmpty ? 'Required' : null,
      );
}