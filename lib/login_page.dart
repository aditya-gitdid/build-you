import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'doctor_signup_page.dart';
import 'signup_page.dart';
import 'ui_components.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _isLoggingIn = false;
  bool _isDoctor = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _showStatusSnack({
    required String message,
    required bool success,
  }) {
    final bgColor = success ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C);
    final icon = success ? Icons.check_circle : Icons.error_outline;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _handleLogin() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showStatusSnack(
        message: 'Please enter valid email and password.',
        success: false,
      );
      return;
    }

    setState(() {
      _isLoggingIn = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      // role-based routing is handled in main.dart _AuthGate

      if (!mounted) return;
      _showStatusSnack(message: 'Successfully logged in.', success: true);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    } on FirebaseAuthException {
      if (!mounted) return;
      _showStatusSnack(
        message: 'Invalid credentials. Please try again.',
        success: false,
      );
    } catch (_) {
      if (!mounted) return;
      _showStatusSnack(
        message: 'Login failed. Please try again.',
        success: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF070A13), Color(0xFF061530)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = constraints.maxWidth >= 700;
              final cardWidth = isTablet ? 500.0 : constraints.maxWidth * 0.92;

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: isTablet ? 24 : 10),
                          const AppLogo(),
                          const SizedBox(height: 28),
                          const Text(
                            'BuildYou',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Track, Share, Achieve Together',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFAAB3C3),
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Role selector
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F1A2E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF1E3050)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isDoctor = false),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: !_isDoctor ? const Color(0xFFFF6200) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.person_outline,
                                              color: !_isDoctor ? Colors.white : const Color(0xFF8FA0BA),
                                              size: 18),
                                          const SizedBox(width: 6),
                                          Text(
                                            'User',
                                            style: TextStyle(
                                              color: !_isDoctor ? Colors.white : const Color(0xFF8FA0BA),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isDoctor = true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _isDoctor ? const Color(0xFFFF6200) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.medical_services_outlined,
                                              color: _isDoctor ? Colors.white : const Color(0xFF8FA0BA),
                                              size: 18),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Doctor',
                                            style: TextStyle(
                                              color: _isDoctor ? Colors.white : const Color(0xFF8FA0BA),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          const InputLabel(text: 'Email'),
                          const SizedBox(height: 10),
                          AppTextField(
                            controller: emailController,
                            hint: 'your@email.com',
                            icon: Icons.mail_outline,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 22),
                          const InputLabel(text: 'Password'),
                          const SizedBox(height: 10),
                          AppTextField(
                            controller: passwordController,
                            hint: '••••••••',
                            icon: Icons.lock_outline,
                            obscureText: true,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _rememberMe,
                                  side: const BorderSide(color: Color(0xFF657089)),
                                  fillColor: WidgetStateProperty.resolveWith(
                                    (states) => states.contains(WidgetState.selected)
                                        ? const Color(0xFFFF6200)
                                        : Colors.transparent,
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _rememberMe = value ?? false;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Remember me',
                                style: TextStyle(
                                  color: Color(0xFFAAB3C3),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {},
                                child: const Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    color: Color(0xFFFF6200),
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          PrimaryButton(
                            text: _isLoggingIn ? 'Logging in...' : 'Login',
                            onPressed: _isLoggingIn ? () {} : _handleLogin,
                          ),
                          const SizedBox(height: 30),
                          Center(
                            child: RichText(
                              text: TextSpan(
                                text: "Don't have an account? ",
                                style: const TextStyle(
                                  color: Color(0xFFAAB3C3),
                                  fontSize: 18,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Sign up',
                                    style: const TextStyle(
                                      color: Color(0xFFFF6200),
                                      fontWeight: FontWeight.w700,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => _isDoctor
                                                ? const DoctorSignupPage()
                                                : const SignupPage(),
                                          ),
                                        );
                                      },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}