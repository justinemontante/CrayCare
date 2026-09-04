import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../services/notification_service.dart';
import '../services/connectivity_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'analytics_screen.dart';
import 'controls_screen.dart';
import 'production_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'admin_screen.dart';
import '../widgets/common/dashboard_skeleton.dart';

class MainShell extends StatefulWidget {
  final Map<String, dynamic>? initialProfile;

  const MainShell({super.key, this.initialProfile});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _dashboardKey = GlobalKey<DashboardScreenState>();
  final _analyticsKey = GlobalKey<AnalyticsScreenState>();
  final _productionKey = GlobalKey<ProductionScreenState>();
  final _controlsKey = GlobalKey<ControlsScreenState>();
  late final List<Widget> _ownerScreens;
  String? _photoUrl;
  ImageProvider<Object>? _photoImage;
  bool _isAdmin = false;
  bool _roleLoaded = false;
  bool _handlingDisabledAccount = false;
  bool _notificationPromptCheckStarted = false;
  bool _connectivityWasOnline = true;
  bool _showConnectedMessage = false;
  Timer? _connectedMessageTimer;
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
    _photoImage = _photoImageProvider(url);
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
    _ownerScreens = [
      DashboardScreen(
        key: _dashboardKey,
        onViewGraph: _goToAnalytics,
        onNavigate: _selectOwnerTab,
        onTankTab: (tab) {
          _selectOwnerTab(2);
          _productionKey.currentState?.switchToTab(tab);
        },
        onControlTab: (tab) {
          _selectOwnerTab(3);
          _controlsKey.currentState?.switchToTab(tab);
        },
      ),
      AnalyticsScreen(key: _analyticsKey),
      ProductionScreen(key: _productionKey),
      ControlsScreen(key: _controlsKey),
      const NotificationsScreen(),
    ];
    final initialProfile = widget.initialProfile;
    if (initialProfile != null) {
      _applyProfile(initialProfile);
      _roleLoaded = true;
    }
    _listenToProfile();
    NotificationService.instance.addListener(_onNotificationChange);
    _connectivityWasOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.addListener(_onConnectivityChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncActiveScreenWork();
      unawaited(_maybeShowNotificationPermissionPrompt());
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _connectedMessageTimer?.cancel();
    NotificationService.instance.removeListener(_onNotificationChange);
    ConnectivityService.instance.removeListener(_onConnectivityChange);
    super.dispose();
  }

  void _onNotificationChange() {
    if (mounted) setState(() {});
  }

