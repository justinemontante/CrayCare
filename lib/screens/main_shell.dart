import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_colors.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import 'dashboard_screen.dart';
import 'analytics_screen.dart';
import 'controls_screen.dart';
import 'tanks_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import '../widgets/settings/user_management_form.dart';

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
  String? _userRole;
  bool _isOwner = false;
  bool _loadingRole = true;
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
    
    // Register NotificationService listener to update badges dynamically
    NotificationService.instance.addListener(_onNotificationChange);

    // Safety fallback: if DB role checking takes too long, stop loading after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && _loadingRole) {
        setState(() => _loadingRole = false);
      }
    });
  }

  @override
  void dispose() {
    _roleSub?.cancel();
    _primarySub?.cancel();
    NotificationService.instance.removeListener(_onNotificationChange);
    super.dispose();
  }

  void _onNotificationChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _checkPrimaryUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    debugPrint('[MainShell] Checking user role. Current UID: $uid');

    // Listen to user's profile node (contains role and status)
    _roleSub = FirebaseDatabase.instance
        .ref('users/$uid/profile')
        .onValue
        .listen((event) {
      if (event.snapshot.value == null) {
        if (mounted) setState(() => _loadingRole = false);
        return;
      }
      final profile = DatabaseService.convertMap(event.snapshot.value as Map);
      
      final String? roleVal = profile['role'] as String?;
      final String? statusVal = profile['status'] as String?;
      debugPrint('[MainShell] User role: $roleVal, status: $statusVal');
      
      // Auto-kick if account is disabled in real-time
      if (statusVal == 'disabled') {
        _roleSub?.cancel();
        _primarySub?.cancel();
        FirebaseDatabase.instance.ref('users/$uid/fcmToken').remove().catchError((_) {});
        FirebaseAuth.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your account has been disabled by the administrator.'),
              backgroundColor: Colors.redAccent,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
        return;
      }

      final hasControl = (roleVal == 'owner' || roleVal == 'admin');

      if (mounted) {
        setState(() {
          _userRole = roleVal;
          _isOwner = hasControl;
          _loadingRole = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _loadingRole = false);
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
      if (isPrimary && mounted) {
        setState(() {
          _isOwner = true;
          _loadingRole = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _loadingRole = false);
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
    final bool isAdmin = _userRole == 'admin';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _loadingRole
          ? const Scaffold(
              key: ValueKey('loading_shell'),
              backgroundColor: Color(0xFFF8FFFF),
              body: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              ),
            )
          : Container(
              key: const ValueKey('main_shell_view'),
              child: Scaffold(
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
                                      SettingsScreen(initialPhotoUrl: _photoUrl, userRole: _userRole),
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
                      child: isAdmin
                          ? const UserManagementForm()
                          : IndexedStack(
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
                    if (!isAdmin) _buildBottomNav(),
                  ],
                ),
              ),
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
              onTap: () {
                setState(() => _currentIndex = i);
                if (i == 4) {
                  NotificationService.instance.markAllRead();
                }
              },
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
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          item.icon,
                          size: 22,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.darkWith(0.3),
                        ),
                        if (i == 4 && i != _currentIndex)
                          Positioned(
                            right: -6,
                            top: -4,
                            child: _buildBadge(
                              NotificationService.instance.unreadCount,
                            ),
                          ),
                      ],
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
