import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ChangePasswordForm extends StatefulWidget {
  final TextEditingController currentPwCtrl;
  final TextEditingController newPwCtrl;
  final TextEditingController confirmPwCtrl;
  final Future<void> Function() onChangePassword;
  final bool isCreatingPassword;

  const ChangePasswordForm({
    super.key,
    required this.currentPwCtrl,
    required this.newPwCtrl,
    required this.confirmPwCtrl,
    required this.onChangePassword,
    this.isCreatingPassword = false,
  });

  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  bool _currentVisible = false;
  bool _newVisible = false;
  bool _confirmVisible = false;
  bool _isSubmitting = false;
  String? _currentPwError;

  @override
  void initState() {
    super.initState();
    widget.currentPwCtrl.addListener(_clearError);
    widget.newPwCtrl.addListener(_clearError);
    widget.confirmPwCtrl.addListener(_clearError);
  }

  @override
  void dispose() {
    widget.currentPwCtrl.removeListener(_clearError);
    widget.newPwCtrl.removeListener(_clearError);
    widget.confirmPwCtrl.removeListener(_clearError);
    super.dispose();
  }

  void _clearError() {
    if (_currentPwError != null) {
      setState(() => _currentPwError = null);
    }
  }

  Future<void> _onSubmit() async {
    final currentPw = widget.currentPwCtrl.text;
    final newPw = widget.newPwCtrl.text;
    final confirmPw = widget.confirmPwCtrl.text;

    if ((!widget.isCreatingPassword && currentPw.isEmpty) ||
        newPw.isEmpty ||
        confirmPw.isEmpty) {
      setState(() => _currentPwError = 'Please fill in all fields.');
      return;
    }

    if (newPw != confirmPw) {
      setState(() => _currentPwError = 'New passwords do not match.');
      return;
    }

    if (newPw.length < 8) {
      setState(() => _currentPwError = 'Password must be at least 8 characters.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.onChangePassword();
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('incorrect') ||
          msg.contains('wrong-password') ||
          msg.contains('invalid-credential') ||
          msg.contains('wrong password')) {
        setState(() => _currentPwError = 'Current password is incorrect.');
      } else if (msg.contains('weak-password')) {
        setState(() => _currentPwError = 'New password is too weak.');
      } else if (msg.contains('too-many-requests')) {
        setState(
          () => _currentPwError =
              'Too many attempts. Please wait a few minutes.',
        );
      } else if (msg.contains('email-already-in-use') ||
          msg.contains('credential-already-in-use')) {
        setState(
          () => _currentPwError =
              'This email is already linked to another account.',
        );
      } else {
        setState(() => _currentPwError = msg.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
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
                  Text(
                    widget.isCreatingPassword
                        ? 'Create a password to also sign in using your email address.'
                        : 'Your password must be at least 8 characters long.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.dark,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!widget.isCreatingPassword) ...[
                    _buildField(
                      'Current Password',
                      widget.currentPwCtrl,
                      obscure: !_currentVisible,
                      onToggle: () =>
                          setState(() => _currentVisible = !_currentVisible),
                      visible: _currentVisible,
                      errorText: _currentPwError,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildField(
                    'New Password',
                    widget.newPwCtrl,
                    obscure: !_newVisible,
                    onToggle: () => setState(() => _newVisible = !_newVisible),
                    visible: _newVisible,
                    errorText: widget.isCreatingPassword
                        ? _currentPwError
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    'Confirm New Password',
                    widget.confirmPwCtrl,
                    obscure: !_confirmVisible,
                    onToggle: () =>
                        setState(() => _confirmVisible = !_confirmVisible),
                    visible: _confirmVisible,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _onSubmit,
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
                          _isSubmitting
                              ? (widget.isCreatingPassword
                                    ? 'Creating…'
                                    : 'Updating…')
                              : (widget.isCreatingPassword
                                    ? 'Create Password'
                                    : 'Update Password'),
                          key: ValueKey(_isSubmitting),
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
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    required bool obscure,
    required VoidCallback onToggle,
    required bool visible,
    String? errorText,
  }) {
    final hasError = errorText != null;
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
              borderSide: BorderSide(
                color: hasError ? AppColors.critical : AppColors.darkWith(0.12),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasError ? AppColors.critical : AppColors.darkWith(0.12),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasError ? AppColors.critical : AppColors.primaryWith(0.5),
              ),
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
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 11, color: AppColors.critical),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    errorText,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.critical,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