  void _onConnectivityChange() {
    final isOnline = ConnectivityService.instance.isOnline;
    if (isOnline == _connectivityWasOnline) return;
    final wasOffline = !_connectivityWasOnline;
    _connectivityWasOnline = isOnline;
    _connectedMessageTimer?.cancel();

    if (!mounted) return;
    setState(() => _showConnectedMessage = wasOffline && isOnline);
    if (_showConnectedMessage) {
      _connectedMessageTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _showConnectedMessage = false);
      });
    }
  }

  void _applyProfile(Map<String, dynamic> data) {
    final photo = data['photo_url'] ?? data['photoUrl'];
    if (photo is String) _setPhoto(photo);
    _isAdmin = data['role'] == 'admin';
    if (_isAdmin && _currentIndex > 0) _currentIndex = 0;
  }

  void _listenToProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _profileSub?.cancel();
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (doc) {
            if (!mounted) return;
            if (!doc.exists) {
              if (!_roleLoaded) setState(() => _roleLoaded = true);
              return;
            }
            final data = doc.data()!;
            if (data['status'] == 'disabled') {
              unawaited(_handleDisabledAccount());
              return;
            }
            setState(() {
              _applyProfile(data);
              _roleLoaded = true;
            });
            unawaited(_maybeShowNotificationPermissionPrompt());
          },
          onError: (e) {
            debugPrint('[MainShell] Profile stream error: $e');
            if (mounted && !_roleLoaded) {
              setState(() => _roleLoaded = true);
            }
          },
        );
  }

  Future<void> _maybeShowNotificationPermissionPrompt() async {
    if (_notificationPromptCheckStarted || !_roleLoaded || _isAdmin) return;
    _notificationPromptCheckStarted = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final status = await NotificationService.instance
          .notificationAuthorizationStatus();
      if (status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final promptKey = 'notification_permission_prompt_seen_${user.uid}';
      if (prefs.getBool(promptKey) == true || !mounted) return;

      final shouldEnable = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _NotificationPermissionDialog(),
      );
      await prefs.setBool(promptKey, true);

      if (shouldEnable == true) {
        await NotificationService.instance.requestNotificationPermission();
      }
    } catch (e, stack) {
      debugPrint('[MainShell] Notification permission prompt error: $e\n$stack');
    }
  }

  Future<void> _handleDisabledAccount() async {
    if (_handlingDisabledAccount) return;
    _handlingDisabledAccount = true;
    await _profileSub?.cancel();
    _profileSub = null;
    try {
      await AuthService().signOut();
    } catch (e) {
      debugPrint('[MainShell] Disabled-account sign-out cleanup failed: $e');
      await FirebaseAuth.instance.signOut();
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _goToAnalytics(String chartKey) {
    _selectOwnerTab(1);
    _analyticsKey.currentState?.scrollToChart(chartKey);
  }

  void _selectOwnerTab(int index) {
    if (index == _currentIndex || index < 0 || index >= _ownerScreens.length) {
      return;
    }
    setState(() => _currentIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncActiveScreenWork();
    });
  }

  void _syncActiveScreenWork() {
    if (!mounted || _isAdmin) return;
    _dashboardKey.currentState?.setTabActive(_currentIndex == 0);
    _analyticsKey.currentState?.setTabActive(_currentIndex == 1);
    _controlsKey.currentState?.setTabActive(_currentIndex == 3);
  }

  @override
  Widget build(BuildContext context) {
    final photoImage = _photoImage;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: !_roleLoaded
          ? _buildLoadingShell()
          : Scaffold(
              key: _scaffoldKey,
              body: Stack(
                children: [
                  Column(
                    children: [
                      _buildHeader(photoImage),
                      _buildConnectivityBanner(),
                      Expanded(
                        child: _isAdmin
                            ? const AdminScreen()
                            : IndexedStack(
                                index: _currentIndex,
                                children: _ownerScreens,
                              ),
                      ),
                      if (!_isAdmin) _buildBottomNav(),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingShell() {
    return Scaffold(
      key: const ValueKey('dashboard-loading'),
      backgroundColor: const Color(0xFFF8FBFB),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF8FFFF),
                  Color(0xFFF2FDFD),
                  Color(0xFFE8FAFA),
                  Color(0xFFDAF4F5),
                ],
              ),
              border: Border(
                bottom: BorderSide(color: Color(0x0F000000), width: 1),
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
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE3F1F1),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: DashboardSkeleton()),
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 20,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                _ownerNavItems.length,
                (_) => Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F1F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ImageProvider<Object>? photoImage) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF8FFFF),
            Color(0xFFF2FDFD),
            Color(0xFFE8FAFA),
            Color(0xFFDAF4F5),
          ],
        ),
        border: Border(bottom: BorderSide(color: Color(0x0f000000), width: 1)),
      ),
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
                  builder: (_) => SettingsScreen(
                    initialPhotoUrl: _photoUrl,
                    initialPhotoImage: _photoImage,
                  ),
                ),
              );
              if (result != null && mounted) setState(() => _setPhoto(result));
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: photoImage == null ? AppColors.primary : null,
                shape: BoxShape.circle,
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
    );
  }

  Widget _buildConnectivityBanner() {
    final Widget message;
    if (!ConnectivityService.instance.isOnline) {
      message = const Padding(
        key: ValueKey('offline'),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          'No internet connection — showing cached data',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF856404),
          ),
        ),
      );
    } else if (_showConnectedMessage) {
      message = const Padding(
        key: ValueKey('connected'),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 15,
              color: AppColors.success,
            ),
            SizedBox(width: 6),
            Text(
              'Connected to internet',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    } else {
      message = const SizedBox(key: ValueKey('online'));
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, -0.35),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: message,
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.whiteWith(0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0d000000),
            blurRadius: 16,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: List.generate(_ownerNavItems.length, (i) {
          final item = _ownerNavItems[i];
          final isActive = i == _currentIndex;
          return Expanded(
            child: Semantics(
              selected: isActive,
              button: true,
              label: item.label,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    if (i == _currentIndex) return;
                    _selectOwnerTab(i);
                    if (i == 2) {
                      _productionKey.currentState?.switchToTab(0);
                    }
                  },
                  child: _buildNavItem(item, isActive, i),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavItem(_NavItem item, bool isActive, int index) {
    final unread = index == 4 ? NotificationService.instance.unreadCount : 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primaryWith(0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppColors.primaryWith(0.08) : Colors.transparent,
        ),
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
                color: isActive ? AppColors.primary : AppColors.darkWith(0.3),
              ),
              if (unread > 0)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    padding: EdgeInsets.all(unread > 9 ? 2 : 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
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
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive ? AppColors.primary : AppColors.darkWith(0.4),
              ),
              child: Text(item.label),
            ),
          ),
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: isActive ? 18 : 0,
            height: 3,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _NotificationPermissionDialog extends StatelessWidget {
  const _NotificationPermissionDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.primaryWith(0.10)),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkWith(0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.primaryWith(0.09),
                shape: BoxShape.circle,
              ),
              child: Image.asset('assets/images/logo.png'),
            ),
            const SizedBox(height: 18),
            const Text(
              'Stay updated with CrayCare',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'Get real-time updates about your tank, feeding activities, and important CrayCare reminders.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: AppColors.subtitleText,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.notifications_active_rounded, size: 19),
                label: const Text(
                  'Enable Notifications',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 7),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.subtitleText,
                minimumSize: const Size(double.infinity, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Maybe Later',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
