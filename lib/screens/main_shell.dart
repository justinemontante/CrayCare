import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/notification_service.dart';
import '../services/connectivity_service.dart';
import 'dashboard_screen.dart';
import 'analytics_screen.dart';
import 'controls_screen.dart';
import 'production_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'admin_screen.dart';


class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _analyticsKey = GlobalKey<AnalyticsScreenState>();
  final _productionKey = GlobalKey<ProductionScreenState>();
  final _controlsKey = GlobalKey<ControlsScreenState>();
  String? _photoUrl;
  bool _isAdmin = false;
  bool _roleLoaded = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  static const List<_NavItem> _ownerNavItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.bar_chart_rounded, label: 'Analytics'),
    _NavItem(icon: Icons.oil_barrel_rounded, label: 'Tank'),
    _NavItem(icon: Icons.memory_rounded, label: 'Controls'),
    _NavItem(icon: Icons.notifications_rounded, label: 'Notifications'),
  ];

  void _setPhoto(String url) {
    _photoUrl = url;
  }

  ImageProvider<Object>? _photoImageProvider(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return null;
    final uri = Uri.tryParse(photoUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(photoUrl);
    }
    try {
      return MemoryImage(base64Decode(photoUrl.split(',').last));
    } on FormatException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _listenToProfile();
    NotificationService.instance.addListener(_onNotificationChange);
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    NotificationService.instance.removeListener(_onNotificationChange);
    super.dispose();
  }

  void _onNotificationChange() {
    if (mounted) setState(() {});
  }

  void _listenToProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _profileSub?.cancel();
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;
      setState(() {
        final photo = data['photo_url'] ?? data['photoUrl'];
        if (photo is String) _setPhoto(photo);
        _isAdmin = data['role'] == 'admin';
        _roleLoaded = true;
        if (_isAdmin && _currentIndex > 0) _currentIndex = 0;
      });
    }, onError: (e) {
      debugPrint('[MainShell] Profile stream error: $e');
      if (mounted && !_roleLoaded) {
        setState(() => _roleLoaded = true);
      }
    });
  }

  void _goToAnalytics(String chartKey) {
    setState(() => _currentIndex = 1);
    _analyticsKey.currentState?.scrollToChart(chartKey);
  }

  @override
  Widget build(BuildContext context) {
    final photoImage = _photoImageProvider(_photoUrl);

    if (!_roleLoaded) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(photoImage),
              _buildOfflineBanner(),
              Expanded(
                  child: _isAdmin
                      ? const AdminScreen()
                      : IndexedStack(
                          index: _currentIndex,
                          children: [
                            DashboardScreen(
                              onViewGraph: _goToAnalytics,
                              onNavigate: (i) => setState(() => _currentIndex = i),
                              onTankTab: (tab) {
                                setState(() => _currentIndex = 2);
                                _productionKey.currentState?.switchToTab(tab);
                              },
                              onControlTab: (tab) {
                                setState(() => _currentIndex = 3);
                                _controlsKey.currentState?.switchToTab(tab);
                              },
                            ),
                            AnalyticsScreen(key: _analyticsKey),
                            ProductionScreen(key: _productionKey),
                            ControlsScreen(key: _controlsKey),
                            const NotificationsScreen(),
                          ],
                        ),
              ),
              if (!_isAdmin) _buildBottomNav(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ImageProvider<Object>? photoImage) {
    return SizedBox(
      height: 82,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF5FFFF),
                  Color(0xFFE9FBFB),
                  Color(0xFFD8F5F6),
                  Color(0xFFC9F0F1),
                ],
                stops: [0.0, 0.36, 0.70, 1.0],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _HeaderWavePainter(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/logo.png', width: 42, height: 42),
                    const SizedBox(width: 6),
                    const Text(
                      'Cray',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Text(
                      'Care',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(initialPhotoUrl: _photoUrl),
                      ),
                    );
                    if (result != null && mounted) {
                      setState(() => _setPhoto(result));
                    }
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: photoImage == null ? AppColors.primary : null,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.72),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.13),
                          blurRadius: 9,
                          offset: const Offset(0, 3),
                        ),
                      ],
                      image: photoImage != null
                          ? DecorationImage(image: photoImage, fit: BoxFit.cover)
                          : null,
                    ),
                    child: photoImage == null
                        ? const Icon(Icons.person, color: Colors.white, size: 20)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return ListenableBuilder(
      listenable: ConnectivityService.instance,
      builder: (context, _) {
        if (ConnectivityService.instance.isOnline) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          color: const Color(0xFFFFF3CD),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.wifi_off_rounded, size: 14, color: Color(0xFF856404)),
              SizedBox(width: 6),
              Text(
                'No internet connection — showing cached data',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF856404),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.whiteWith(0.9),
        boxShadow: const [
          BoxShadow(color: Color(0x0d000000), blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Row(
        children: List.generate(_ownerNavItems.length, (i) {
          final item = _ownerNavItems[i];
          final isActive = i == _currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _currentIndex = i);
                if (i == 4) NotificationService.instance.markAllRead();
                if (i == 2) {
                  _productionKey.currentState?.switchToTab(0);
                }
              },
              child: _buildNavItem(item, isActive, i),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavItem(_NavItem item, bool isActive, int index) {
    final unread = index == 4 ? NotificationService.instance.unreadCount : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primaryWith(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(item.icon, size: 22,
                color: isActive ? AppColors.primary : AppColors.darkWith(0.3),
              ),
              if (unread > 0)
                Positioned(
                  top: -2, right: -4,
                  child: Container(
                    padding: EdgeInsets.all(unread > 9 ? 2 : 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Center(
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(item.label,
              style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w600,
                color: isActive ? AppColors.primary : AppColors.darkWith(0.4),
              ),
            ),
          ),
          if (isActive)
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 20, height: 3,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.all(Radius.circular(3)),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderWavePainter extends CustomPainter {
  const _HeaderWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backWave = Path()
      ..moveTo(0, size.height * 0.58)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.48,
        size.width * 0.30,
        size.height * 0.78,
        size.width * 0.50,
        size.height * 0.66,
      )
      ..cubicTo(
        size.width * 0.70,
        size.height * 0.54,
        size.width * 0.82,
        size.height * 0.46,
        size.width,
        size.height * 0.58,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      backWave,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.28),
    );

    final midWave = Path()
      ..moveTo(0, size.height * 0.72)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.60,
        size.width * 0.34,
        size.height * 0.90,
        size.width * 0.56,
        size.height * 0.73,
      )
      ..cubicTo(
        size.width * 0.74,
        size.height * 0.60,
        size.width * 0.88,
        size.height * 0.72,
        size.width,
        size.height * 0.66,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      midWave,
      Paint()..color = const Color(0xFFEAFBFB).withValues(alpha: 0.78),
    );

    final whiteWave = Path()
      ..moveTo(0, size.height * 0.82)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.74,
        size.width * 0.35,
        size.height * 1.02,
        size.width * 0.56,
        size.height * 0.84,
      )
      ..cubicTo(
        size.width * 0.75,
        size.height * 0.68,
        size.width * 0.88,
        size.height * 0.90,
        size.width,
        size.height * 0.78,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(whiteWave, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
