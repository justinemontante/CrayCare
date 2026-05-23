import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart'; // Para ma-logout din ng tuluyan ang Google account
import '../theme/app_colors.dart';
import '../screens/login_screen.dart';
import '../models/crayfish_stage.dart';
import '../services/settings_service.dart';

class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  int _currentPage = 0;

  // Default values habang naglo-load
  String _profileName = 'Loading...';
  String _profileEmail = 'Loading...';

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  bool _notifAllow = true;
  bool _notifSound = true;
  bool _notifVibration = true;
  bool _notifCritical = true;
  bool _notifFeeding = true;
  bool _notifSampling = false;

  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onSettingsChange);
    _loadUserData(); // Kunin ang user data pagkakasimula ng drawer
  }

  // FUNCTION PARA KUNIN ANG DATA SA FIREBASE
  void _loadUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _profileName = user.displayName ?? 'CrayCare User';
        _profileEmail = user.email ?? 'No email linked';
      });
    }
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChange);
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  void _onSettingsChange() => setState(() {});

  void _goTo(int page) {
    _nameCtrl.text = _profileName;
    _emailCtrl.text = _profileEmail;
    setState(() => _currentPage = page);
  }

  void _back() {
    if (_currentPage == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _currentPage = 0);
    }
  }

  void _saveProfile() async {
    // I-update ang pangalan sa Firebase kung binago ng user
    final user = FirebaseAuth.instance.currentUser;
    if (user != null &&
        _nameCtrl.text.isNotEmpty &&
        _nameCtrl.text != _profileName) {
      await user.updateDisplayName(_nameCtrl.text);
    }

    setState(() {
      _profileName = _nameCtrl.text.isNotEmpty ? _nameCtrl.text : _profileName;
      _profileEmail = _emailCtrl.text.isNotEmpty
          ? _emailCtrl.text
          : _profileEmail;
    });

    _back();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
    }
  }

  void _changePassword() {
    if (_newPwCtrl.text.isNotEmpty && _newPwCtrl.text == _confirmPwCtrl.text) {
      _back();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showLogoutSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Are you sure you want to logout?',
                  style: TextStyle(fontSize: 12, color: AppColors.dark),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    // UPDATED LOGOUT FUNCTIONALITY
                    onPressed: () async {
                      try {
                        // 1. Sign out sa Google at Firebase
                        await GoogleSignIn().signOut();
                        await FirebaseAuth.instance.signOut();

                        if (!ctx.mounted) return;

                        // 2. I-close ang bottom sheet
                        Navigator.of(ctx).pop();

                        // 3. I-close ang drawer
                        Navigator.of(context).pop();

                        // 4. Bumalik sa Login Screen at burahin ang history para di ma-back
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error logging out: $e')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.critical,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Yes, Logout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width,
      child: Column(
        children: [
          Container(
            height: MediaQuery.of(context).padding.top,
            color: Colors.white,
          ),
          _buildHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeIn,
              switchOutCurve: Curves.easeOut,
              layoutBuilder: (child, List<Widget> previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, if (child != null) child],
                );
              },
              child: [
                _buildMainMenu(),
                _buildEditProfile(),
                _buildChangePassword(),
                _buildNotifSettings(),
                _buildStageSettings(),
              ][_currentPage],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.darkWith(0.07))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            color: AppColors.dark,
            onPressed: _back,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: 4),
          Text(
            _currentPage == 0 ? 'Profile & Settings' : _pageTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
        ],
      ),
    );
  }

  String get _pageTitle {
    switch (_currentPage) {
      case 1:
        return 'Edit Profile';
      case 2:
        return 'Change Password';
      case 3:
        return 'Notifications';
      case 4:
        return 'Crayfish Stage';
      default:
        return '';
    }
  }

  Widget _buildMainMenu() {
    return Container(
      color: const Color(0xFFf7f7f7),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildProfileCard(),
            const SizedBox(height: 10),
            _buildMenuSection('Account', [
              _buildMenuItem(
                'Edit Profile',
                Icons.person,
                AppColors.primary,
                chevron: true,
                onTap: () => _goTo(1),
              ),
              _buildMenuItem(
                'Change Password',
                Icons.lock,
                AppColors.primary,
                chevron: true,
                onTap: () => _goTo(2),
              ),
            ]),
            const SizedBox(height: 10),
            _buildMenuSection('Preferences', [
              _buildMenuItem(
                'Notifications',
                Icons.notifications,
                AppColors.warning,
                chevron: true,
                onTap: () => _goTo(3),
              ),
              _buildMenuItem(
                'Crayfish Stage',
                Icons.pets,
                AppColors.primary,
                chevron: true,
                onTap: () => _goTo(4),
              ),
            ]),
            const SizedBox(height: 10),
            _buildMenuItem(
              'Logout',
              Icons.logout,
              AppColors.critical,
              onTap: _showLogoutSheet,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: AppColors.darkWith(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _profileEmail,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.darkWith(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection(String label, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.darkWith(0.4),
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...items,
      ],
    );
  }

  Widget _buildMenuItem(
    String label,
    IconData icon,
    Color color, {
    bool chevron = false,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.04)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: label == 'Logout'
                          ? AppColors.critical
                          : AppColors.dark,
                    ),
                  ),
                ),
                if (chevron)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.darkWith(0.2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStageSettings() {
    final svc = SettingsService.instance;
    final sensors = ['temp', 'ph', 'do', 'turb', 'waterlevel'];
    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Selecting a stage automatically updates the ideal sensor thresholds for your crayfish\'s development.',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.dark.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.dark.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.dark.withValues(alpha: 0.03),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Growth Stage',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.dark.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: svc.currentStage,
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      items: CrayfishStage.all
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.name,
                              child: Text(s.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) svc.setCurrentStage(v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 12,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      svc.currentStageObj.description,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'THRESHOLD PARAMETERS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: AppColors.dark.withValues(alpha: 0.4),
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: sensors.length,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final key = sensors[index];
                final range =
                    svc.currentRanges[key] ?? {'min': 0.0, 'max': 0.0};
                final info = sensorInfo[key]!;
                return Container(
                  height: 60,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.dark.withValues(alpha: 0.04),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _showRangeEditor(
                        key,
                        info.label,
                        info.unit,
                        range['min']!,
                        range['max']!,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.dark.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Image.asset(
                                _getSensorIconPath(key),
                                width: 20,
                                height: 20,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    info.label,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.dark,
                                    ),
                                  ),
                                  Text(
                                    'Standard Range',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: AppColors.dark.withValues(
                                        alpha: 0.4,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${range['min']!.toStringAsFixed(1)} \u2013 ${range['max']! >= 999 ? '\u221E' : range['max']!.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  info.unit,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.dark.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                SettingsService.instance.resetToDefaults();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ranges reset to defaults'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(
                Icons.refresh_rounded,
                size: 14,
                color: AppColors.dark,
              ),
              label: Text(
                'RESET TO DEFAULTS',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  color: AppColors.dark.withValues(alpha: 0.5),
                  letterSpacing: 0.5,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.dark.withValues(alpha: 0.03),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getSensorIconPath(String key) {
    switch (key) {
      case 'temp':
        return 'assets/images/temperature.png';
      case 'ph':
        return 'assets/images/pH.png';
      case 'do':
        return 'assets/images/DO.png';
      case 'turb':
        return 'assets/images/Turbidity.png';
      case 'waterlevel':
        return 'assets/images/waterLevel.png';
      default:
        return 'assets/images/logo.png';
    }
  }

  Color _getSensorColor(String key) {
    switch (key) {
      case 'temp':
        return const Color(0xFFF59E0B);
      case 'ph':
        return const Color(0xFF8B5CF6);
      case 'do':
        return const Color(0xFF3B82F6);
      case 'turb':
        return const Color(0xFF64748B);
      case 'waterlevel':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  void _showRangeEditor(
    String key,
    String label,
    String unit,
    double currentMin,
    double currentMax,
  ) {
    final minCtrl = TextEditingController(text: currentMin.toStringAsFixed(1));
    final maxCtrl = TextEditingController(
      text: currentMax >= 999 ? '' : currentMax.toStringAsFixed(1),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getSensorColor(key).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset(
                _getSensorIconPath(key),
                width: 20,
                height: 20,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adjust the ideal range for this stage.',
              style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.5)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildModalField('Minimum', minCtrl, unit)),
                const SizedBox(width: 12),
                Expanded(child: _buildModalField('Maximum', maxCtrl, unit)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.darkWith(0.4),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final min = double.tryParse(minCtrl.text) ?? currentMin;
              final max =
                  double.tryParse(maxCtrl.text) ??
                  (currentMax >= 999 ? 999.0 : currentMax);
              SettingsService.instance.updateRange(
                SettingsService.instance.currentStage,
                key,
                min,
                max,
              );
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Update',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalField(
    String label,
    TextEditingController ctrl,
    String unit,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.dark,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          decoration: InputDecoration(
            suffixText: unit,
            suffixStyle: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.darkWith(0.4),
            ),
            filled: true,
            fillColor: AppColors.darkWith(0.04),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditProfile() {
    return Container(
      color: const Color(0xFFf7f7f7),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkWith(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: AppColors.darkWith(0.05)),
            ),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primaryWith(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryWith(0.2),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppColors.primary,
                        size: 40,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildField('Full Name', _nameCtrl),
                const SizedBox(height: 16),
                _buildField('Email Address', _emailCtrl),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangePassword() {
    return Container(
      color: const Color(0xFFf7f7f7),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkWith(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: AppColors.darkWith(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your password must be at least 8 characters long.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.dark,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                _buildField('Current Password', _currentPwCtrl, obscure: true),
                const SizedBox(height: 16),
                _buildField('New Password', _newPwCtrl, obscure: true),
                const SizedBox(height: 16),
                _buildField(
                  'Confirm New Password',
                  _confirmPwCtrl,
                  obscure: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _changePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Update Password',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifSettings() {
    return Container(
      color: const Color(0xFFf7f7f7),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMenuSection('General Settings', [
              _buildToggle(
                'Notification Sound',
                'Play sound for incoming alerts',
                _notifSound,
                (v) => setState(() => _notifSound = v ?? true),
              ),
              _buildToggle(
                'Vibration',
                'Vibrate on important updates',
                _notifVibration,
                (v) => setState(() => _notifVibration = v ?? true),
              ),
            ]),
            const SizedBox(height: 12),
            _buildMenuSection('Alerts & Reminders', [
              _buildToggle(
                'Water Quality Alerts',
                'Critical alerts for all water parameters',
                _notifCritical,
                (v) => setState(() => _notifCritical = v ?? true),
              ),
              _buildToggle(
                'Feeding Reminders',
                'Confirmations for daily feeding',
                _notifFeeding,
                (v) => setState(() => _notifFeeding = v ?? true),
              ),
              _buildToggle(
                'Sampling Schedule',
                'Weekly growth tracking reminders',
                _notifSampling,
                (v) => setState(() => _notifSampling = v ?? false),
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.darkWith(0.6),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: const TextStyle(fontSize: 13, color: AppColors.dark),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.darkWith(0.04),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.darkWith(0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.darkWith(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.primaryWith(0.5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggle(
    String label,
    String subtitle,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.04)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.darkWith(0.4),
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeColor: AppColors.primary,
                activeTrackColor: AppColors.primaryWith(0.2),
                inactiveTrackColor: AppColors.darkWith(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
