import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/database_service.dart';
import '../widgets/section_label.dart';

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

  String _displayName(Map<String, dynamic> user) {
    return (user['fullName'] as String?) ??
        (user['displayName'] as String?) ??
        (user['email'] as String?) ??
        'User';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await DatabaseService.instance.getAllUsers();
      final assignment = await DatabaseService.instance.getDeviceAssignment();
      users.sort((a, b) => (a['email'] as String? ?? '')
          .compareTo(b['email'] as String? ?? ''));
      if (!mounted) return;
      setState(() {
        _users = users;
        _deviceOwnerUid = assignment?['assignedTankId'] as String?;
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

  Future<bool?> _confirm({required String title, required String message, IconData? icon, Color? iconColor}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: null,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (iconColor ?? AppColors.primary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: iconColor ?? AppColors.primary),
              ),
            if (icon != null) const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.darkText)),
            const SizedBox(height: 8),
            Text(message,
                style: const TextStyle(fontSize: 12, color: AppColors.subtitleText, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cancel', style: TextStyle(color: AppColors.mutedText, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: AppColors.dark,
      ),
    );
  }

  void _openUserSheet(Map<String, dynamic> user) {
    final uid = user['uid'] as String;
    final name = _displayName(user);
    final email = user['email'] as String? ?? '';
    final role = (user['role'] as String?) ?? 'owner';
    final status = (user['status'] as String?) ?? 'active';
    final isAdmin = role == 'admin';

    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join();
    final avatarColor = isAdmin ? AppColors.dark : AppColors.primary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            String currentRole = role;
            String currentStatus = status;
            bool isDisabled = currentStatus == 'disabled';
            bool isOwner = uid == _deviceOwnerUid;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // User avatar + name
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: avatarColor.withValues(alpha: isDisabled ? 0.06 : 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: avatarColor.withValues(alpha: isDisabled ? 0.08 : 0.15),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initials.toUpperCase(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDisabled ? AppColors.mutedText : avatarColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: isDisabled ? AppColors.mutedText : AppColors.darkText,
                        )),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(email,
                          style: const TextStyle(fontSize: 12, color: AppColors.subtitleText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildMiniBadge(
                          label: currentRole.toUpperCase(),
                          color: isAdmin ? AppColors.dark : AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        _buildMiniBadge(
                          label: isDisabled ? 'DISABLED' : 'ACTIVE',
                          color: isDisabled ? AppColors.critical : AppColors.success,
                        ),
                        if (isOwner) ...[
                          const SizedBox(width: 8),
                          _buildMiniBadge(label: 'HARDWARE', color: AppColors.primary),
                        ],
                      ],
                    ),

                    const SizedBox(height: 20),
                    Container(height: 1, color: AppColors.darkWith(0.06)),
                    const SizedBox(height: 16),

                    // Role section
                    _buildSectionHeader(Icons.badge_outlined, 'Role'),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: AppColors.darkWith(0.03),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildRoleOption(
                              ctx: ctx,
                              label: 'Owner',
                              icon: Icons.person_outline_rounded,
                              isSelected: currentRole == 'owner',
                              onTap: () async {
                                if (currentRole == 'owner') return;
                                final selfUid = FirebaseAuth.instance.currentUser?.uid;
                                if (uid == selfUid) {
                                  _showSnack('You can\'t remove your own admin role from here.');
                                  return;
                                }
                                await DatabaseService.instance.setUserRole(uid, 'owner');
                                if (!ctx.mounted) return;
                                setSheetState(() => currentRole = 'owner');
                                if (!mounted) return;
                                await _load();
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _buildRoleOption(
                              ctx: ctx,
                              label: 'Admin',
                              icon: Icons.admin_panel_settings_outlined,
                              isSelected: currentRole == 'admin',
                              onTap: () async {
                                if (currentRole == 'admin') return;
                                await DatabaseService.instance.setUserRole(uid, 'admin');
                                if (!ctx.mounted) return;
                                setSheetState(() => currentRole = 'admin');
                                if (!mounted) return;
                                await _load();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Status section
                    _buildSectionHeader(
                      Icons.circle,
                      'Account Status',
                      iconColor: isDisabled ? AppColors.critical : AppColors.success,
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        final selfUid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == selfUid) {
                          _showSnack('You can\'t disable your own admin account.');
                          return;
                        }
                        final newStatus = isDisabled ? 'active' : 'disabled';
                        final confirmed = await _confirm(
                          title: isDisabled ? 'Enable account?' : 'Disable account?',
                          message: isDisabled
                              ? '$name will be able to sign in again.'
                              : '$name will be signed out and blocked from signing back in.',
                          icon: isDisabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                          iconColor: isDisabled ? AppColors.success : AppColors.critical,
                        );
                        if (confirmed != true) return;
                        await DatabaseService.instance.setUserStatus(uid, newStatus);
                        if (!ctx.mounted) return;
                        setSheetState(() => currentStatus = newStatus);
                        if (!mounted) return;
                        await _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: (isDisabled ? AppColors.critical : AppColors.success).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (isDisabled ? AppColors.critical : AppColors.success).withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: (isDisabled ? AppColors.critical : AppColors.success).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isDisabled ? Icons.lock_rounded : Icons.lock_open_rounded,
                                size: 18,
                                color: isDisabled ? AppColors.critical : AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isDisabled ? 'Account Disabled' : 'Account Active',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDisabled ? AppColors.critical : AppColors.success,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    isDisabled
                                        ? 'Tap to re-enable this account'
                                        : 'Tap to disable this account',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.darkWith(0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isDisabled ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                              size: 32,
                              color: isDisabled ? AppColors.critical : AppColors.success,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Hardware section
                    _buildSectionHeader(Icons.sensors_rounded, 'Hardware Assignment'),
                    const SizedBox(height: 10),
                    if (isOwner)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Currently Assigned',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'This user receives sensor alerts & feeding reminders',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.darkWith(0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () async {
                          final confirmed = await _confirm(
                            title: 'Assign hardware to $name?',
                            message:
                                'This will transfer the sensor hardware to $name. '
                                'Only they will receive live sensor alerts and feeding reminders. '
                                'The previous owner will lose access.',
                            icon: Icons.sensors_rounded,
                            iconColor: AppColors.primary,
                          );
                          if (confirmed != true) return;
                          await DatabaseService.instance.setDeviceAssignment(uid);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          await _load();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.darkWith(0.03),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.darkWith(0.1)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.sensors_rounded, size: 18, color: AppColors.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Transfer Hardware',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.darkText,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'Assign sensor hardware to this user',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.darkWith(0.45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.darkWith(0.3)),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMiniBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String label, {Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor ?? AppColors.darkWith(0.4)),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.darkWith(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleOption({
    required BuildContext ctx,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.3) : AppColors.darkWith(0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.primary : AppColors.darkWith(0.35),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? AppColors.primary : AppColors.darkWith(0.45),
              ),
            ),
          ],
        ),
      ),
    );
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
                _buildStatsBar(),
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
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
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
                  child: Column(
                    children: _users.map(_buildUserCard).toList(),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }

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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  Widget _buildStatsBar() {
    final totalUsers = _users.length;
    final activeUsers = _users.where((u) => (u['status'] ?? 'active') == 'active').length;
    final disabledUsers = totalUsers - activeUsers;
    final hasHardware = _deviceOwnerUid != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  value: '$totalUsers',
                  label: 'Total Users',
                  icon: Icons.people_alt_rounded,
                  color: AppColors.primary,
                  bgColor: AppColors.primaryWith(0.08),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  value: '$activeUsers',
                  label: 'Active',
                  icon: Icons.check_circle_outline_rounded,
                  color: AppColors.success,
                  bgColor: AppColors.successWith(0.08),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  value: '$disabledUsers',
                  label: 'Disabled',
                  icon: Icons.block_rounded,
                  color: AppColors.critical,
                  bgColor: AppColors.criticalWith(0.08),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  value: hasHardware ? '1' : '0',
                  label: 'Hardware',
                  icon: Icons.sensors_rounded,
                  color: hasHardware ? AppColors.success : AppColors.mutedText,
                  bgColor: (hasHardware ? AppColors.success : AppColors.mutedText).withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkWith(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceOwnerCard() {
    final owner = _users.where((u) => u['uid'] == _deviceOwnerUid).toList();
    final ownerName = owner.isNotEmpty ? _displayName(owner.first) : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _deviceOwnerUid != null
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.darkWith(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.sensors_rounded,
              color: _deviceOwnerUid != null ? AppColors.primary : AppColors.mutedText,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hardware currently assigned to',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5)),
                ),
                const SizedBox(height: 3),
                Text(
                  ownerName ?? 'Not assigned',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.darkText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_deviceOwnerUid != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('ACTIVE',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.success, letterSpacing: 0.5)),
            ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final uid = user['uid'] as String;
    final email = user['email'] as String? ?? '';
    final name = _displayName(user);
    final role = (user['role'] as String?) ?? 'owner';
    final status = (user['status'] as String?) ?? 'active';
    final isDisabled = status == 'disabled';
    final isDeviceOwner = uid == _deviceOwnerUid;
    final isAdmin = role == 'admin';

    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join();
    final avatarColor = isAdmin ? AppColors.dark : AppColors.primary;

    return GestureDetector(
      onTap: () => _openUserSheet(user),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFCFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDeviceOwner
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.darkWith(0.1),
            width: isDeviceOwner ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkWith(isDeviceOwner ? 0.1 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: avatarColor.withValues(alpha: isDisabled ? 0.06 : 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: avatarColor.withValues(alpha: isDisabled ? 0.06 : 0.1),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  initials.toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDisabled ? AppColors.mutedText : avatarColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: isDisabled ? AppColors.mutedText : AppColors.darkText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isAdmin ? AppColors.dark : AppColors.primary).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: isAdmin ? AppColors.dark : AppColors.primary,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(email,
                        style: const TextStyle(fontSize: 11, color: AppColors.subtitleText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isDeviceOwner)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sensors_rounded, size: 9, color: AppColors.primary),
                        SizedBox(width: 3),
                        Text('HW',
                            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 0.3)),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isDisabled ? AppColors.critical : AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.darkWith(0.2)),
          ],
        ),
      ),
    );
  }
}
