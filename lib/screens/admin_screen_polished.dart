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
  final _search = TextEditingController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _ownerSub;
  List<Map<String, dynamic>> _users = [];
  String? _ownerUid;
  String _query = '';
  int _filter = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
  }

  @override
  void dispose() {
    _search.dispose();
    _usersSub?.cancel();
    _ownerSub?.cancel();
    super.dispose();
  }

  void _listen() {
    _usersSub = FirebaseFirestore.instance.collection('users').snapshots().listen(
      (snap) {
        final users = snap.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          data['uid'] = d.id;
          return data;
        }).toList();
        if (!mounted) return;
        setState(() {
          _users = users;
          _loading = false;
          _error = null;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Unable to load users.';
        });
      },
    );
    _ownerSub = DatabaseService.instance.streamCurrentOwner().listen((doc) {
      if (!mounted) return;
      setState(() => _ownerUid = doc.data()?['uid'] as String?);
    });
  }

  Future<void> _load() async {
    try {
      final users = await DatabaseService.instance.getAllUsers();
      final owner = await DatabaseService.instance.getCurrentOwnerUid();
      if (!mounted) return;
      setState(() {
        _users = users;
        _ownerUid = owner;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load admin data.';
      });
    }
  }

  String _name(Map<String, dynamic> u) =>
      (u['full_name'] as String?) ??
      (u['fullName'] as String?) ??
      (u['displayName'] as String?) ??
      (u['email'] as String?) ??
      'User';

  List<Map<String, dynamic>> get _visibleUsers {
    final self = FirebaseAuth.instance.currentUser?.uid;
    final q = _query.trim().toLowerCase();
    final list = _users.where((u) {
      final role = (u['role'] as String? ?? 'owner').toLowerCase();
      if (_filter == 1 && role != 'owner') return false;
      if (_filter == 2 && role != 'admin') return false;
      if (q.isEmpty) return true;
      return _name(u).toLowerCase().contains(q) ||
          (u['email'] as String? ?? '').toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      final sa = a['uid'] == self ? 0 : 1;
      final sb = b['uid'] == self ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
      return _name(a).toLowerCase().compareTo(_name(b).toLowerCase());
    });
    return list;
  }

  Map<String, dynamic>? get _hardwareOwner {
    for (final u in _users) {
      if (u['uid'] == _ownerUid) return u;
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
            _header(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (_error != null)
              _errorCard()
            else ...[
              _stats(),
              const SizedBox(height: 12),
              _hardwareCard(),
              const SizedBox(height: 18),
              _usersHeader(),
              const SizedBox(height: 10),
              _searchBox(),
              const SizedBox(height: 9),
              _filters(),
              const SizedBox(height: 10),
              if (_visibleUsers.isEmpty)
                _empty()
              else
                ..._visibleUsers.map((u) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _userCard(u),
                    )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
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
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: AppColors.primary, size: 25),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin Center',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkText)),
                  SizedBox(height: 4),
                  Text('Accounts, roles and hardware access',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.subtitleText)),
                ],
              ),
            ),
            _pill('LIVE', AppColors.success, dot: true),
          ],
        ),
      );

  Widget _stats() {
    final owners = _users.where((u) => (u['role'] ?? 'owner') == 'owner').length;
    final admins = _users.where((u) => (u['role'] ?? 'owner') == 'admin').length;
    final disabled = _users.where((u) => (u['status'] ?? 'active') == 'disabled').length;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(width: w, child: _stat('Total users', '${_users.length}', Icons.groups_rounded, AppColors.primary)),
          SizedBox(width: w, child: _stat('Owners', '$owners', Icons.person_rounded, AppColors.success)),
          SizedBox(width: w, child: _stat('Admins', '$admins', Icons.admin_panel_settings_rounded, AppColors.dark)),
          SizedBox(width: w, child: _stat('Disabled', '$disabled', Icons.person_off_rounded, AppColors.critical)),
        ],
      );
    });
  }

  Widget _stat(String label, String value, IconData icon, Color color) => Container(
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
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: color,
                          height: 1)),
                  const SizedBox(height: 5),
                  Text(label,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkWith(0.48))),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _hardwareCard() {
    final owner = _hardwareOwner;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: (owner == null ? AppColors.warning : AppColors.success)
                .withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.developer_board_rounded,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hardware Assignment',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkText)),
                  SizedBox(height: 2),
                  Text('Owner currently receiving device data',
                      style: TextStyle(
                          fontSize: 10.5, color: AppColors.subtitleText)),
                ],
              ),
            ),
            _pill(owner == null ? 'UNASSIGNED' : 'CONNECTED',
                owner == null ? AppColors.warning : AppColors.success),
          ]),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (owner == null ? AppColors.warning : AppColors.success)
                  .withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(14),
            ),
            child: owner == null
                ? const Row(children: [
                    Icon(Icons.link_off_rounded,
                        size: 20, color: AppColors.warning),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          'No hardware owner. Tap an owner below to assign the device.',
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: AppColors.subtitleText)),
                    ),
                  ])
                : Row(children: [
                    _avatar(owner, 42),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_name(owner),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkText)),
                          const SizedBox(height: 2),
                          Text(owner['email'] as String? ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.subtitleText)),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle_rounded,
                        size: 20, color: AppColors.success),
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _usersHeader() => Row(children: [
        const Expanded(
          child: Text('User Management',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkText)),
        ),
        Text('${_visibleUsers.length} shown',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.darkWith(0.4))),
      ]);

  Widget _searchBox() => TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: 'Search name or email',
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: AppColors.darkWith(0.4)),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.close_rounded, size: 18)),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.darkWith(0.07))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.55), width: 1.3)),
        ),
      );

  Widget _filters() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: AppColors.darkWith(0.035),
            borderRadius: BorderRadius.circular(13)),
        child: Row(children: [
          _filterButton(0, 'All', Icons.people_alt_rounded),
          _filterButton(1, 'Owners', Icons.person_outline_rounded),
          _filterButton(2, 'Admins', Icons.admin_panel_settings_outlined),
        ]),
      );

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
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 15,
                color: active
                    ? AppColors.primary
                    : AppColors.darkWith(0.4)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? AppColors.primary
                        : AppColors.darkWith(0.4))),
          ]),
        ),
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> u) {
    final uid = u['uid'] as String;
    final role = (u['role'] as String? ?? 'owner').toLowerCase();
    final disabled = (u['status'] as String? ?? 'active') == 'disabled';
    final linked = uid == _ownerUid;
    final self = uid == FirebaseAuth.instance.currentUser?.uid;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => _openUser(u),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
                color: linked
                    ? AppColors.primary.withValues(alpha: 0.28)
                    : AppColors.darkWith(0.07)),
          ),
          child: Row(children: [
            _avatar(u, 46, muted: disabled),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(_name(u),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: disabled
                                  ? AppColors.mutedText
                                  : AppColors.darkText)),
                    ),
                    if (self) ...[
                      const SizedBox(width: 6),
                      _pill('YOU', AppColors.primary),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(u['email'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.darkWith(0.48))),
                  const SizedBox(height: 7),
                  Wrap(spacing: 6, runSpacing: 5, children: [
                    _pill(role == 'admin' ? 'ADMIN' : 'OWNER',
                        role == 'admin' ? AppColors.dark : AppColors.primary),
                    _pill(disabled ? 'DISABLED' : 'ACTIVE',
                        disabled ? AppColors.critical : AppColors.success),
                    if (linked) _pill('HARDWARE', AppColors.primary),
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 22, color: AppColors.darkWith(0.22)),
          ]),
        ),
      ),
    );
  }

  void _openUser(Map<String, dynamic> u) {
    final uid = u['uid'] as String;
    final role = (u['role'] as String? ?? 'owner').toLowerCase();
    final disabled = (u['status'] as String? ?? 'active') == 'disabled';
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 18),
              _avatar(u, 62, muted: disabled),
              const SizedBox(height: 10),
              Text(_name(u),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkText)),
              const SizedBox(height: 3),
              Text(u['email'] as String? ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.subtitleText)),
              const SizedBox(height: 18),
              _action(
                disabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                disabled ? 'Enable account' : 'Disable account',
                self
                    ? 'Your own admin account cannot be disabled'
                    : disabled
                        ? 'Allow this user to sign in again'
                        : 'Block this user from signing in',
                disabled ? AppColors.success : AppColors.critical,
                enabled: !self,
                onTap: () async {
                  final ok = await _confirm(
                      disabled ? 'Enable account?' : 'Disable account?',
                      disabled
                          ? '${_name(u)} will be able to sign in again.'
                          : '${_name(u)} will be blocked from signing in.');
                  if (!ok) return;
                  await DatabaseService.instance
                      .setUserStatus(uid, disabled ? 'active' : 'disabled');
                  if (!mounted) return;
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  showBeautifulSnackbar(context,
                      disabled ? 'Account enabled.' : 'Account disabled.', true);
                },
              ),
              const SizedBox(height: 8),
              _action(
                Icons.swap_horiz_rounded,
                role == 'admin' ? 'Change role to Owner' : 'Change role to Admin',
                self ? 'You cannot change your own role' : 'Update account access level',
                AppColors.primary,
                enabled: !self,
                onTap: () async {
                  final next = role == 'admin' ? 'owner' : 'admin';
                  final ok = await _confirm('Change account role?',
                      'Change ${_name(u)} to ${next.toUpperCase()}?');
                  if (!ok) return;
                  if (linked && next == 'admin') {
                    await DatabaseService.instance.removeCurrentOwner();
                  }
                  await DatabaseService.instance.setUserRole(uid, next);
                  if (!mounted) return;
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  showBeautifulSnackbar(
                      context, 'Role updated to ${next.toUpperCase()}.', true);
                },
              ),
              if (role != 'admin') ...[
                const SizedBox(height: 8),
                _action(
                  linked ? Icons.link_off_rounded : Icons.link_rounded,
                  linked ? 'Unlink hardware' : 'Assign hardware',
                  linked
                      ? 'Stop routing device data to this owner'
                      : 'Route sensor data and device access to this owner',
                  linked ? AppColors.critical : AppColors.primary,
                  enabled: !disabled,
                  onTap: () async {
                    final ok = await _confirm(
                        linked ? 'Unlink hardware?' : 'Assign hardware?',
                        linked
                            ? 'Remove hardware assignment from ${_name(u)}?'
                            : 'Assign hardware to ${_name(u)}?');
                    if (!ok) return;
                    if (linked) {
                      await DatabaseService.instance.removeCurrentOwner();
                    } else {
                      await DatabaseService.instance.setCurrentOwner(uid);
                    }
                    if (!mounted) return;
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    showBeautifulSnackbar(context,
                        linked ? 'Hardware unlinked.' : 'Hardware assigned.', true);
                  },
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String title, String subtitle, Color color,
      {required VoidCallback onTap, bool enabled = true}) => Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: color.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkText)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 10.5,
                              height: 1.35,
                              color: AppColors.subtitleText)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.darkWith(0.22)),
              ]),
            ),
          ),
        ),
      );

  Future<bool> _confirm(String title, String message) async =>
      (await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: Text(message,
              style: const TextStyle(
                  fontSize: 12, height: 1.5, color: AppColors.subtitleText)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm')),
          ],
        ),
      )) ==
      true;

  Widget _avatar(Map<String, dynamic> u, double size, {bool muted = false}) {
    final role = (u['role'] as String? ?? 'owner').toLowerCase();
    final color = role == 'admin' ? AppColors.dark : AppColors.primary;
    final image = _photo((u['photo_url'] ?? u['photoUrl']) as String?);
    final initials = _name(u)
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0])
        .join()
        .toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: muted ? 0.05 : 0.1),
        borderRadius: BorderRadius.circular(size * 0.3),
        image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      child: image == null
          ? Text(initials.isEmpty ? '?' : initials,
              style: TextStyle(
                  fontSize: size * 0.27,
                  fontWeight: FontWeight.w800,
                  color: muted ? AppColors.mutedText : color))
          : null,
    );
  }

  ImageProvider<Object>? _photo(String? value) {
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

  Widget _pill(String label, Color color, {bool dot = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(7)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Icon(Icons.circle, size: 6, color: color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.2)),
        ]),
      );

  Widget _empty() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          Icon(Icons.person_search_rounded, size: 34, color: AppColors.primary),
          SizedBox(height: 10),
          Text('No users found',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText)),
          SizedBox(height: 3),
          Text('Try another search or filter.',
              style: TextStyle(fontSize: 11, color: AppColors.subtitleText)),
        ]),
      );

  Widget _errorCard() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          const Icon(Icons.cloud_off_rounded,
              size: 34, color: AppColors.critical),
          const SizedBox(height: 10),
          Text(_error!,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.subtitleText)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
}
