import 'dart:convert'; // Para ma-decode ang base64 image
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ProfileEditForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final VoidCallback onSave;
  final VoidCallback? onTapCamera; // Para pag pindot sa camera icon
  final String? photoUrl; // URL ng profile picture para sa preview

  const ProfileEditForm({
    super.key,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.onSave,
    this.onTapCamera,
    this.photoUrl,
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
    final photoImage = _photoImageProvider(photoUrl);

    return Container(
      color: const Color(0xFFf7f7f7),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkWith(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: AppColors.darkWith(0.05)),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap:
                      onTapCamera, // Clickable na — pindutin para magpalit ng picture
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: photoImage == null
                              ? AppColors.primaryWith(0.1)
                              : null,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primaryWith(0.2),
                            width: 2,
                          ),
                          image: photoImage != null
                              ? DecorationImage(
                                  image: photoImage,
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: photoImage == null
                            ? const Icon(
                                Icons.person,
                                color: AppColors.primary,
                                size: 40,
                              )
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildField('Full Name', nameCtrl),
                const SizedBox(height: 16),
                _buildField('Email Address', emailCtrl, enabled: false),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.darkWith(0.6),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          enabled: enabled,
          style: TextStyle(
            fontSize: 13,
            color: enabled
                ? AppColors.dark
                : AppColors.dark.withValues(alpha: 0.5),
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: enabled
                ? AppColors.darkWith(0.04)
                : AppColors.darkWith(0.02),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.darkWith(0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.darkWith(0.12)),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.darkWith(0.06)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.primaryWith(0.5)),
            ),
          ),
        ),
      ],
    );
  }
}
