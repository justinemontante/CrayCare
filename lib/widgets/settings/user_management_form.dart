import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../theme/app_colors.dart';
import '../../services/database_service.dart';

class UserManagementForm extends StatefulWidget {
  const UserManagementForm({super.key});

  @override
  State<UserManagementForm> createState() => _UserManagementFormState();
}

class _UserManagementFormState extends State<UserManagementForm>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterRole = 'all'; // 'all', 'admin', 'owner', 'monitor'

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Container(
      color: const Color(0xFFF5F6FA),
      child: StreamBuilder<DatabaseEvent>(
        stream: DatabaseService.instance.getAllUsersStream(),
        builder: (context, snapshot) {
          // Parse users list from snapshot for stats and list
          final usersList = <MapEntry<String, Map<String, dynamic>>>[];
          if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
            final rawUsers = snapshot.data!.snapshot.value as Map;
            rawUsers.forEach((key, val) {
              if (val is Map && val['profile'] != null) {
                final profile = val['profile'] as Map;
                final converted = profile.map<String, dynamic>(
                  (k, v) => MapEntry(k.toString(), v),
                );
                usersList.add(MapEntry(key.toString(), converted));
              }
            });
          }

          // Compute stats
          final int totalUsers = usersList.length;
          final int activeUsers = usersList
              .where((e) => (e.value['status'] ?? 'active') != 'disabled')
              .length;
          final int disabledUsers = totalUsers - activeUsers;
          final int ownerCount =
              usersList.where((e) => e.value['role'] == 'owner').length;
          final int monitorCount =
              usersList.where((e) => (e.value['role'] ?? 'monitor') == 'monitor').length;

          // Filter users
          final filteredUsers = usersList.where((entry) {
            final name =
                (entry.value['displayName'] ?? '').toString().toLowerCase();
            final email =
                (entry.value['email'] ?? '').toString().toLowerCase();
            final role = (entry.value['role'] ?? 'monitor').toString();
            final matchesSearch =
                name.contains(_searchQuery) || email.contains(_searchQuery);
            final matchesFilter =
                _filterRole == 'all' || role == _filterRole;
            return matchesSearch && matchesFilter;
          }).toList();

          return FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                // Stats Cards
                _buildStatsHeader(
                  total: totalUsers,
                  active: activeUsers,
                  disabled: disabledUsers,
                  owners: ownerCount,
                  monitors: monitorCount,
                ),

                // Search Bar + Filters
                _buildSearchAndFilters(),

                // Users List
                Expanded(
                  child: _buildUsersList(
                    snapshot: snapshot,
                    filteredUsers: filteredUsers,
                    currentUid: currentUid,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // DYNAMIC GREETING
  String _getGreetingTime() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final weekdays = [
      'Sunday', 'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday',
    ];
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final weekday = weekdays[now.weekday % 7];
    final month = months[now.month - 1];
    return '$weekday, $month ${now.day}, ${now.year}';
  }

  Widget _buildStatsHeader({
    required int total,
    required int active,
    required int disabled,
    required int owners,
    required int monitors,
  }) {
    return Column(
      children: [
        // Greeting Card (matching dashboard design)
        Container(
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
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
          child: Stack(
            children: [
              Container(
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
                  borderRadius: BorderRadius.all(Radius.circular(16)),
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
                            '${_getGreetingTime()}, Admin',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _getFormattedDate(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                              color: AppColors.darkWith(0.4),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Manage your team accounts and permissions.',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.darkWith(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 190,
                child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                  child: Image.asset(
                    'assets/images/seaweedImage.png',
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomRight,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Compact Stats Row
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(
            children: [
              _buildMiniStat(
                icon: Icons.people_rounded,
                label: 'Total',
                count: total,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              _buildMiniStat(
                icon: Icons.check_circle_outline,
                label: 'Active',
                count: active,
                color: const Color(0xFF16a34a),
              ),
              const SizedBox(width: 6),
              _buildMiniStat(
                icon: Icons.block,
                label: 'Disabled',
                count: disabled,
                color: const Color(0xFFef4444),
              ),
              const SizedBox(width: 6),
              _buildMiniStat(
                icon: Icons.shield_outlined,
                label: 'Owners',
                count: owners,
                color: const Color(0xFF2563eb),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkWith(0.04)),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkWith(0.02),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 3),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: AppColors.darkWith(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            onChanged: (val) {
              setState(() => _searchQuery = val.trim().toLowerCase());
            },
            decoration: InputDecoration(
              hintText: 'Search by name or email...',
              hintStyle: TextStyle(
                fontSize: 13,
                color: AppColors.darkWith(0.3),
              ),
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.primary, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.darkWith(0.06)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 6),
                _buildFilterChip('Admins', 'admin'),
                const SizedBox(width: 6),
                _buildFilterChip('Owners', 'owner'),
                const SizedBox(width: 6),
                _buildFilterChip('Monitors', 'monitor'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isActive = _filterRole == value;
    return GestureDetector(
      onTap: () => setState(() => _filterRole = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.darkWith(0.08),
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isActive ? Colors.white : AppColors.darkWith(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildUsersList({
    required AsyncSnapshot<DatabaseEvent> snapshot,
    required List<MapEntry<String, Map<String, dynamic>>> filteredUsers,
    required String? currentUid,
  }) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              'Error loading users',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.darkWith(0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${snapshot.error}',
              style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.4)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 48, color: AppColors.darkWith(0.15)),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching users found'
                  : 'No users in this category',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.darkWith(0.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      itemCount: filteredUsers.length,
      itemBuilder: (context, idx) {
        final userEntry = filteredUsers[idx];
        final uid = userEntry.key;
        final profile = userEntry.value;

        final String name = profile['displayName'] ?? 'CrayCare User';
        final String email = profile['email'] ?? 'No email';
        final String role = profile['role'] ?? 'monitor';
        final String status = profile['status'] ?? 'active';
        final String? photoUrl = profile['photoUrl'] as String?;
        final bool isSelf = uid == currentUid;

        return _buildUserTile(
          uid: uid,
          name: name,
          email: email,
          role: role,
          status: status,
          photoUrl: photoUrl,
          isSelf: isSelf,
          index: idx,
        );
      },
    );
  }

  Widget _buildUserTile({
    required String uid,
    required String name,
    required String email,
    required String role,
    required String status,
    required String? photoUrl,
    required bool isSelf,
    required int index,
  }) {
    final bool isDisabled = status == 'disabled';

    Color roleBgColor;
    Color roleTextColor;
    IconData roleIcon;
    switch (role) {
      case 'admin':
        roleBgColor = const Color(0xFFfee2e2);
        roleTextColor = const Color(0xFFef4444);
        roleIcon = Icons.shield_rounded;
        break;
      case 'owner':
        roleBgColor = const Color(0xFFdbeafe);
        roleTextColor = const Color(0xFF2563eb);
        roleIcon = Icons.shield_outlined;
        break;
      default:
        roleBgColor = const Color(0xFFe2fbf0); // Light green-teal
        roleTextColor = const Color(0xFF10b981); // Emerald green
        roleIcon = Icons.visibility_rounded;
    }

    // Initials avatar color (derived from name hash)
    final avatarColors = [
      const Color(0xFF0D9488),
      const Color(0xFF7C3AED),
      const Color(0xFFDB2777),
      const Color(0xFFEA580C),
      const Color(0xFF2563EB),
      const Color(0xFF059669),
    ];
    final colorIdx = name.hashCode.abs() % avatarColors.length;
    final avatarColor = isDisabled ? Colors.grey.shade400 : avatarColors[colorIdx];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50).clamp(0, 300)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isDisabled ? const Color(0xFFFAFAFA) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDisabled ? Colors.grey.shade200 : AppColors.darkWith(0.04),
          ),
          boxShadow: [
            if (!isDisabled)
              BoxShadow(
                color: AppColors.darkWith(0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () =>
                _showUserActionSheet(uid, name, email, role, status, isSelf),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: avatarColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: avatarColor.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: photoUrl != null && photoUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(21),
                            child: Image.network(
                              photoUrl,
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: avatarColor,
                                  ),
                                );
                              },
                            ),
                          )
                        : Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: avatarColor,
                            ),
                          ),
                  ),
                  const SizedBox(width: 14),

                  // Info
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: isDisabled
                                      ? Colors.grey.shade400
                                      : AppColors.dark,
                                  decoration: isDisabled
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSelf) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE2F9F6), // Light teal
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'YOU',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0D9488), // Teal
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.darkWith(0.35),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        if (isDisabled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFfef2f2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.block,
                                    size: 9, color: Color(0xFFef4444)),
                                SizedBox(width: 4),
                                Text(
                                  'ACCOUNT DISABLED',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFef4444),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: roleBgColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  roleIcon,
                                  size: 9,
                                  color: roleTextColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  role.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: roleTextColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.darkWith(0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showUserActionSheet(
    String targetUid,
    String targetName,
    String targetEmail,
    String currentRole,
    String currentStatus,
    bool isSelf,
  ) {
    if (isSelf) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('You cannot modify your own account.'),
            ],
          ),
          backgroundColor: AppColors.dark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    String selectedRole = currentRole;
    String selectedStatus = currentStatus;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final bool isDisabled = selectedStatus == 'disabled';
            final bool hasChanges =
                selectedRole != currentRole || selectedStatus != currentStatus;

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Pull indicator
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // User Info Header
                  Row(
                    children: [
                      Builder(
                        builder: (context) {
                          final avatarColors = [
                            const Color(0xFF0D9488),
                            const Color(0xFF7C3AED),
                            const Color(0xFFDB2777),
                            const Color(0xFFEA580C),
                            const Color(0xFF2563EB),
                            const Color(0xFF059669),
                          ];
                          final colorIdx = targetName.hashCode.abs() % avatarColors.length;
                          final avatarColor = avatarColors[colorIdx];
                          return Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: avatarColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: avatarColor.withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              targetName.isNotEmpty ? targetName[0].toUpperCase() : 'U',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: avatarColor,
                              ),
                            ),
                          );
                        }
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              targetName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.dark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              targetEmail,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.darkWith(0.4),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Divider(color: AppColors.darkWith(0.06), height: 1),
                  const SizedBox(height: 20),

                  // Role Selector
                  const Text(
                    'Assign Role',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A), // Dark navy
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildRoleOption(
                        label: 'Monitor',
                        subtitle: 'View only',
                        icon: Icons.visibility_rounded,
                        color: const Color(0xFF10b981), // Green
                        bgColor: const Color(0xFFe2fbf0),
                        isSelected: selectedRole == 'monitor',
                        onTap: () =>
                            setSheetState(() => selectedRole = 'monitor'),
                      ),
                      const SizedBox(width: 8),
                      _buildRoleOption(
                        label: 'Owner',
                        subtitle: 'Full control',
                        icon: Icons.shield_rounded,
                        color: const Color(0xFF2563eb), // Blue
                        bgColor: const Color(0xFFdbeafe),
                        isSelected: selectedRole == 'owner',
                        onTap: () =>
                            setSheetState(() => selectedRole = 'owner'),
                      ),
                      const SizedBox(width: 8),
                      _buildRoleOption(
                        label: 'Admin',
                        subtitle: 'Manage users',
                        icon: Icons.admin_panel_settings_rounded,
                        color: const Color(0xFFef4444), // Red
                        bgColor: const Color(0xFFfee2e2),
                        isSelected: selectedRole == 'admin',
                        onTap: () =>
                            setSheetState(() => selectedRole = 'admin'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Status Toggle
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDisabled
                          ? const Color(0xFFfef2f2)
                          : const Color(0xFFf0fdf4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDisabled
                            ? const Color(0xFFfecaca)
                            : const Color(0xFFbbf7d0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDisabled
                              ? Icons.block
                              : Icons.check_circle_rounded,
                          size: 20,
                          color: isDisabled
                              ? const Color(0xFFef4444)
                              : const Color(0xFF16a34a),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account Status',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDisabled
                                      ? const Color(0xFFef4444)
                                      : const Color(0xFF16a34a),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isDisabled
                                    ? 'User cannot sign-in'
                                    : 'User is active',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.darkWith(0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: !isDisabled,
                          activeTrackColor: const Color(0xFF10b981),
                          activeThumbColor: Colors.white,
                          inactiveTrackColor: const Color(0xFFe5e7eb),
                          inactiveThumbColor: Colors.white,
                          onChanged: (active) {
                            setSheetState(() {
                              selectedStatus =
                                  active ? 'active' : 'disabled';
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Save Button
                  ElevatedButton(
                    onPressed: hasChanges
                        ? () => _confirmSave(
                              ctx: ctx,
                              targetUid: targetUid,
                              targetName: targetName,
                              selectedRole: selectedRole,
                              selectedStatus: selectedStatus,
                              currentRole: currentRole,
                              currentStatus: currentStatus,
                            )
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFf3f4f6),
                      disabledForegroundColor: const Color(0xFF9ca3af),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.save_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          hasChanges
                              ? 'Save Changes'
                              : 'No Changes Made',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRoleOption({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isSelected ? bgColor : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? color : const Color(0xFFE5E7EB),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: isSelected ? color : const Color(0xFF6B7280),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? color : const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? color.withValues(alpha: 0.8) : const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmSave({
    required BuildContext ctx,
    required String targetUid,
    required String targetName,
    required String selectedRole,
    required String selectedStatus,
    required String currentRole,
    required String currentStatus,
  }) {
    // Build change description
    final changes = <String>[];
    if (selectedRole != currentRole) {
      changes.add('Role: ${currentRole.toUpperCase()} → ${selectedRole.toUpperCase()}');
    }
    if (selectedStatus != currentStatus) {
      changes.add('Status: ${currentStatus.toUpperCase()} → ${selectedStatus.toUpperCase()}');
    }

    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFf59e0b), size: 22),
            SizedBox(width: 8),
            Text(
              'Confirm Changes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apply the following changes to $targetName?',
              style: TextStyle(fontSize: 13, color: AppColors.darkWith(0.6)),
            ),
            const SizedBox(height: 14),
            ...changes.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_forward_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (selectedStatus == 'disabled')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFfef2f2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, size: 14, color: Color(0xFFef4444)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'This user will be signed out immediately.',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFFef4444),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.darkWith(0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx); // close dialog
              Navigator.pop(ctx); // close bottom sheet
              try {
                await DatabaseService.instance.updateUserRoleAndStatus(
                  uid: targetUid,
                  role: selectedRole,
                  status: selectedStatus,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Updated permissions for $targetName',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF16a34a),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Failed to update: $e',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(88, 38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Confirm',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
