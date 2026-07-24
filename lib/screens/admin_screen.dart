import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/database_service.dart';
import '../widgets/section_label.dart';

/// Admin-only screen. Shown as a tab in MainShell only when the signed-in
/// user's Firestore profile has role == 'admin'. Also enforced server-side
/// by firestore.rules. Uses the same greeting-card + section-label pattern
/// as DashboardScreen so it matches the rest of the app, and sits under
/// MainShell's shared header — so the profile avatar (top-right) still
/// opens Settings exactly like it does on every other tab.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map<String, dynamic>> _users = [];
  String? _deviceOwnerUid;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _getGreetingTime() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    const weekdays = [
      'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[now.weekday % 7]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await DatabaseService.instance.getAllUsers();
      final deviceOwner = await DatabaseService.instance.getDeviceOwner();
      users.sort((a, b) => (a['email'] as String? ?? '')
          .compareTo(b['email'] as String? ?? ''));
      if (!mounted) return;
      setState(() {
        _users = users;
        _deviceOwnerUid = deviceOwner?['ownerUid'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load admin data: $e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> user) async {
    final uid = user['uid'] as String;
    final currentStatus = (user['status'] as String?) ?? 'active';
    final newStatus = currentStatus == 'disabled' ? 'active' : 'disabled';

    if (uid == FirebaseAuth.instance.currentUser?.uid) {
      _showSnack('You can\'t disable your own admin account.');
      return;
    }

    final confirmed = await _confirm(
      title: newStatus == 'disabled' ? 'Disable account?' : 'Enable account?',
      message: newStatus == 'disabled'
          ? '${user['email']} will be signed out and blocked from signing back in.'
          : '${user['email']} will be able to sign in again.',
    );
    if (confirmed != true) return;

    await DatabaseService.instance.setUserStatus(uid, newStatus);
    await _load();
  }

  Future<void> _changeRole(Map<String, dynamic> user, String newRole) async {
    final uid = user['uid'] as String;
    if (uid == FirebaseAuth.instance.currentUser?.uid && newRole != 'admin') {
      _showSnack('You can\'t remove your own admin role from here.');
      return;
    }
    await DatabaseService.instance.setUserRole(uid, newRole);
    await _load();
  }

  Future<void> _assignDeviceOwner(Map<String, dynamic> user) async {
    final uid = user['uid'] as String;
    final confirmed = await _confirm(
      title: 'Assign hardware to this account?',
      message:
          '${user['email']} will become the owner of the sensor readings — only '
          'they and admins will be able to view live readings from the tank.',
    );
    if (confirmed != true) return;

    await DatabaseService.instance.setDeviceOwner(uid);
    await _load();
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreeting(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: const TextStyle(color: AppColors.critical)),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: SectionLabel(
                    label: 'Shared Hardware',
                    showLiveData: false,
                    icon: Icons.sensors_rounded,
                    topPadding: 4,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _buildDeviceOwnerCard(),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: SectionLabel(
                    label: 'Users',
                    showLiveData: false,
                    icon: Icons.people_alt_rounded,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(children: _users.map(_buildUserCard).toList()),
                ),
                const SizedBox(height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Same gradient card, accent bar, and typography as DashboardScreen's
  // greeting — just "Admin" instead of the tank owner's first name.
  Widget _buildGreeting() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 23, 20, 23),
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
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_getGreetingTime()}, Admin!',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _getFormattedDate(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: AppColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Here's what's happening across all accounts today.",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.subtitleText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.admin_panel_settings_rounded, color: AppColors.primary, size: 26),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceOwnerCard() {
    final owner = _users.where((u) => u['uid'] == _deviceOwnerUid).toList();
    final ownerLabel = owner.isNotEmpty
        ? (owner.first['email'] as String? ?? owner.first['uid'])
        : (_deviceOwnerUid == null ? 'Not assigned' : _deviceOwnerUid);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.sensors_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hardware currently assigned to',
                    style: TextStyle(fontSize: 12, color: AppColors.subtitleText, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(ownerLabel ?? 'Not assigned',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.darkText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final uid = user['uid'] as String;
    final email = user['email'] as String? ?? '(no email)';
    final name = user['displayName'] as String? ?? 'CrayCare User';
    final role = (user['role'] as String?) ?? 'owner';
    final status = (user['status'] as String?) ?? 'active';
    final isDisabled = status == 'disabled';
    final isDeviceOwner = uid == _deviceOwnerUid;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.darkText)),
                    Text(email,
                        style: const TextStyle(fontSize: 12, color: AppColors.subtitleText)),
                  ],
                ),
              ),
              if (isDeviceOwner)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('DEVICE OWNER',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _roleDropdown(user, role),
              _statusChip(isDisabled),
              TextButton.icon(
                onPressed: () => _toggleStatus(user),
                icon: Icon(isDisabled ? Icons.lock_open_rounded : Icons.lock_rounded, size: 16),
                label: Text(isDisabled ? 'Enable' : 'Disable'),
                style: TextButton.styleFrom(
                  foregroundColor: isDisabled ? AppColors.success : AppColors.critical,
                ),
              ),
              if (!isDeviceOwner)
                OutlinedButton.icon(
                  onPressed: () => _assignDeviceOwner(user),
                  icon: const Icon(Icons.sensors_rounded, size: 16),
                  label: const Text('Set as device owner'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roleDropdown(Map<String, dynamic> user, String role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.lightBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: role,
          isDense: true,
          items: const [
            DropdownMenuItem(value: 'owner', child: Text('Owner')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
          ],
          onChanged: (v) {
            if (v != null && v != role) _changeRole(user, v);
          },
        ),
      ),
    );
  }

  Widget _statusChip(bool isDisabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (isDisabled ? AppColors.critical : AppColors.success).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isDisabled ? 'Disabled' : 'Active',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDisabled ? AppColors.critical : AppColors.success,
        ),
      ),
    );
  }
}
