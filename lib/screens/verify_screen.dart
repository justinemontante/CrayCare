import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_button.dart';
import 'main_shell.dart';
import 'signup_screen.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;
  bool _isVerified = false;

  // COUNTDOWN TIMER VARIABLES
  Timer? _timer;
  int _countdownStart = 60;
  bool _isResendEnabled = false;

  @override
  void initState() {
    super.initState();
    _startTimer(); // Simulan ang cooldown timer ng 60s
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_isVerified) {
      _deleteUnverifiedAccount();
    }
    super.dispose();
  }

  void _deleteUnverifiedAccount() async {
    try {
      await _currentUser?.delete();
    } catch (_) {
      // Account already deleted or token expired
    }
  }

  void _startTimer() {
    setState(() {
      _isResendEnabled = false;
      _countdownStart = 60;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdownStart == 0) {
        setState(() {
          _timer?.cancel();
          _isResendEnabled = true;
        });
      } else {
        setState(() {
          _countdownStart--;
        });
      }
    });
  }

  // Helper function para i-format ang timer bilang 00:SS (e.g., 00:45)
  String _formatTimer(int seconds) {
    final s = seconds.toString().padLeft(2, '0');
    return '00:$s';
  }

  // NATIVE FIREBASE RESEND LINK
  void _resendVerificationLink() async {
    if (!_isResendEnabled) return;

    setState(() => _isLoading = true);
    try {
      await _currentUser?.sendEmailVerification();
      _showSuccessSnackBar(
        'A new verification link has been sent to your email!',
      );
      _startTimer(); // Reset ang cooldown timer
    } catch (e) {
      _showErrorSnackBar(
        'Too many requests. Please wait for the timer to finish.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // NATIVE FIREBASE VERIFY LINK CHECKER
  void _checkEmailVerification() async {
    setState(() => _isLoading = true);
    try {
      await _currentUser
          ?.reload(); // I-reload ang Firebase session para makuha ang latest status
      final freshUser = FirebaseAuth.instance.currentUser;

      if (freshUser != null && freshUser.emailVerified) {
        if (!mounted) return;
        _showSuccessModal(); // Ipakita ang Animated Success Modal!
      } else {
        if (!mounted) return;
        _showErrorSnackBar(
          'Email not verified yet. Please click the link sent to your inbox first.',
        );
      }
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // LOGOUT (Babalik sa Signup Screen)
  void _logout() async {
    try {
      _timer?.cancel();
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SignupScreen()),
      );
    } catch (e) {
      _showErrorSnackBar('Logout error: $e');
    }
  }

  // ANIMATED SUCCESS MODAL (Scale + Fade Transition)
  void _showSuccessModal() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: anim1,
            child: AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22c55e).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: Color(0xFF22c55e),
                      size: 54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Email Verified!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Welcome to CrayCare. Your account has been successfully created and verified.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        _timer?.cancel();
                        _isVerified = true;
                        Navigator.pop(context); // Close Modal
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const MainShell()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Go to Dashboard',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emailAddress = _currentUser?.email ?? 'your email';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _logout();
        }
      },
      child: Scaffold(
        body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 50, 28, 40),
              child: Column(
                children: [
                  SizedBox(
                    width: 130,
                    child: Image.asset('assets/images/logo.png'),
                  ),
                  const SizedBox(height: 32),

                  const Text(
                    'Verify your email',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                    'We sent a secure verification link to:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.dark.withValues(alpha: 0.6),
                    ),
                  ),

                  // ✉️ MAGANDANG HORIZONTAL EMAIL BOX KATULAD NG SCREENSHOT
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 4,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.darkWith(
                        0.04,
                      ), // Soft grey/blue background
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.darkWith(0.05)),
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center, // Centered content
                      children: [
                        const Icon(
                          Icons.mail_outline_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            emailAddress,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),
                  Text(
                    'Please check your inbox (and Spam folder)\nand click the link to activate your account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.dark.withValues(alpha: 0.7),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // I HAVE CLICKED THE LINK BUTTON
                  GradientButton(
                    onTap: _isLoading ? () {} : _checkEmailVerification,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'I have clicked the link',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Didn't receive the link? ",
                            style: TextStyle(fontSize: 13, color: AppColors.dark),
                          ),
                          _isResendEnabled
                              ? TextButton(
                                  onPressed: _isLoading ? null : _resendVerificationLink,
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                        )
                                      : const Text(
                                          'Resend Link',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  child: Text(
                                    'Resend in ${_formatTimer(_countdownStart)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.dark.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // BACK TO SIGN UP
                  GestureDetector(
                    onTap: _logout,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_back_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Back to Sign Up',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
