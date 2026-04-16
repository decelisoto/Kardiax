// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import 'ecg_dashboard.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const EcgDashboard(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = switch (e.code) {
          'user-not-found'  => 'No account found with this email.',
          'wrong-password'  => 'Incorrect password.',
          'invalid-email'   => 'Please enter a valid email.',
          'user-disabled'   => 'This account has been disabled.',
          _                 => 'Sign in failed. Please try again.',
        };
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmall = size.height < 700;

    return Scaffold(
      backgroundColor: KardiaxColors.black,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.08,
                vertical: isSmall ? 24 : 40,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: isSmall ? 20 : 40),

                    // ── Logo ──
                    RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: 'Kardia',
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 38,
                              fontWeight: FontWeight.w700,
                              color: KardiaxColors.textPrimary,
                              letterSpacing: 2,
                            ),
                          ),
                          TextSpan(
                            text: 'x',
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 38,
                              fontWeight: FontWeight.w700,
                              color: KardiaxColors.red,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Cardiac monitoring, redefined.',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        color: KardiaxColors.textSecondary,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),

                    SizedBox(height: isSmall ? 32 : 52),

                    // ── Welcome text ──
                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        color: KardiaxColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sign in to continue monitoring',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        color: KardiaxColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Email field ──
                    _FieldLabel('EMAIL'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(
                        fontFamily: 'Rajdhani',
                        color: KardiaxColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: _inputDecoration(
                        'you@example.com',
                        Icons.mail_outline,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter your email';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    // ── Password field ──
                    _FieldLabel('PASSWORD'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(
                        fontFamily: 'Rajdhani',
                        color: KardiaxColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration:
                          _inputDecoration(
                            '••••••••',
                            Icons.lock_outline,
                          ).copyWith(
                            suffixIcon: GestureDetector(
                              onTap: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              child: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: KardiaxColors.gray,
                                size: 18,
                              ),
                            ),
                          ),
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return 'Enter your password';
                        if (v.length < 6) return 'Password too short';
                        return null;
                      },
                    ),

                    // ── Forgot password ──
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: KardiaxColors.red,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 0,
                          ),
                        ),
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),

                    // ── Error message ──
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: KardiaxColors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: KardiaxColors.red.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: KardiaxColors.red,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                fontFamily: 'Rajdhani',
                                color: KardiaxColors.red,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // ── Sign in button ──
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: KardiaxColors.red,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: KardiaxColors.red
                              .withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
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
                                'SIGN IN',
                                style: TextStyle(
                                  fontFamily: 'Rajdhani',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Register link ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account? ",
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            color: KardiaxColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                          child: const Text(
                            'Sign up',
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              color: KardiaxColors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: isSmall ? 20 : 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: 'Rajdhani',
        color: KardiaxColors.textHint,
        fontSize: 14,
      ),
      prefixIcon: Icon(icon, color: KardiaxColors.gray, size: 18),
      filled: true,
      fillColor: KardiaxColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: KardiaxColors.gray.withOpacity(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: KardiaxColors.gray.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: KardiaxColors.red, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: KardiaxColors.red.withOpacity(0.5)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: KardiaxColors.red, width: 1.5),
      ),
      errorStyle: const TextStyle(
        fontFamily: 'Rajdhani',
        color: KardiaxColors.red,
        fontSize: 12,
      ),
    );
  }
}

// ── Field label ──
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Rajdhani',
        color: KardiaxColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }
}
