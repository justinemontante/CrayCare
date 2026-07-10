import 'dart:convert'; // Para ma-decode ang base64 image
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class SettingsMenu extends StatelessWidget {
  final String profileName;
  final String profileEmail;
  final String? photoUrl;
  final void Function(int page) onGoTo;
  final VoidCallback onLogout;

  const SettingsMenu({
    super.key,
    required this.profileName,
    required this.profileEmail,
    this.photoUrl,
    required this.onGoTo,
    required this.onLogout,
  });

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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFf7f7f7),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildProfileCard(),
            const SizedBox(height: 10),
            _buildMenuSection('Account', [
              _buildMenuItem(
                'Edit Profile',
                Icons.person,
                AppColors.primary,
                chevron: true,
                onTap: () => onGoTo(1),
              ),
              _buildMenuItem(
                'Change Password',
                Icons.lock,
                AppColors.primary,
                chevron: true,
                onTap: () => onGoTo(2),
              ),
            ]),
            const SizedBox(height: 10),
            _buildMenuSection('Preferences', [
              _buildMenuItem(
                'Notifications',
                Icons.notifications,
                AppColors.warning,
                chevron: true,
                onTap: () => onGoTo(3),
              ),
              _buildMenuItem(
                'Sensor Thresholds',
                Icons.tune_rounded,
                AppColors.primary,
                chevron: true,
                onTap: () => onGoTo(4),
              ),
            ]),
            const SizedBox(height: 10),
            _buildMenuItem(
              'Logout',
              Icons.logout,
              AppColors.critical,
              onTap: onLogout,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final photoImage = _photoImageProvider(photoUrl);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: AppColors.darkWith(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: photoImage == null ? AppColors.primary : null,
              shape: BoxShape.circle,
              image: photoImage != null
                  ? DecorationImage(image: photoImage, fit: BoxFit.cover)
                  : null,
            ),
            child: photoImage == null
                ? const Icon(Icons.person, color: Colors.white, size: 26)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profileName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  profileEmail,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.darkWith(0.5),
                  ),
                ),
              ],
            ),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.darkWith(0.4),
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...items,
      ],
    );
  }

  Widget _buildMenuItem(
    String label,
    IconData icon,
    Color color, {
    bool chevron = false,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.04)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: label == 'Logout'
                          ? AppColors.critical
                          : AppColors.dark,
                    ),
                  ),
                ),
                if (chevron)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.darkWith(0.2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
