import 'package:flutter/material.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onOtpChange(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  SizedBox(width: 130, child: Image.asset('assets/images/logo.png')),
                  const SizedBox(height: 8),
                  const Text(
                    'Verification',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0B3C49)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Enter the 6-digit code sent to your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: const Color(0xFF0B3C49).withOpacity(0.7)),
                  ),
                  const SizedBox(height: 32),
                  // OTP inputs
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: SizedBox(
                          width: 40,
                          height: 50,
                          child: TextField(
                            controller: _otpControllers[index],
                            focusNode: _focusNodes[index],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49)),
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.8),
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF1FA5A5), width: 1.5),
                              ),
                            ),
                            onChanged: (value) => _onOtpChange(index, value),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  // Verify button
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: const Color(0xFF1FA5A5).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
                        gradient: const LinearGradient(colors: [Color(0xFF0B3C49), Color(0xFF1FA5A5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      ),
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Verify', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Resend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Didn't receive code? ", style: TextStyle(fontSize: 13, color: const Color(0xFF0B3C49))),
                      GestureDetector(
                        onTap: () {},
                        child: const Text('Resend', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1FA5A5))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Back to Sign Up
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      'Back to Sign Up',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0B3C49).withOpacity(0.8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
