import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../screens/login_screen.dart';

class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  int _currentPage = 0;
  String _profileName = 'Justine';
  String _profileEmail = 'justine@craycare.com';

  final _pageController = PageController();
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
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _nameCtrl.text = _profileName;
    _emailCtrl.text = _profileEmail;
    _pageController.animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _currentPage = page);
  }

  void _back() {
    if (_currentPage == 0) {
      Navigator.of(context).pop();
    } else {
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentPage = 0);
    }
  }

  void _saveProfile() {
    setState(() {
      _profileName = _nameCtrl.text.isNotEmpty ? _nameCtrl.text : _profileName;
      _profileEmail = _emailCtrl.text.isNotEmpty ? _emailCtrl.text : _profileEmail;
    });
    _back();
  }

  void _changePassword() {
    if (_newPwCtrl.text.isNotEmpty && _newPwCtrl.text == _confirmPwCtrl.text) {
      _back();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _showLogoutSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                const Text('Logout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dark)),
                const SizedBox(height: 8),
                const Text('Are you sure you want to logout?', style: TextStyle(fontSize: 12, color: AppColors.dark)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pop();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.critical,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Yes, Logout', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dark)),
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
      width: MediaQuery.of(context).size.width * 0.85,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMainMenu(),
                  _buildEditProfile(),
                  _buildChangePassword(),
                  _buildNotifSettings(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
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
          ),
          const SizedBox(width: 4),
          Text(
            _currentPage == 0 ? 'Profile & Settings' : _pageTitle,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.dark),
          ),
        ],
      ),
    );
  }

  String get _pageTitle {
    switch (_currentPage) {
      case 1: return 'Edit Profile';
      case 2: return 'Change Password';
      case 3: return 'Notifications';
      default: return '';
    }
  }

  Widget _buildMainMenu() {
    return Container(
      color: const Color(0xFFf7f7f7),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          children: [
            _buildProfileCard(),
            const SizedBox(height: 8),
            _buildMenuSection('Account', [
              _buildMenuItem('Edit Profile', Icons.person, AppColors.primary, chevron: true, onTap: () => _goTo(1)),
              _buildMenuItem('Change Password', Icons.lock, AppColors.primary, chevron: true, onTap: () => _goTo(2)),
            ]),
            const SizedBox(height: 8),
            _buildMenuSection('Preferences', [
              _buildMenuItem('Notifications', Icons.notifications, AppColors.warning, chevron: true, onTap: () => _goTo(3)),
            ]),
            const SizedBox(height: 8),
            _buildMenuItem('Logout', Icons.logout, AppColors.critical, onTap: _showLogoutSheet),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppColors.darkWith(0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: const Icon(Icons.person, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_profileName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.dark)),
              const SizedBox(height: 2),
              Text(_profileEmail, style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.5))),
            ],
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4), letterSpacing: 0.3)),
        ),
        ...items,
      ],
    );
  }

  Widget _buildMenuItem(String label, IconData icon, Color color, {bool chevron = false, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: label == 'Logout' ? AppColors.critical : AppColors.dark,
                    ),
                  ),
                ),
                if (chevron) Icon(Icons.chevron_right, size: 16, color: AppColors.darkWith(0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditProfile() {
    return Container(
      color: const Color(0xFFf7f7f7),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.darkWith(0.05), blurRadius: 6)],
            ),
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 64, height: 64,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.person, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.primaryWith(0.1), borderRadius: BorderRadius.circular(20)),
                    child: const Text('Change Photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 16),
                _buildField('Full Name', _nameCtrl),
                const SizedBox(height: 12),
                _buildField('Email', _emailCtrl),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.darkWith(0.05), blurRadius: 6)],
            ),
            child: Column(
              children: [
                _buildField('Current Password', _currentPwCtrl, obscure: true),
                const SizedBox(height: 12),
                _buildField('New Password', _newPwCtrl, obscure: true),
                const SizedBox(height: 12),
                _buildField('Confirm Password', _confirmPwCtrl, obscure: true),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _changePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Update Password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildToggle('Allow Notifications', _notifAllow, (v) => setState(() => _notifAllow = v ?? true)),
          const SizedBox(height: 6),
          _buildToggle('Allow Sound', _notifSound, (v) => setState(() => _notifSound = v ?? true)),
          const SizedBox(height: 6),
          _buildToggle('Allow Vibration', _notifVibration, (v) => setState(() => _notifVibration = v ?? true)),
          const SizedBox(height: 6),
          _buildToggle('Critical Water Warnings', _notifCritical, (v) => setState(() => _notifCritical = v ?? true)),
          const SizedBox(height: 6),
          _buildToggle('Feeding Confirmations', _notifFeeding, (v) => setState(() => _notifFeeding = v ?? true)),
          const SizedBox(height: 6),
          _buildToggle('Sampling Reminders', _notifSampling, (v) => setState(() => _notifSampling = v ?? false)),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.6))),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: const TextStyle(fontSize: 13, color: AppColors.dark),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.darkWith(0.04),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  Widget _buildToggle(String label, bool value, ValueChanged<bool?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.dark)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
