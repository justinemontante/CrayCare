import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_button.dart';
import 'verify_screen.dart';
import '../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Dynamic error holder para sa email field
  String? _emailError;

  // Global Key para sa Form Validation
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  // NATIVE SIGN UP LOGIC (No OTP packages, pure Firebase Link)
  void _signUp() async {
    // I-reset muna ang email error bago mag-validate ulit
    setState(() => _emailError = null);

    // 1. I-validate ang form. Kung may kulang, hihinto ito at magrered ang textfield.
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 2. Gagawa ng user at awtomatikong magpapadala ng verification link galing sa Google
      await _authService.signUp(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (!mounted) return;
      // 3. Dideretso sa VerifyScreen (Malinis, WALANG PARAMETERS na kailangan)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VerifyScreen()),
      );
    } catch (e) {
      final errorMsg = e.toString().replaceAll('Exception: ', '');

      // KUNG REGISTERED NA ANG EMAIL: I-set ang error sa variable at patakbuhin ulit ang validator
      if (errorMsg.contains('email-already-in-use') ||
          errorMsg.contains('already-in-use') ||
          errorMsg.contains('already in use')) {
        setState(() {
          _emailError = 'This email is already in use';
        });
        _formKey.currentState!.validate(); // Pwersahing mag-red ang textfield
      } else {
        _showErrorSnackBar(errorMsg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // REUSABLE INPUT DECORATION STYLE WITH BEAUTIFUL ERROR BORDERS
  InputDecoration _buildInputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: AppColors.darkWith(0.4), fontSize: 14),
      filled: true,
      fillColor: AppColors.whiteWith(0.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),

      // Standard borders
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.whiteWith(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.whiteWith(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),

      // Red Error borders for a professional look
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      errorStyle: const TextStyle(
        color: Colors.redAccent,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              children: [
                SizedBox(
                  width: 130,
                  child: Image.asset('assets/images/logo.png'),
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Cray',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                    Text(
                      'Care',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Create an account',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.darkWith(0.7),
                  ),
                ),
                const SizedBox(height: 16),

                // FORM WITH VALIDATION KEY
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Full Name',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dark,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // TEXTFORMFIELD FOR FULL NAME
                      TextFormField(
                        controller: _nameController,
                        decoration: _buildInputDecoration(
                          'Enter your full name',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Full name is required';
                          }
                          return null;
                        },
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Email',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dark,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // TEXTFORMFIELD FOR EMAIL WITH DYNAMIC ERROR LABEL
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _buildInputDecoration('Enter your email'),
                        onChanged: (value) {
                          // Kapag nagbago ang tinype ng user, burahin agad ang pulang error label
                          if (_emailError != null) {
                            setState(() {
                              _emailError = null;
                            });
                            _formKey.currentState!.validate();
                          }
                        },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!RegExp(
                            r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                          ).hasMatch(value.trim())) {
                            return 'Please enter a valid email address';
                          }
                          // Ibabalik ang "This email is already in use" kung ito ay na-trigger sa catch block
                          if (_emailError != null) {
                            return _emailError;
                          }
                          return null;
                        },
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dark,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // TEXTFORMFIELD FOR PASSWORD
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: _buildInputDecoration('Create a password')
                            .copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppColors.darkWith(0.5),
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Password is required';
                          }
                          if (value.trim().length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 18),
                      GradientButton(
                        onTap: _isLoading ? () {} : _signUp,
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
                                'Sign Up',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppColors.primary,
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppColors.primary,
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Starting Google Sign-In...'),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.whiteWith(0.8),
                            side: BorderSide(color: AppColors.whiteWith(0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/icons/google.png',
                                width: 20,
                                height: 20,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Sign Up with Google',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.dark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Already have an account? ",
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.dark,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
