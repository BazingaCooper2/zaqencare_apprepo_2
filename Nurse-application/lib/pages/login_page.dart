import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nurse_tracking_app/pages/dashboard_page.dart';
import 'package:nurse_tracking_app/services/session.dart';
import 'package:nurse_tracking_app/constants/tables.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  Future<void> _signIn() async {
    try {
      setState(() => _isLoading = true);

      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Please enter both email and password')));
        setState(() => _isLoading = false);
        return;
      }

      debugPrint('🔍 Attempting manual login for: $email');

      // ✅ Step 1: Query database directly for email and password
      final List<dynamic> response = await Supabase.instance.client
          .from(Tables.employee)
          .select()
          .eq('email', email)
          .eq('password', password)
          .limit(1);

      if (response.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid email or password.')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      final employee = response.first as Map<String, dynamic>;
      debugPrint('✅ Logged in manually as ${employee['email']}');

      // ✅ Step 2: Save session locally
      await SessionManager.saveSession(employee);

      // ✅ Navigate to dashboard
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Login successful')),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardPage()),
        );
      }
    } catch (error, stack) {
      debugPrint('❌ Login error: $error');
      debugPrint(stack.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  UI ONLY — nothing below touches logic/API
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

    const accentTeal = Color(0xFF1D9E75);
    const accentTealLight = Color(0xFF5DCAA5);
    const accentGlow = Color(0x221D9E75);

    final effectiveCard = isDark ? const Color(0xFF111E30) : Colors.white;
    final effectiveTitle = isDark ? Colors.white : const Color(0xFF0B1628);
    const effectiveSubtitle = Color(0xFF8896A8);
    final effectiveInputBg =
        isDark ? const Color(0xFF18273D) : const Color(0xFFF3F7FB);
    final effectiveInputBorder =
        isDark ? const Color(0xFF243350) : const Color(0xFFDDE4EE);
    final effectiveInputText = isDark ? Colors.white : const Color(0xFF0B1628);
    const effectiveLabel = Color(0xFF8896A8);

    InputDecoration field({
      required String label,
      required String hint,
      required Widget prefix,
      Widget? suffix,
    }) =>
        InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              fontSize: 13, color: effectiveLabel, fontWeight: FontWeight.w500),
          hintText: hint,
          hintStyle: TextStyle(
              color: effectiveLabel.withValues(alpha: 0.5), fontSize: 14),
          prefixIcon: prefix,
          suffixIcon: suffix,
          filled: true,
          fillColor: effectiveInputBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: effectiveInputBorder, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: accentTeal, width: 1.5),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: effectiveInputBorder, width: 1),
          ),
        );

    return Scaffold(
      backgroundColor: const Color(0xFF0B1628),
      body: Stack(
        children: [
          // ── Decorative background ─────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _BgPainter()),
          ),

          // ── Content ───────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: screenHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: AnimationLimiter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: AnimationConfiguration.toStaggeredList(
                        duration: const Duration(milliseconds: 520),
                        childAnimationBuilder: (widget) => SlideAnimation(
                          verticalOffset: 30.0,
                          child: FadeInAnimation(child: widget),
                        ),
                        children: [
                          SizedBox(height: screenHeight * 0.06),

                          // ── Brand pill ────────────────────
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: accentGlow,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: accentTeal.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: accentTeal,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: const Icon(
                                    Icons.medical_services_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'ZaqenCare',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: accentTealLight,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.032),

                          // ── Hero text ─────────────────────
                          const Text(
                            'Staff\nPortal.',
                            style: TextStyle(
                              fontSize: 54,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.0,
                              letterSpacing: -2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: accentTeal,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Care Management System',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white.withValues(alpha: 0.4),
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: screenHeight * 0.045),

                          // ── Login card ────────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: effectiveCard,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.04),
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Card top row
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Welcome back',
                                            style: TextStyle(
                                              fontSize: 19,
                                              fontWeight: FontWeight.w700,
                                              color: effectiveTitle,
                                              letterSpacing: -0.4,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          const Text(
                                            'Sign in to continue',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: effectiveSubtitle,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Decorative dot cluster
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Column(
                                        children: [
                                          Row(children: [
                                            _dot(accentTeal, 7),
                                            const SizedBox(width: 4),
                                            _dot(
                                                accentTealLight.withValues(
                                                    alpha: 0.35),
                                                5),
                                          ]),
                                          const SizedBox(height: 4),
                                          Row(children: [
                                            _dot(
                                                accentTealLight.withValues(
                                                    alpha: 0.35),
                                                5),
                                            const SizedBox(width: 4),
                                            _dot(
                                                accentTeal.withValues(
                                                    alpha: 0.25),
                                                7),
                                          ]),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 22),

                                // Email field
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  style: TextStyle(
                                      fontSize: 14, color: effectiveInputText),
                                  decoration: field(
                                    label: 'Email address',
                                    hint: 'nurse@hospital.com',
                                    prefix: const Icon(Icons.email_outlined,
                                        size: 18, color: effectiveLabel),
                                  ),
                                ),
                                const SizedBox(height: 13),

                                // Password field
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: !_isPasswordVisible,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _signIn(),
                                  style: TextStyle(
                                      fontSize: 14, color: effectiveInputText),
                                  decoration: field(
                                    label: 'Password',
                                    hint: '••••••••',
                                    prefix: const Icon(Icons.lock_outline,
                                        size: 18, color: effectiveLabel),
                                    suffix: IconButton(
                                      onPressed: () => setState(() =>
                                          _isPasswordVisible =
                                              !_isPasswordVisible),
                                      icon: Icon(
                                        _isPasswordVisible
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        size: 18,
                                        color: effectiveLabel,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // Forgot password
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () {},
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'Forgot password?',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: accentTeal,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // Sign in button
                                SizedBox(
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _signIn,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accentTeal,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          accentTeal.withValues(alpha: 0.45),
                                      disabledForegroundColor: Colors.white,
                                      elevation: 0,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'Sign in',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(Icons.arrow_forward_rounded,
                                                  size: 18),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.04),

                          // ── Footer ────────────────────────
                          Center(
                            child: Text(
                              '· ZaqenCare v1.0 ·',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.2),
                                letterSpacing: 1.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── Background painter ──────────────────────────────────────────────────────
class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Base
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0B1628),
    );

    // Large teal blob — top right
    canvas.drawCircle(
      Offset(size.width + 50, -70),
      230,
      Paint()
        ..color = const Color(0xFF1D9E75).withValues(alpha: 0.13)
        ..style = PaintingStyle.fill,
    );

    // Smaller inner blob
    canvas.drawCircle(
      Offset(size.width - 10, 50),
      110,
      Paint()
        ..color = const Color(0xFF1D9E75).withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );

    // Ring outline
    canvas.drawCircle(
      Offset(size.width + 50, -70),
      270,
      Paint()
        ..color = const Color(0xFF1D9E75).withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Subtle second ring
    canvas.drawCircle(
      Offset(size.width + 50, -70),
      310,
      Paint()
        ..color = const Color(0xFF1D9E75).withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // Bottom-left dim blob
    canvas.drawCircle(
      Offset(-50, size.height + 30),
      180,
      Paint()
        ..color = const Color(0xFF0F6E56).withValues(alpha: 0.07)
        ..style = PaintingStyle.fill,
    );

    // Dot grid — upper portion only
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;
    const spacing = 26.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height * 0.42; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => false;
}
