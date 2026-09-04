import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/snackbar_helper.dart';

class ProfileEditForm extends StatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final Future<void> Function() onSave;
  final VoidCallback? onTapCamera; // Para pag pindot sa camera icon
  final ImageProvider<Object>? photoImage;

  const ProfileEditForm({
    super.key,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.onSave,
    this.onTapCamera,
    this.photoImage,
  });

  @override
  State<ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends State<ProfileEditForm> {
  bool _isSaving = false;

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave();
    } catch (e) {
      if (!mounted) return;
      showBeautifulSnackbar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        false,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoImage = widget.photoImage;

    return Container(
      color: Colors.white,
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
                      _isSaving ? null : widget.onTapCamera,
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
                _buildField('Full Name', widget.nameCtrl),
                const SizedBox(height: 16),
                _buildField(
                  'Email Address',
                  widget.emailCtrl,
                  enabled: false,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: Text(
                        _isSaving ? 'Saving…' : 'Save Changes',
                        key: ValueKey(_isSaving),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
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
