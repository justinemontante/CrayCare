import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_colors.dart';
import '../services/database_service.dart';
import 'dashboard_screen.dart';
import 'analytics_screen.dart';
import 'controls_screen.dart';
import 'tanks_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _analyticsKey = GlobalKey<AnalyticsScreenState>();
  final _tanksKey = GlobalKey<TanksScreenState>();
  String? _photoUrl;
  bool _isOwner = false;
  StreamSubscription<DatabaseEvent>? _roleSub;
  StreamSubscription<DatabaseEvent>? _primarySub;

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
    _loadPhoto();
    _checkPrimaryUser();
  }

  @override
  void dispose() {
    _roleSub?.cancel();
    _primarySub?.cancel();
    super.dispose();
  }

  void _checkPrimaryUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    debugPrint('[MainShell] Checking user role. Current UID: $uid');

    // Listen to user's role in their profile
    _roleSub = FirebaseDatabase.instance
        .ref('users/$uid/profile/role')
        .onValue
        .listen((event) {
      final roleVal = event.snapshot.value;
      debugPrint('[MainShell] User role value: $roleVal');
      final isOwnerByRole = (roleVal?.toString() == 'owner');

      if (mounted) setState(() => _isOwner = isOwnerByRole);
    });

    // Also check legacy authorizedOperators (backward compat)
    _primarySub = FirebaseDatabase.instance
        .ref('system/authorizedOperators')
        .onValue
        .listen((event) {
      final val = event.snapshot.value;
      debugPrint('[MainShell] authorizedOperators value: $val');
      bool isPrimary;
      if (val == null) {
        isPrimary = false;
      } else if (val is Map) {
        isPrimary = val.containsKey(uid) || val['UID'] == uid;
      } else {
        isPrimary = val.toString() == uid;
      }
      debugPrint('[MainShell] isPrimary (legacy) = $isPrimary');
      if (isPrimary && mounted) setState(() => _isOwner = true);
    });
  }

  Future<void> _loadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final data = await DatabaseService.instance.getUserProfile(user.uid);
    if (data != null && data['photoUrl'] != null && mounted) {
      setState(() => _setPhoto(data['photoUrl'] as String));
    }
  }

  void _goToAnalytics(String chartKey) {
    setState(() => _currentIndex = 1);
    _analyticsKey.currentState?.scrollToChart(chartKey);
  }



  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.bar_chart_rounded, label: 'Analytics'),
    _NavItem(icon: Icons.inventory_2_rounded, label: 'Tank'),
    _NavItem(icon: Icons.memory_rounded, label: 'Controls'),
    _NavItem(icon: Icons.notifications_rounded, label: 'Notifications'),
  ];

  @override
  Widget build(BuildContext context) {
    final photoImage = _photoImageProvider(_photoUrl);
    final isOwner = _isOwner;

    return Scaffold(
      key: _scaffoldKey,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF8FFFF), // #f8ffff
                  Color(0xFFF2FDFD), // #f2fdfd
                  Color(0xFFE8FAFA), // #e8fafa
                  Color(0xFFDAF4F5), // #daf4f5
                ],
              ),
              border: Border(
                bottom: BorderSide(color: Color(0x0f000000), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 42,
                      height: 42,
                    ),
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
                        builder: (_) =>
                            SettingsScreen(initialPhotoUrl: _photoUrl, isOwner: isOwner),
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
                      image: photoImage != null
                          ? DecorationImage(
                              image: photoImage,
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: photoImage == null
                        ? const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                DashboardScreen(
                  onViewGraph: _goToAnalytics,
                  onNavigate: (i) => setState(() => _currentIndex = i),
                  onTankTab: (tab) {
                    setState(() => _currentIndex = 2);
                    _tanksKey.currentState?.switchToTab(tab);
                  },
                ),
                AnalyticsScreen(key: _analyticsKey),
                TanksScreen(key: _tanksKey, isOwner: isOwner),
                ControlsScreen(isOwner: isOwner),
                const NotificationsScreen(),
              ],
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = _navItems;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.whiteWith(0.85),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0d000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final isActive = i == _currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentIndex = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primaryWith(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 22,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.darkWith(0.3),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.darkWith(0.4),
                        ),
                      ),
                    ),
                    if (isActive)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 20,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.all(Radius.circular(3)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}


class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
