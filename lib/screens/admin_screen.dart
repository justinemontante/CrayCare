import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/database_service.dart';

/// Admin-only screen. Shown in MainShell only when the signed-in user's
/// Firestore profile has role == 'admin'. Also enforced server-side by
/// firestore.rules, so even a modified client can't actually read/write
/// other users' docs without the role being set on their own profile.
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
          'they (and any monitors linked to them) will be able to view live '
          'readings from the tank.',
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
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        title: const Text('Admin'),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildDeviceOwnerCard(),
                      const SizedBox(height: 20),
                      const Text(
                        'Users',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.darkText),
                      ),
                      const SizedBox(height: 8),
                      ..._users.map(_buildUserCard),
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
              if (!isDeviceOwner && role != 'monitor')
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
            DropdownMenuItem(value: 'monitor', child: Text('Monitor')),
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
