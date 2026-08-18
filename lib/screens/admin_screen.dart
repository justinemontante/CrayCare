import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_helper.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final TextEditingController _search = TextEditingController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _ownerSub;

  List<Map<String, dynamic>> _users = [];
  String? _ownerUid;
  String _query = '';
  int _filter = 0; // 0 all, 1 owners, 2 admins
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _listenRealtime();
  }

  @override
  void dispose() {
    _search.dispose();
    _usersSub?.cancel();
    _ownerSub?.cancel();
    super.dispose();
  }

  void _listenRealtime() {
    _usersSub?.cancel();
    _usersSub = FirebaseFirestore.instance.collection('users').snapshots().listen(
      (snapshot) {
        final users = snapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['uid'] = doc.id;
          return data;
        }).toList();
        if (!mounted) return;
        setState(() {
          _users = users;
          _loading = false;
          _error = null;
        });
      },
      onError: (error) {
        debugPrint('[AdminScreen] users stream error: $error');
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Unable to load users.';
        });
      },
    );

    _ownerSub?.cancel();
    _ownerSub = DatabaseService.instance.streamCurrentOwner().listen(
      (doc) {
        if (!mounted) return;
        setState(() => _ownerUid = doc.data()?['uid'] as String?);
      },
      onError: (error) =>
          debugPrint('[AdminScreen] owner stream error: $error'),
    );
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final users = await DatabaseService.instance.getAllUsers();
      final ownerUid = await DatabaseService.instance.getCurrentOwnerUid();
      if (!mounted) return;
      setState(() {
        _users = users;
        _ownerUid = ownerUid;
        _loading = false;
      });
    } catch (error) {
      debugPrint('[AdminScreen] load error: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load admin data.';
      });
    }
  }

  String _displayName(Map<String, dynamic> user) {
    return (user['full_name'] as String?) ??
        (user['fullName'] as String?) ??
        (user['displayName'] as String?) ??
        (user['email'] as String?) ??
        'User';
  }

  List<Map<String, dynamic>> get _visibleUsers {
    final selfUid = FirebaseAuth.instance.currentUser?.uid;
    final query = _query.trim().toLowerCase();
    final visible = _users.where((user) {
      final role = (user['role'] as String? ?? 'owner').toLowerCase();
      if (_filter == 1 && role != 'owner') return false;
      if (_filter == 2 && role != 'admin') return false;
      if (query.isEmpty) return true;
      final name = _displayName(user).toLowerCase();
      final email = (user['email'] as String? ?? '').toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();

    visible.sort((a, b) {
      final aSelf = a['uid'] == selfUid ? 0 : 1;
      final bSelf = b['uid'] == selfUid ? 0 : 1;
      if (aSelf != bSelf) return aSelf.compareTo(bSelf);
      return _displayName(a)
          .toLowerCase()
          .compareTo(_displayName(b).toLowerCase());
    });
    return visible;
  }

  Map<String, dynamic>? get _hardwareOwner {
    for (final user in _users) {
      if (user['uid'] == _ownerUid) return user;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7FAFA),
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_error != null)
              _buildErrorState()
            else ...[
              _buildStats(),
              const SizedBox(height: 12),
              _buildHardwareCard(),
              const SizedBox(height: 18),
              _buildUsersHeader(),
              const SizedBox(height: 10),
              _buildSearchBox(),
              const SizedBox(height: 9),
              _buildFilters(),
              const SizedBox(height: 10),
              if (_visibleUsers.isEmpty)
                _buildEmptyState()
              else
                ..._visibleUsers.map(
                  (user) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _buildUserCard(user),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF0FBFB), Color(0xFFE4F7F7)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: AppColors.primary,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Center',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkText,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Accounts, roles and hardware access',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.subtitleText,
                  ),
                ),
              ],
            ),
          ),
          _buildBadge('LIVE', AppColors.success, dot: true),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final owners = _users
        .where((user) => (user['role'] as String? ?? 'owner') == 'owner')
        .length;
    final admins = _users
        .where((user) => (user['role'] as String? ?? 'owner') == 'admin')
        .length;
    final disabled = _users
        .where((user) =>
            (user['status'] as String? ?? 'active') == 'disabled')
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: width,
              child: _buildStatCard(
                'Total users',
                '${_users.length}',
                Icons.groups_rounded,
                AppColors.primary,
              ),
            ),
            SizedBox(
              width: width,
              child: _buildStatCard(
                'Owners',
                '$owners',
                Icons.person_rounded,
                AppColors.success,
              ),
            ),
            SizedBox(
              width: width,
              child: _buildStatCard(
                'Admins',
                '$admins',
                Icons.admin_panel_settings_rounded,
                AppColors.dark,
              ),
            ),
            SizedBox(
              width: width,
              child: _buildStatCard(
                'Disabled',
                '$disabled',
                Icons.person_off_rounded,
                AppColors.critical,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.darkWith(0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkWith(0.48),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareCard() {
    final owner = _hardwareOwner;
    final statusColor = owner == null ? AppColors.warning : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.developer_board_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hardware Assignment',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkText,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Owner currently receiving device data',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.subtitleText,
                      ),
                    ),
                  ],
                ),
              ),
              _buildBadge(
                owner == null ? 'UNASSIGNED' : 'CONNECTED',
                statusColor,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(14),
            ),
            child: owner == null
                ? const Row(
                    children: [
                      Icon(
                        Icons.link_off_rounded,
                        size: 20,
                        color: AppColors.warning,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No hardware owner. Tap an owner below to assign the device.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: AppColors.subtitleText,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _buildAvatar(owner, 42),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName(owner),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.darkText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              owner['email'] as String? ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.subtitleText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: AppColors.success,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'User Management',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.darkText,
            ),
          ),
        ),
        Text(
          '${_visibleUsers.length} shown',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AppColors.darkWith(0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBox() {
    return TextField(
      controller: _search,
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: 'Search name or email',
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: AppColors.darkWith(0.4),
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.darkWith(0.07)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.55),
            width: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.035),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          _buildFilterButton(0, 'All', Icons.people_alt_rounded),
          _buildFilterButton(1, 'Owners', Icons.person_outline_rounded),
          _buildFilterButton(2, 'Admins', Icons.admin_panel_settings_outlined),
        ],
      ),
    );
  }

  Widget _buildFilterButton(int value, String label, IconData icon) {
    final active = _filter == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: active
                    ? AppColors.primary
                    : AppColors.darkWith(0.4),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? AppColors.primary
                      : AppColors.darkWith(0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final uid = user['uid'] as String;
    final role = (user['role'] as String? ?? 'owner').toLowerCase();
    final disabled =
        (user['status'] as String? ?? 'active') == 'disabled';
    final linked = uid == _ownerUid;
    final self = uid == FirebaseAuth.instance.currentUser?.uid;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => _openUserSheet(user),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: linked
                  ? AppColors.primary.withValues(alpha: 0.28)
                  : AppColors.darkWith(0.07),
            ),
          ),
          child: Row(
            children: [
              _buildAvatar(user, 46, muted: disabled),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _displayName(user),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: disabled
                                  ? AppColors.mutedText
                                  : AppColors.darkText,
                            ),
                          ),
                        ),
                        if (self) ...[
                          const SizedBox(width: 6),
                          _buildBadge('YOU', AppColors.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user['email'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.darkWith(0.48),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _buildBadge(
                          role == 'admin' ? 'ADMIN' : 'OWNER',
                          role == 'admin' ? AppColors.dark : AppColors.primary,
                        ),
                        _buildBadge(
                          disabled ? 'DISABLED' : 'ACTIVE',
                          disabled ? AppColors.critical : AppColors.success,
                        ),
                        if (linked)
                          _buildBadge('HARDWARE', AppColors.primary),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.darkWith(0.22),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openUserSheet(Map<String, dynamic> user) {
    final uid = user['uid'] as String;
    final role = (user['role'] as String? ?? 'owner').toLowerCase();
    final disabled =
        (user['status'] as String? ?? 'active') == 'disabled';
    final linked = uid == _ownerUid;
    final self = uid == FirebaseAuth.instance.currentUser?.uid;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),
                _buildAvatar(user, 62, muted: disabled),
                const SizedBox(height: 10),
                Text(
                  _displayName(user),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user['email'] as String? ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.subtitleText,
                  ),
                ),
                const SizedBox(height: 18),
                _buildActionTile(
                  icon: disabled
                      ? Icons.lock_open_rounded
                      : Icons.lock_rounded,
                  title: disabled ? 'Enable account' : 'Disable account',
                  subtitle: self
                      ? 'Your own admin account cannot be disabled'
                      : disabled
                          ? 'Allow this user to sign in again'
                          : 'Block this user from signing in',
                  color: disabled ? AppColors.success : AppColors.critical,
                  enabled: !self,
                  onTap: () async {
                    final confirmed = await _confirm(
                      disabled ? 'Enable account?' : 'Disable account?',
                      disabled
                          ? '${_displayName(user)} will be able to sign in again.'
                          : '${_displayName(user)} will be blocked from signing in.',
                    );
                    if (!confirmed) return;
                    try {
                      await DatabaseService.instance.setUserStatus(
                        uid,
                        disabled ? 'active' : 'disabled',
                      );
                      if (!mounted) return;
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      showBeautifulSnackbar(
                        context,
                        disabled ? 'Account enabled.' : 'Account disabled.',
                        true,
                      );
                    } catch (error) {
                      if (!mounted) return;
                      showBeautifulSnackbar(
                        context,
                        'Failed to update account.',
                        false,
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                _buildActionTile(
                  icon: Icons.swap_horiz_rounded,
                  title: role == 'admin'
                      ? 'Change role to Owner'
                      : 'Change role to Admin',
                  subtitle: self
                      ? 'You cannot change your own role'
                      : 'Update account access level',
                  color: AppColors.primary,
                  enabled: !self,
                  onTap: () async {
                    final nextRole = role == 'admin' ? 'owner' : 'admin';
                    final confirmed = await _confirm(
                      'Change account role?',
                      'Change ${_displayName(user)} to ${nextRole.toUpperCase()}?',
                    );
                    if (!confirmed) return;
                    try {
                      if (linked && nextRole == 'admin') {
                        await DatabaseService.instance.removeCurrentOwner();
                      }
                      await DatabaseService.instance.setUserRole(uid, nextRole);
                      if (!mounted) return;
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      showBeautifulSnackbar(
                        context,
                        'Role updated to ${nextRole.toUpperCase()}.',
                        true,
                      );
                    } catch (error) {
                      if (!mounted) return;
                      showBeautifulSnackbar(
                        context,
                        'Failed to update role.',
                        false,
                      );
                    }
                  },
                ),
                if (role != 'admin') ...[
                  const SizedBox(height: 8),
                  _buildActionTile(
                    icon: linked ? Icons.link_off_rounded : Icons.link_rounded,
                    title: linked ? 'Unlink hardware' : 'Assign hardware',
                    subtitle: linked
                        ? 'Stop routing device data to this owner'
                        : 'Route sensor data and device access to this owner',
                    color:
                        linked ? AppColors.critical : AppColors.primary,
                    enabled: !disabled,
                    onTap: () async {
                      final confirmed = await _confirm(
                        linked ? 'Unlink hardware?' : 'Assign hardware?',
                        linked
                            ? 'Remove hardware assignment from ${_displayName(user)}?'
                            : 'Assign hardware to ${_displayName(user)}?',
                      );
                      if (!confirmed) return;
                      try {
                        if (linked) {
                          await DatabaseService.instance.removeCurrentOwner();
                        } else {
                          await DatabaseService.instance.setCurrentOwner(uid);
                        }
                        if (!mounted) return;
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        showBeautifulSnackbar(
                          context,
                          linked ? 'Hardware unlinked.' : 'Hardware assigned.',
                          true,
                        );
                      } catch (error) {
                        if (!mounted) return;
                        showBeautifulSnackbar(
                          context,
                          'Failed to update hardware assignment.',
                          false,
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: AppColors.subtitleText,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.darkWith(0.22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String message) async {
    return (await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.subtitleText,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        )) ==
        true;
  }

  Widget _buildAvatar(
    Map<String, dynamic> user,
    double size, {
    bool muted = false,
  }) {
    final role = (user['role'] as String? ?? 'owner').toLowerCase();
    final color = role == 'admin' ? AppColors.dark : AppColors.primary;
    final image = _photoProvider(
      (user['photo_url'] ?? user['photoUrl']) as String?,
    );
    final initials = _displayName(user)
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: muted ? 0.05 : 0.1),
        borderRadius: BorderRadius.circular(size * 0.3),
        image: image == null
            ? null
            : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      child: image == null
          ? Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(
                fontSize: size * 0.27,
                fontWeight: FontWeight.w800,
                color: muted ? AppColors.mutedText : color,
              ),
            )
          : null,
    );
  }

  ImageProvider<Object>? _photoProvider(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(value);
    }
    try {
      return MemoryImage(base64Decode(value.split(',').last));
    } on FormatException {
      return null;
    }
  }

  Widget _buildBadge(String label, Color color, {bool dot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Icon(Icons.circle, size: 6, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 34,
            color: AppColors.primary,
          ),
          SizedBox(height: 10),
          Text(
            'No users found',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Try another search or filter.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.subtitleText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 34,
            color: AppColors.critical,
          ),
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.subtitleText,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _load,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
