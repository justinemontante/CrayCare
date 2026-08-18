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
  final _searchController = TextEditingController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _ownerSub;

  List<Map<String, dynamic>> _users = [];
  String? _currentOwnerUid;
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
    _searchController.dispose();
    _usersSub?.cancel();
    _ownerSub?.cancel();
    super.dispose();
  }

  void _listenRealtime() {
    _usersSub?.cancel();
    _usersSub = FirebaseFirestore.instance.collection('users').snapshots().listen(
      (snap) {
        final users = snap.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['uid'] = doc.id;
          return data;
        }).toList();
        users.sort((a, b) => _displayName(a).toLowerCase().compareTo(_displayName(b).toLowerCase()));
        if (!mounted) return;
        setState(() {
          _users = users;
          _loading = false;
          _error = null;
        });
      },
      onError: (e) {
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
        setState(() => _currentOwnerUid = doc.data()?['uid'] as String?);
      },
      onError: (e) => debugPrint('[AdminScreen] owner stream error: $e'),
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
      users.sort((a, b) => _displayName(a).toLowerCase().compareTo(_displayName(b).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _users = users;
        _currentOwnerUid = ownerUid;
        _loading = false;
      });
    } catch (e) {
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

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _dateText() {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final selfUid = FirebaseAuth.instance.currentUser?.uid;
    final q = _query.trim().toLowerCase();
    final list = _users.where((user) {
      final role = (user['role'] as String? ?? 'owner').toLowerCase();
      if (_filter == 1 && role != 'owner') return false;
      if (_filter == 2 && role != 'admin') return false;
      if (q.isEmpty) return true;
      final name = _displayName(user).toLowerCase();
      final email = (user['email'] as String? ?? '').toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();

    list.sort((a, b) {
      final aSelf = a['uid'] == selfUid ? 0 : 1;
      final bSelf = b['uid'] == selfUid ? 0 : 1;
      if (aSelf != bSelf) return aSelf.compareTo(bSelf);
      return _displayName(a).toLowerCase().compareTo(_displayName(b).toLowerCase());
    });
    return list;
  }

  Map<String, dynamic>? get _hardwareOwner {
    if (_currentOwnerUid == null) return null;
    for (final user in _users) {
      if (user['uid'] == _currentOwnerUid) return user;
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
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildError(),
              )
            else ...[
              SliverToBoxAdapter(child: _buildStats()),
              SliverToBoxAdapter(child: _buildHardwareCard()),
              SliverToBoxAdapter(child: _buildUsersToolbar()),
              if (_filteredUsers.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                  sliver: SliverList.separated(
                    itemCount: _filteredUsers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (_, index) => _buildUserCard(_filteredUsers[index]),
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
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF0FBFB), Color(0xFFE3F7F7)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 5),
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
            child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primary, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting()}, Admin',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkText,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Manage accounts and hardware access',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.52)),
                ),
                const SizedBox(height: 3),
                Text(
                  _dateText(),
                  style: TextStyle(fontSize: 10.5, color: AppColors.darkWith(0.38)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: AppColors.success, size: 7),
                SizedBox(width: 5),
                Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.success, letterSpacing: 0.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final owners = _users.where((u) => (u['role'] as String? ?? 'owner') == 'owner').length;
    final admins = _users.where((u) => (u['role'] as String? ?? 'owner') == 'admin').length;
    final disabled = _users.where((u) => (u['status'] as String? ?? 'active') == 'disabled').length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(width: width, child: _statCard('Total users', '${_users.length}', Icons.groups_2_rounded, AppColors.primary)),
              SizedBox(width: width, child: _statCard('Owners', '$owners', Icons.person_rounded, AppColors.success)),
              SizedBox(width: width, child: _statCard('Admins', '$admins', Icons.admin_panel_settings_rounded, AppColors.dark)),
              SizedBox(width: width, child: _statCard('Disabled', '$disabled', Icons.person_off_rounded, AppColors.critical)),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color, height: 1)),
                const SizedBox(height: 5),
                Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.48))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareCard() {
    final owner = _hardwareOwner;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: owner != null
                ? AppColors.success.withValues(alpha: 0.22)
                : AppColors.warning.withValues(alpha: 0.22),
          ),
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
                  child: const Icon(Icons.developer_board_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hardware Assignment', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.darkText)),
                      SizedBox(height: 2),
                      Text('Current owner receiving sensor data', style: TextStyle(fontSize: 10.5, color: AppColors.subtitleText)),
                    ],
                  ),
                ),
                _badge(owner != null ? 'CONNECTED' : 'UNASSIGNED', owner != null ? AppColors.success : AppColors.warning),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: owner != null ? AppColors.success.withValues(alpha: 0.045) : AppColors.warning.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(14),
              ),
              child: owner != null
                  ? Row(
                      children: [
                        _avatar(owner, size: 42),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_displayName(owner), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.darkText)),
                              const SizedBox(height: 2),
                              Text(owner['email'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.subtitleText)),
                            ],
                          ),
                        ),
                        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                      ],
                    )
                  : const Row(
                      children: [
                        Icon(Icons.link_off_rounded, color: AppColors.warning, size: 21),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('No owner is currently linked. Open an owner account below to assign the hardware.', style: TextStyle(fontSize: 11, height: 1.4, color: AppColors.subtitleText)),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('User Management', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.darkText)),
              ),
              Text('${_filteredUsers.length} shown', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4))),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search name or email',
              hintStyle: TextStyle(fontSize: 11, color: AppColors.darkWith(0.35)),
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.darkWith(0.42)),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.darkWith(0.07))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.darkWith(0.07))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.55), width: 1.3)),
            ),
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: AppColors.darkWith(0.035), borderRadius: BorderRadius.circular(13)),
            child: Row(
              children: [
                _filterButton(0, 'All', Icons.people_alt_rounded),
                _filterButton(1, 'Owners', Icons.person_outline_rounded),
                _filterButton(2, 'Admins', Icons.admin_panel_settings_outlined),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(int value, String label, IconData icon) {
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
            boxShadow: active
                ? [BoxShadow(color: AppColors.dark.withValues(alpha: 0.05), blurRadius: 7, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? AppColors.primary : AppColors.darkWith(0.4)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? AppColors.primary : AppColors.darkWith(0.4))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final uid = user['uid'] as String;
    final role = (user['role'] as String? ?? 'owner').toLowerCase();
    final status = (user['status'] as String? ?? 'active').toLowerCase();
    final isAdmin = role == 'admin';
    final disabled = status == 'disabled';
    final linked = uid == _currentOwnerUid;
    final self = uid == FirebaseAuth.instance.currentUser?.uid;
    final accent = disabled ? AppColors.critical : (isAdmin ? AppColors.dark : AppColors.primary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => _openUserSheet(user),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(13, 13, 11, 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: linked ? AppColors.primary.withValues(alpha: 0.28) : AppColors.darkWith(0.07), width: linked ? 1.3 : 1),
          ),
          child: Row(
            children: [
              _avatar(user, size: 46, muted: disabled),
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
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w750, color: disabled ? AppColors.mutedText : AppColors.darkText),
                          ),
                        ),
                        if (self) ...[
                          const SizedBox(width: 6),
                          _badge('YOU', AppColors.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user['email'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: AppColors.darkWith(0.48)),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _badge(isAdmin ? 'ADMIN' : 'OWNER', accent),
                        _badge(disabled ? 'DISABLED' : 'ACTIVE', disabled ? AppColors.critical : AppColors.success),
                        if (linked) _badge('HARDWARE', AppColors.primary),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: AppColors.darkWith(0.22), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(Map<String, dynamic> user, {double size = 44, bool muted = false}) {
    final role = (user['role'] as String? ?? 'owner').toLowerCase();
    final color = role == 'admin' ? AppColors.dark : AppColors.primary;
    final image = _photoImageProvider((user['photo_url'] ?? user['photoUrl']) as String?);
    final words = _displayName(user).trim().split(RegExp(r'\s+'));
    final initials = words.where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: muted ? 0.05 : 0.1),
        borderRadius: BorderRadius.circular(size * 0.3),
        image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: image != null
          ? null
          : Text(initials.isEmpty ? '?' : initials, style: TextStyle(fontSize: size * 0.28, fontWeight: FontWeight.w800, color: muted ? AppColors.mutedText : color)),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(7)),
      child: Text(label, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.25)),
    );
  }

  Future<bool> _confirm(String title, String message, {Color? color, IconData? icon}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: (color ?? AppColors.primary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon ?? Icons.help_outline_rounded, color: color ?? AppColors.primary, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 12, height: 1.5, color: AppColors.subtitleText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color ?? AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _openUserSheet(Map<String, dynamic> user) {
    final uid = user['uid'] as String;
    final self = uid == FirebaseAuth.instance.currentUser?.uid;
    final role = (user['role'] as String? ?? 'owner').toLowerCase();
    final disabled = (user['status'] as String? ?? 'active').toLowerCase() == 'disabled';
    final linked = uid == _currentOwnerUid;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 36),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 18),
                _avatar(user, size: 62, muted: disabled),
                const SizedBox(height: 11),
                Text(_displayName(user), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.darkText)),
                const SizedBox(height: 3),
                Text(user['email'] as String? ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppColors.subtitleText)),
                const SizedBox(height: 9),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 7,
                  children: [
                    _badge(role == 'admin' ? 'ADMIN' : 'OWNER', role == 'admin' ? AppColors.dark : AppColors.primary),
                    _badge(disabled ? 'DISABLED' : 'ACTIVE', disabled ? AppColors.critical : AppColors.success),
                    if (linked) _badge('HARDWARE', AppColors.primary),
                  ],
                ),
                const SizedBox(height: 22),
                _sheetSectionTitle('Account', Icons.manage_accounts_rounded),
                const SizedBox(height: 8),
                _actionTile(
                  icon: disabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                  title: disabled ? 'Enable account' : 'Disable account',
                  subtitle: self ? 'Your own admin account cannot be disabled' : (disabled ? 'Allow this user to sign in again' : 'Block this user from signing in'),
                  color: disabled ? AppColors.success : AppColors.critical,
                  enabled: !self,
                  onTap: () async {
                    final enable = disabled;
                    final ok = await _confirm(
                      enable ? 'Enable account?' : 'Disable account?',
                      enable ? '${_displayName(user)} will be able to sign in again.' : '${_displayName(user)} will be blocked from signing in.',
                      color: enable ? AppColors.success : AppColors.critical,
                      icon: enable ? Icons.lock_open_rounded : Icons.lock_rounded,
                    );
                    if (!ok) return;
                    await DatabaseService.instance.setUserStatus(uid, enable ? 'active' : 'disabled');
                    if (!mounted) return;
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    showBeautifulSnackbar(context, enable ? 'Account enabled.' : 'Account disabled.', true);
                  },
                ),
                const SizedBox(height: 8),
                _actionTile(
                  icon: role == 'admin' ? Icons.person_rounded : Icons.admin_panel_settings_rounded,
                  title: role == 'admin' ? 'Change role to Owner' : 'Change role to Admin',
                  subtitle: self ? 'You cannot change your own role' : 'Update this account’s access level',
                  color: AppColors.primary,
                  enabled: !self,
                  onTap: () async {
                    final nextRole = role == 'admin' ? 'owner' : 'admin';
                    final ok = await _confirm(
                      'Change account role?',
                      'Change ${_displayName(user)} from ${role.toUpperCase()} to ${nextRole.toUpperCase()}?',
                      icon: Icons.swap_horiz_rounded,
                    );
                    if (!ok) return;
                    if (linked && nextRole == 'admin') {
                      await DatabaseService.instance.removeCurrentOwner();
                    }
                    await DatabaseService.instance.setUserRole(uid, nextRole);
                    if (!mounted) return;
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    showBeautifulSnackbar(context, 'Role updated to ${nextRole.toUpperCase()}.', true);
                  },
                ),
                if (role != 'admin') ...[
                  const SizedBox(height: 18),
                  _sheetSectionTitle('Hardware', Icons.developer_board_rounded),
                  const SizedBox(height: 8),
                  _actionTile(
                    icon: linked ? Icons.link_off_rounded : Icons.link_rounded,
                    title: linked ? 'Unlink hardware' : 'Assign hardware',
                    subtitle: linked ? 'Stop routing sensor data to this owner' : (_currentOwnerUid == null ? 'Route sensor data to this owner' : 'Reassign hardware from the current owner'),
                    color: linked ? AppColors.critical : AppColors.primary,
                    enabled: !disabled,
                    onTap: () async {
                      final ok = await _confirm(
                        linked ? 'Unlink hardware?' : 'Assign hardware?',
                        linked
                            ? 'The hardware will no longer be assigned to ${_displayName(user)}.'
                            : 'Sensor data and device access will route to ${_displayName(user)}.',
                        color: linked ? AppColors.critical : AppColors.primary,
                        icon: linked ? Icons.link_off_rounded : Icons.developer_board_rounded,
                      );
                      if (!ok) return;
                      if (linked) {
                        await DatabaseService.instance.removeCurrentOwner();
                      } else {
                        await DatabaseService.instance.setCurrentOwner(uid);
                      }
                      if (!mounted) return;
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      showBeautifulSnackbar(context, linked ? 'Hardware unlinked.' : 'Hardware assigned.', true);
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

  Widget _sheetSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 17),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.darkText)),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.48,
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
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.darkText)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 10.5, height: 1.35, color: AppColors.subtitleText)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.darkWith(0.22)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 60),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.person_search_rounded, color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: 13),
          const Text('No users found', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.darkText)),
          const SizedBox(height: 4),
          const Text('Try another search or filter.', style: TextStyle(fontSize: 11, color: AppColors.subtitleText)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.critical, size: 34),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.subtitleText)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
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
