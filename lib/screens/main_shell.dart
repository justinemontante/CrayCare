import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import 'dashboard_screen.dart';
import 'analytics_screen.dart';
import 'controls_screen.dart';
import 'production_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _analyticsKey = GlobalKey<AnalyticsScreenState>();
  final _productionKey = GlobalKey<ProductionScreenState>();
  final _controlsKey = GlobalKey<ControlsScreenState>();
  String? _photoUrl;
  bool _showProdPicker = false;

  late final AnimationController _pickerCtrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 350),
  );
  late final Animation<double> _pickerScale = CurvedAnimation(
    parent: _pickerCtrl, curve: Curves.easeOutCubic,
  );
  late final Animation<double> _pickerFade = Tween(begin: 0.0, end: 1.0).animate(
    CurvedAnimation(parent: _pickerCtrl, curve: const Interval(0.0, 0.4)),
  );

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.bar_chart_rounded, label: 'Analytics'),
    _NavItem(icon: Icons.energy_savings_leaf_rounded, label: 'Production'),
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
    _loadPhoto();
    NotificationService.instance.addListener(_onNotificationChange);
  }

  @override
  void dispose() {
    _pickerCtrl.dispose();
    NotificationService.instance.removeListener(_onNotificationChange);
    super.dispose();
  }

  void _onNotificationChange() {
    if (mounted) setState(() {});
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

  void _showPicker() {
    setState(() => _showProdPicker = true);
    _pickerCtrl.forward(from: 0);
  }

  void _hidePicker() {
    _pickerCtrl.reverse().then((_) {
      if (mounted) setState(() => _showProdPicker = false);
    });
  }

  void _selectProdMode(String mode) {
    final needsTabSwitch = _currentIndex != 2;
    if (needsTabSwitch) setState(() => _currentIndex = 2);
    _productionKey.currentState?.setProductionMode(mode);
    _hidePicker();
  }

  @override
  Widget build(BuildContext context) {
    final photoImage = _photoImageProvider(_photoUrl);
    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(photoImage),
              Expanded(
                child: IndexedStack(
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
                    ProductionScreen(key: _productionKey, isOwner: true),
                    ControlsScreen(key: _controlsKey, isOwner: true),
                    const NotificationsScreen(),
                  ],
                ),
              ),
              _buildBottomNav(),
            ],
          ),
          if (_showProdPicker || _pickerCtrl.isAnimating)
            _buildProdPickerOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeader(ImageProvider<Object>? photoImage) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF8FFFF), Color(0xFFF2FDFD), Color(0xFFE8FAFA), Color(0xFFDAF4F5)],
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
              const Text('Cray', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.dark, letterSpacing: -0.3)),
              const Text('Care', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: -0.3)),
            ],
          ),
          GestureDetector(
            onTap: () async {
              final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => SettingsScreen(initialPhotoUrl: _photoUrl)));
              if (result != null && mounted) setState(() => _setPhoto(result));
            },
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: photoImage == null ? AppColors.primary : null,
                shape: BoxShape.circle,
                image: photoImage != null ? DecorationImage(image: photoImage, fit: BoxFit.cover) : null,
              ),
              child: photoImage == null ? const Icon(Icons.person, color: Colors.white, size: 20) : null,
            ),
          ),
        ],
      ),
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
        children: List.generate(_navItems.length, (i) {
          final item = _navItems[i];
          final isActive = i == _currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (i == 2) {
                  _showPicker();
                } else {
                  setState(() => _currentIndex = i);
                  if (i == 4) NotificationService.instance.markAllRead();
                }
              },
              child: _buildNavItem(item, isActive),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavItem(_NavItem item, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primaryWith(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 22,
            color: isActive ? AppColors.primary : AppColors.darkWith(0.3),
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

  Widget _buildProdPickerOverlay() {
    return GestureDetector(
      onTap: _hidePicker,
      child: Container(
        color: Colors.transparent,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedBuilder(
                animation: _pickerCtrl,
                builder: (context, _) {
                  return Transform.scale(
                    scale: _pickerScale.value,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 74),
                      width: 200, height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(200)),
                        boxShadow: [
                          BoxShadow(color: AppColors.darkWith(0.08), blurRadius: 20, offset: const Offset(0, -2)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 16),
                          Text('Select type',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.darkWith(0.5)),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildPickerCircle(Icons.water_drop_rounded, 'Crayfish', AppColors.primary, () => _selectProdMode('crayfish')),
                              const SizedBox(width: 20),
                              _buildPickerCircle(Icons.eco_rounded, 'Lettuce', AppColors.success, () => _selectProdMode('lettuce')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerCircle(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.25), width: 2),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.dark)),
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
