import 'dart:convert';
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
  // ownerUid -> hardwareId (from hardwareAssignments collection)
  Map<String, String> _hardwareOwnerMap = {};
  bool _loading = true;
  String? _error;
  int _userFilterTab = 0; // 0 = All, 1 = Owners, 2 = Admins

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
      // Load users first — this must succeed.
      final users = await DatabaseService.instance.getAllUsers();
      users.sort((a, b) => (a['email'] as String? ?? '')
          .compareTo(b['email'] as String? ?? ''));

      // Load hardware assignments separately — failure is non-fatal so the
      // admin can still manage users while Firestore rules are being deployed.
      final hwMap = <String, String>{};
      try {
        final assignments = await DatabaseService.instance.getAllHardwareAssignments();
        for (final a in assignments) {
          final ownerUid = a['ownerUid'] as String?;
          final hardwareId = a['hardwareId'] as String?;
          if (ownerUid != null && hardwareId != null) {
            hwMap[ownerUid] = hardwareId;
          }
        }
      } catch (_) {
        // Hardware assignment rules may not be deployed yet — continue
        // without the hardware overlay on user cards.
      }

      if (!mounted) return;
      setState(() {
        _users = users;
        _hardwareOwnerMap = hwMap;
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

  // A regular SnackBar is anchored to this screen's own Scaffold, which
  // sits BELOW modal bottom sheets in the overlay stack — so it renders
  // hidden behind the modal instead of on top of it. Inserting into the
  // root overlay guarantees it always shows in front, even while a
  // modal (like the user sheet) is open.
  void _showSnack(String message) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
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
        // Declare mutable state OUTSIDE StatefulBuilder.builder so they
        // persist across setSheetState rebuilds (not re-initialized each call).
        String currentRole = role;
        String currentStatus = status;
        String? assignedHardwareId = _hardwareOwnerMap[uid];

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            bool isDisabled = currentStatus == 'disabled';

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
                        if (assignedHardwareId != null) ...[
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
                                if (currentRole == 'admin') {
                                  _showSnack('You can\'t demote another admin. Only the admin themselves can change their role.');
                                  return;
                                }
                                final confirmed = await _confirm(
                                  title: 'Demote to Owner?',
                                  message: '$name will lose admin privileges and return to a regular owner account.',
                                  icon: Icons.person_outline_rounded,
                                  iconColor: AppColors.primary,
                                );
                                if (confirmed != true) return;
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
                                final confirmed = await _confirm(
                                  title: 'Promote to Admin?',
                                  message: '$name will gain full admin privileges, including the ability to manage other users.',
                                  icon: Icons.admin_panel_settings_rounded,
                                  iconColor: AppColors.dark,
                                );
                                if (confirmed != true) return;
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

                    // Hardware Assignment section (owners only)
                    if (currentRole != 'admin') ...[
                      _buildSectionHeader(Icons.developer_board_rounded, 'Hardware'),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.darkWith(0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.darkWith(0.08)),
                        ),
                        child: assignedHardwareId != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: AppColors.success.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.check_circle_rounded,
                                            size: 18, color: AppColors.success),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Hardware linked',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.success)),
                                            const SizedBox(height: 2),
                                            Text('Data routes to ${_displayName(user)}\'s account',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.subtitleText)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: GestureDetector(
                                      onTap: () async {
                                        final confirmed = await _confirm(
                                          title: 'Unassign Hardware?',
                                          message:
                                              '${_displayName(user)} will lose access to the hardware. Sensor data, auto feeder, and all device features will stop routing to their account.',
                                          icon: Icons.link_off_rounded,
                                          iconColor: AppColors.critical,
                                        );
                                        if (confirmed != true || !ctx.mounted) return;
                                        await DatabaseService.instance
                                            .removeHardwareAssignment(assignedHardwareId!);
                                        if (!mounted) return;
                                        await _load();
                                        setSheetState(() {
                                          assignedHardwareId = null;
                                        });
                                        _showSnack('Hardware unassigned.');
                                      },
                                      child: _buildActionChip(
                                          'Unassign', Icons.link_off_rounded, AppColors.critical),
                                    ),
                                  ),
                                ],
                              )
                            : GestureDetector(
                                onTap: () async {
                                  // If we already know the hardware ID from another owner, use it directly.
                                  // Otherwise, ask the admin to enter it once.
                                  String? hardwareIdToAssign;
                                  if (_hardwareOwnerMap.isNotEmpty) {
                                    hardwareIdToAssign = _hardwareOwnerMap.values.first;
                                  } else {
                                    hardwareIdToAssign = await _showHardwareInputDialog();
                                    if (hardwareIdToAssign == null) return;
                                  }
                                  if (!ctx.mounted) return;
                                  final confirmed = await _confirm(
                                    title: 'Assign Hardware?',
                                    message:
                                        'The hardware will be linked to ${_displayName(user)}\'s account. Sensor data, auto feeder, and all device features will route to them.',
                                    icon: Icons.developer_board_rounded,
                                    iconColor: AppColors.primary,
                                  );
                                  if (confirmed != true || !ctx.mounted) return;
                                  await DatabaseService.instance
                                      .setHardwareAssignment(hardwareIdToAssign, uid);
                                  if (!mounted) return;
                                  await _load();
                                  setSheetState(() {
                                    assignedHardwareId = hardwareIdToAssign;
                                  });
                                  _showSnack('Hardware assigned to ${_displayName(user)}.');
                                },
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppColors.darkWith(0.05),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.add_rounded,
                                          size: 18, color: AppColors.darkWith(0.4)),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text('Link hardware to this account',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.subtitleText,
                                              fontWeight: FontWeight.w500)),
                                    ),
                                    Icon(Icons.chevron_right_rounded,
                                        size: 18, color: AppColors.darkWith(0.25)),
                                  ],
                                ),
                              ),
                      ),
                    ],

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _showHardwareInputDialog({String? prefill}) async {
    final controller = TextEditingController(text: prefill ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Text('Hardware ID',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.darkText)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the hardware ID printed on the ESP32 device (e.g. ESP_AABBCCDDEEFF). '
              'You can also find it in the Serial Monitor output on boot.',
              style: TextStyle(fontSize: 12, color: AppColors.subtitleText, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: AppColors.darkText,
              ),
              decoration: InputDecoration(
                hintText: 'ESP_AABBCCDDEEFF',
                hintStyle: TextStyle(color: AppColors.darkWith(0.3), fontSize: 12),
                filled: true,
                fillColor: AppColors.darkWith(0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.darkWith(0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.darkWith(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.mutedText, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          TextButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isEmpty) return;
              Navigator.pop(ctx, val);
            },
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sticky header — never scrolls ─────────────────────────
          _buildGreeting(),
          if (!_loading && _error == null) ...[
            _buildStatsBar(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: SectionLabel(
                label: 'Users',
                showLiveData: false,
                icon: Icons.people_alt_rounded,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
              child: _buildUserFilterTabBar(),
            ),
          ],
          // ── Scrollable user list ───────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppColors.critical),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
                          children: _filteredUsers().map(_buildUserCard).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredUsers() {
    final selfUid = FirebaseAuth.instance.currentUser?.uid;
    List<Map<String, dynamic>> list;
    if (_userFilterTab == 1) {
      list = _users.where((u) => (u['role'] as String? ?? 'owner') == 'owner').toList();
    } else if (_userFilterTab == 2) {
      list = _users.where((u) => (u['role'] as String? ?? 'owner') == 'admin').toList();
    } else {
      list = List.from(_users);
    }
    // Always pin the logged-in user's card to the top.
    list.sort((a, b) {
      final aIsSelf = a['uid'] == selfUid ? 0 : 1;
      final bIsSelf = b['uid'] == selfUid ? 0 : 1;
      return aIsSelf.compareTo(bIsSelf);
    });
    return list;
  }

  Widget _buildUserFilterTabBar() {
    final tabs = [
      (Icons.people_alt_rounded, 'All'),
      (Icons.person_outline_rounded, 'Owners'),
      (Icons.admin_panel_settings_outlined, 'Admins'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.dark.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = _userFilterTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _userFilterTab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.dark.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tabs[i].$1,
                      size: 13,
                      color: isActive ? AppColors.primary : AppColors.dark.withValues(alpha: 0.45),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tabs[i].$2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isActive ? AppColors.primary : AppColors.dark.withValues(alpha: 0.45),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              value: '$totalUsers',
              label: 'Total Users',
              icon: Icons.groups_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard(
              value: '$activeUsers',
              label: 'Active',
              icon: Icons.how_to_reg_rounded,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard(
              value: '$disabledUsers',
              label: 'Disabled',
              icon: Icons.person_off_rounded,
              color: AppColors.critical,
            ),
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
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.darkWith(0.5),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    final isDeviceOwner = _hardwareOwnerMap.containsKey(uid);
    final isAdmin = role == 'admin';
    final photoImage = _photoImageProvider(user['photoUrl'] as String?);

    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join();

    // Accent color mirrors notification type-color logic
    final Color accentColor = isDisabled
        ? AppColors.critical
        : isAdmin
            ? AppColors.dark
            : AppColors.primary;

    final bool highlighted = isDeviceOwner || isDisabled;

    return GestureDetector(
      onTap: () => _openUserSheet(user),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
        decoration: BoxDecoration(
          color: highlighted ? accentColor.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlighted
                ? accentColor.withValues(alpha: 0.25)
                : AppColors.darkWith(0.08),
            width: highlighted ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar — same 28×28 / radius-8 as notification icon container
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDisabled ? 0.07 : 0.12),
                borderRadius: BorderRadius.circular(8),
                image: photoImage != null
                    ? DecorationImage(image: photoImage, fit: BoxFit.cover)
                    : null,
              ),
              child: photoImage == null
                  ? Center(
                      child: Text(
                        initials.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isDisabled ? AppColors.mutedText : accentColor,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDisabled ? AppColors.mutedText : AppColors.dark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Hardware-assigned dot — mirrors unread dot in notif card
                      if (isDeviceOwner)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.darkWith(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  // Meta row — role · status · hardware tag
                  Row(
                    children: [
                      Text(
                        isAdmin ? 'Admin' : 'Owner',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isDisabled ? AppColors.mutedText : accentColor,
                        ),
                      ),
                      Text(
                        ' · ',
                        style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.3)),
                      ),
                      Text(
                        isDisabled ? 'Disabled' : 'Active',
                        style: TextStyle(
                          fontSize: 9,
                          color: isDisabled
                              ? AppColors.critical
                              : AppColors.darkWith(0.4),
                        ),
                      ),
                      if (isDeviceOwner) ...[
                        Text(
                          ' · ',
                          style: TextStyle(
                              fontSize: 9, color: AppColors.darkWith(0.3)),
                        ),
                        Text(
                          'Hardware assigned',
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.darkWith(0.2),
              ),
            ),
          ],
        ),
      ),
    );
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
}
