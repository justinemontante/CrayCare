import 'dart:convert';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class SettingsMenu extends StatelessWidget {
  final String profileName;
  final String profileEmail;
  final String? photoUrl;
  final bool isAdmin;
  final void Function(int page) onGoTo;
  final VoidCallback onLogout;

  const SettingsMenu({
    super.key,
    required this.profileName,
    required this.profileEmail,
    this.photoUrl,
    this.isAdmin = false,
    required this.onGoTo,
    required this.onLogout,
  });

  ImageProvider<Object>? _photoImageProvider(String? value) {
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

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7FAFA),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileCard(),
            const SizedBox(height: 24),
            _buildSectionLabel(Icons.person_outline_rounded, 'ACCOUNT'),
            const SizedBox(height: 10),
            _buildGroupedCard([
              _SettingsItem(
                label: 'Edit Profile',
                subtitle: 'Update your personal information',
                icon: Icons.person_outline_rounded,
                color: AppColors.primary,
                onTap: () => onGoTo(1),
              ),
              _SettingsItem(
                label: 'Change Password',
                subtitle: 'Update your password for security',
                icon: Icons.lock_outline_rounded,
                color: AppColors.primary,
                onTap: () => onGoTo(2),
              ),
            ]),
            const SizedBox(height: 24),
            _buildSectionLabel(Icons.notifications_none_rounded, 'PREFERENCES'),
            const SizedBox(height: 10),
            _buildSingleCard(
              _SettingsItem(
                label: 'Notifications',
                subtitle: 'Manage your notification preferences',
                icon: Icons.notifications_rounded,
                color: AppColors.warning,
                onTap: () => onGoTo(3),
              ),
            ),
            if (!isAdmin) ...[
              const SizedBox(height: 10),
              _buildSingleCard(
                _SettingsItem(
                  label: 'Sensor Thresholds',
                  subtitle: 'Set safe ranges for water conditions',
                  icon: Icons.tune_rounded,
                  color: AppColors.primary,
                  onTap: () => onGoTo(4),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _buildSingleCard(
              _SettingsItem(
                label: 'Logout',
                subtitle: 'Sign out from your account',
                icon: Icons.logout_rounded,
                color: AppColors.critical,
                onTap: onLogout,
              ),
              borderColor: AppColors.critical.withValues(alpha: 0.08),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final photoImage = _photoImageProvider(photoUrl);
    return Container(
      height: 104,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.darkWith(0.06)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onGoTo(1),
          child: Stack(
            children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: photoImage == null ? AppColors.primary : null,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      image: photoImage == null
                          ? null
                          : DecorationImage(image: photoImage, fit: BoxFit.cover),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: photoImage == null
                        ? const Icon(Icons.person_rounded, color: Colors.white, size: 29)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              profileEmail,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 11, color: AppColors.subtitleText),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 21),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: 0.35,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: AppColors.primary.withValues(alpha: 0.14))),
      ],
    );
  }

  Widget _buildGroupedCard(List<_SettingsItem> items) {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: List.generate(items.length, (index) {
          return Column(
            children: [
              _buildMenuRow(items[index]),
              if (index < items.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 68, right: 16),
                  child: Divider(height: 1, thickness: 1, color: AppColors.darkWith(0.06)),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSingleCard(_SettingsItem item, {Color? borderColor}) {
    return Container(
      decoration: _cardDecoration(borderColor: borderColor),
      child: _buildMenuRow(item),
    );
  }

  BoxDecoration _cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: borderColor ?? AppColors.darkWith(0.05)),
      boxShadow: [
        BoxShadow(
          color: AppColors.darkWith(0.045),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildMenuRow(_SettingsItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(item.icon, size: 21, color: item.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: item.color == AppColors.critical ? AppColors.critical : AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.subtitleText),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 21, color: item.color.withValues(alpha: 0.85)),
            ],
          ),
        ),
      ),
    );
  }

}

class _SettingsItem {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
