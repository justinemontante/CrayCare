import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/background_service.dart';
import 'services/ml_service.dart';
import 'firebase_options.dart';
import 'screens/verify_screen.dart';
import 'services/settings_service.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/feeder_service.dart';
import 'services/tank_service.dart';
import 'services/database_service.dart';
import 'services/health_risk_service.dart';
import 'services/crayfish_detection_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  double _displayedProgress = 0.0;
  double _targetProgress = 0.0;
  late AnimationController _animController;

  static const _totalSteps = 10;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animController.addListener(() {
      if (mounted) {
        setState(() => _displayedProgress = _animController.value);
      }
    });
    _initServices();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _advanceProgress() {
    _currentStep++;
    _targetProgress = (_currentStep / _totalSteps).clamp(0.0, 1.0);
    _animController.animateTo(_targetProgress, duration: const Duration(milliseconds: 500));
  }

  Future<void> _withTimeout(Future<void> Function() fn, int timeoutMs) async {
    try {
      await fn().timeout(Duration(milliseconds: timeoutMs));
    } catch (e) {
      debugPrint('[Splash] Service timeout/error: $e');
    }
  }

  Future<void> _initServices() async {
    await _withTimeout(
      () => Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
      10000,
    );
    _advanceProgress();
    if (!mounted) return;

    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: true,
    );
    _advanceProgress();
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);

    await _withTimeout(() => initializeWorkmanager(), 3000);
    _advanceProgress();

    await _withTimeout(() => SettingsService.instance.init(), 3000);
    _advanceProgress();

    await _withTimeout(() => ConnectivityService.instance.init(), 5000);
    _advanceProgress();

    await _withTimeout(() async {
      NotificationService.instance.init();
      await NotificationService.instance.initFCM();
    }, 5000);
    _advanceProgress();

    if (!mounted) return;

    FeederService.instance.init();
    _advanceProgress();
    TankService.instance.init();
    _advanceProgress();
    MlService.instance.init();
    _advanceProgress();
    HealthRiskService.instance.init();
    _advanceProgress();
    CrayfishDetectionService.instance.init();
    _advanceProgress();

    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    bool isOnline = false;
    try {
      isOnline = await ConnectivityService.instance.checkConnectivity()
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    _targetProgress = 1.0;
    if (mounted) setState(() => _displayedProgress = 1.0);
    _animController.stop();

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        if (isOnline) {
          try {
            await currentUser.reload().timeout(const Duration(seconds: 5));
          } catch (reloadError) {
            debugPrint("RELOAD TIMEOUT/ERROR: $reloadError");
          }
        }

        final freshUser = FirebaseAuth.instance.currentUser;

        if (freshUser != null && freshUser.emailVerified) {
          if (isOnline) {
            try {
              final profile = await DatabaseService.instance.getUserProfile(freshUser.uid);
              if (profile != null && profile['status'] == 'disabled') {
                await FirebaseFirestore.instance.collection('users').doc(freshUser.uid).update({'fcmToken': FieldValue.delete()}).catchError((_) {});
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
                return;
              }
            } catch (_) {
            }
          }

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainShell()),
          );
        } else if (freshUser != null && !freshUser.emailVerified) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const VerifyScreen()),
          );
        } else {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      } else {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
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
                  Text(
                    '${(_displayedProgress * 100).toInt()}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
                        value: _displayedProgress,
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
