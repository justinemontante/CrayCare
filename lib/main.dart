import 'dart:async';
import 'dart:io'; // 1. BINAGO: Dinagdag para sa HttpOverrides
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart'; // The core Firebase plugin
import 'package:firebase_auth/firebase_auth.dart'; // Added for checking auth state

import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart'; // Import the MainShell for routing
import 'services/settings_service.dart';
import 'firebase_options.dart'; // Generated configuration file

// 2. BINAGO: Dinagdag itong class na ito para ma-bypass ang SSL/Handshake errors sa devices
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  // 3. BINAGO: In-initialize ang HttpOverrides bago mag-start ang app
  HttpOverrides.global = MyHttpOverrides();

  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await SettingsService.instance.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const CrayCareApp());
}

class CrayCareApp extends StatelessWidget {
  const CrayCareApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrayCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _animateProgress();
  }

  void _animateProgress() async {
    const totalSteps = 100;
    const stepDuration = Duration(milliseconds: 30);

    // 1. Progress bar animation
    for (int i = 1; i <= totalSteps; i++) {
      await Future.delayed(stepDuration);
      if (!mounted) return;
      setState(() {
        _progress = i / totalSteps;
      });
    }

    if (!mounted) return;

    // 2. Check Firebase Auth State (Persistent Login)
    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      // Kung naka-login na, deretso sa Dashboard (MainShell)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } else {
      // Kung walang naka-login, punta sa LoginScreen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 150,
                    height: 150,
                  ),
                  const SizedBox(height: 20),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Cray',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0B3C49),
                        ),
                      ),
                      Text(
                        'Care',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1FA5A5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Better Care, Better Crayfish',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF0B3C49).withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 60,
              child: Column(
                children: [
                  const Text(
                    'Loading...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1FA5A5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: const Color(0xFFE0E0E0),
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF1FA5A5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
