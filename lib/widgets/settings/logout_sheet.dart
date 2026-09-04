import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class LogoutSheet extends StatefulWidget {
  final Future<void> Function() onLogout;

  const LogoutSheet({super.key, required this.onLogout});

  @override
  State<LogoutSheet> createState() => _LogoutSheetState();
}

class _LogoutSheetState extends State<LogoutSheet> {
  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      await widget.onLogout();
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Logout',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Are you sure you want to logout?',
              style: TextStyle(fontSize: 12, color: AppColors.dark),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoggingOut ? null : _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.critical,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Text(
                    _isLoggingOut ? 'Logging out…' : 'Yes, Logout',
                    key: ValueKey(_isLoggingOut),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isLoggingOut
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.dark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
