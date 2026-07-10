import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/background_service.dart';
import 'services/ml_service.dart';
import 'firebase_options.dart';
import 'screens/verify_screen.dart';
import 'services/settings_service.dart';
import 'services/notification_service.dart';
import 'services/feeder_service.dart';
import 'services/crayfish_service.dart';
import 'services/lettuce_service.dart';
import 'services/database_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  HttpOverrides.global = MyHttpOverrides();

  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable offline persistence before any Firebase Database operation
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  FirebaseDatabase.instance.setPersistenceCacheSizeBytes(104857600); // 100MB

  // CRITICAL: Register the background message handler BEFORE any other setup.
  // Firebase requires this to be a top-level function registered here.
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);

  try {
    await initializeWorkmanager();
  } catch (e) {
    debugPrint('[Main] Workmanager init error: $e');
  }

  await SettingsService.instance.init();
  NotificationService.instance.init();
  await NotificationService.instance.initFCM();
  FeederService.instance.init();
  CrayfishService.instance.init();
  LettuceService.instance.init();
  MlService.instance.init();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
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
    const stepDuration = Duration(
      milliseconds: 30,
    ); // Total 3 seconds animation

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
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        // FIXED: Nilagyan ng 5-second timeout para hindi mag-hang forever
        try {
          await currentUser.reload().timeout(const Duration(seconds: 5));
        } catch (reloadError) {
          debugPrint("RELOAD TIMEOUT/ERROR: $reloadError");
          // Kahit nag-timeout ang reload, kung may current user, papasukin pa rin
          // (para pwede pa rin mag-load ang app kahit mahina net).
          // Magiging null lang ito kung talagang na-delete na ang account.
        }

        final freshUser = FirebaseAuth.instance.currentUser;

        if (freshUser != null && freshUser.emailVerified) {
          // Check if user is disabled in database before auto-login
          try {
            final profile = await DatabaseService.instance.getUserProfile(freshUser.uid);
            if (profile != null && profile['status'] == 'disabled') {
              await FirebaseDatabase.instance.ref('users/${freshUser.uid}/fcmToken').remove().catchError((_) {});
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
              return;
            }
          } catch (_) {
            // If DB check fails, allow login anyway (offline resilience)
          }

          // Verified & active: deretso sa Dashboard
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainShell()),
          );
        } else if (freshUser != null && !freshUser.emailVerified) {
          // May account pero hindi naka-verify: pumunta sa VerifyScreen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const VerifyScreen()),
          );
        } else {
          // User deleted or invalid: LoginScreen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      } else {
        // Walang naka-login
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      // DITO LALABAS ANG ERROR SA VS CODE KUNG BAKIT SIYA NAG-FAIL
      debugPrint("SPLASH SCREEN MAIN ERROR: $e");

      if (!mounted) return;
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
