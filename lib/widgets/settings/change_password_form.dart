import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ChangePasswordForm extends StatelessWidget {
  final TextEditingController currentPwCtrl;
  final TextEditingController newPwCtrl;
  final TextEditingController confirmPwCtrl;
  final VoidCallback onChangePassword;

  const ChangePasswordForm({
    super.key,
    required this.currentPwCtrl,
    required this.newPwCtrl,
    required this.confirmPwCtrl,
    required this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your password must be at least 8 characters long.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.dark,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                _buildField('Current Password', currentPwCtrl, obscure: true),
                const SizedBox(height: 16),
                _buildField('New Password', newPwCtrl, obscure: true),
                const SizedBox(height: 16),
                _buildField(
                  'Confirm New Password',
                  confirmPwCtrl,
                  obscure: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onChangePassword,
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
                      'Update Password',
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
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.dark,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.darkWith(0.04),
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
