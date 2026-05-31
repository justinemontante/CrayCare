import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ChangePasswordForm extends StatefulWidget {
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
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  bool _currentVisible = false;
  bool _newVisible = false;
  bool _confirmVisible = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFf7f7f7),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
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
                _buildField(
                  'Current Password',
                  widget.currentPwCtrl,
                  obscure: !_currentVisible,
                  onToggle: () => setState(() => _currentVisible = !_currentVisible),
                  visible: _currentVisible,
                ),
                const SizedBox(height: 16),
                _buildField(
                  'New Password',
                  widget.newPwCtrl,
                  obscure: !_newVisible,
                  onToggle: () => setState(() => _newVisible = !_newVisible),
                  visible: _newVisible,
                ),
                const SizedBox(height: 16),
                _buildField(
                  'Confirm New Password',
                  widget.confirmPwCtrl,
                  obscure: !_confirmVisible,
                  onToggle: () => setState(() => _confirmVisible = !_confirmVisible),
                  visible: _confirmVisible,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onChangePassword,
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
    ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    required bool obscure,
    required VoidCallback onToggle,
    required bool visible,
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
            suffixIcon: IconButton(
              onPressed: onToggle,
              icon: Icon(
                visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                size: 18,
                color: AppColors.darkWith(0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
