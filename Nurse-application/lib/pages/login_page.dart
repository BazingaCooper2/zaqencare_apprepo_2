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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter both email and password')));
        setState(() => _isLoading = false);
        return;
      }

      Map<String, dynamic>? employee;

      debugPrint('🔍 Attempting login for: $email');

      // ✅ Step 1: Check Database directly for matching email and password
      try {
        final List<dynamic> dbResponse = await Supabase.instance.client
            .from(Tables.employee)
            .select('emp_id, first_name, last_name, email, designation, image_url, Employee_status')
            .eq('email', email)
            .eq('password', password)
            .limit(1);

        if (dbResponse.isNotEmpty) {
          employee = dbResponse.first as Map<String, dynamic>;
          debugPrint('✅ Logged in via Database match as ${employee['email']}');

          // Try to sign in with Supabase Auth silently (don't block if it fails)
          try {
            await Supabase.instance.client.auth.signInWithPassword(
              email: email,
              password: password,
            );
          } catch (_) {
            debugPrint('⚠️ Supabase Auth failed silently.');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Database direct auth login attempt issue: $e');
      }

      // ✅ Step 2: Fallback to Supabase Auth if DB match failed (Optional)
      if (employee == null) {
        try {
          final authResponse = await Supabase.instance.client.auth.signInWithPassword(
            email: email,
            password: password,
          );

          final user = authResponse.user;
          if (user != null) {
            debugPrint('✅ Logged in via Supabase Auth as ${user.email}');

            final List<dynamic> empResponse = await Supabase.instance.client
                .from(Tables.employee)
                .select('emp_id, first_name, last_name, email, designation, image_url, Employee_status')
                .eq('email', user.email ?? email)
                .limit(1);

            if (empResponse.isNotEmpty) {
              employee = empResponse.first as Map<String, dynamic>;
            }
          }
        } catch (e) {
          debugPrint('⚠️ Supabase Auth fallback failed: $e');
        }
      }

      if (employee == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid email or password.')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // ✅ Ensure emp_id is linked to auth.uid() for RLS
      try {
        final empId = await SessionManager.getOrCreateEmployeeLink();
        print("Logged in employee id: $empId");
      } catch (e) {
        debugPrint('⚠️ RLS link error: $e');
      }

      // ✅ Step 3: Save employee session locally
      await SessionManager.saveSession(employee);
      debugPrint('💾 Session saved for employee: ${employee['email']}');

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              const Color(0xFF0F2027),
              const Color(0xFF203A43),
              const Color(0xFF2C5364)
            ]
          : [const Color(0xFFE0F7FA), const Color(0xFF80DEEA)],
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: AnimationLimiter(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: AnimationConfiguration.toStaggeredList(
                  duration: const Duration(milliseconds: 600),
                  childAnimationBuilder: (widget) => SlideAnimation(
                    verticalOffset: 50.0,
                    child: FadeInAnimation(
                      child: widget,
                    ),
                  ),
                  children: [
                    // Brand Logo/Icon
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.medical_services_rounded,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Main Card
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Card(
                        elevation: 8,
                        shadowColor: Colors.black26,
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                "Welcome Back",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "ZaqenCare Assistance Portal",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 32),

                              // Email Input
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Email Address',
                                  prefixIcon: Icon(Icons.email_outlined),
                                  hintText: 'nurse@hospital.com',
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Password Input
                              TextFormField(
                                controller: _passwordController,
                                obscureText: !_isPasswordVisible,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _signIn(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(() =>
                                        _isPasswordVisible =
                                            !_isPasswordVisible),
                                    icon: Icon(
                                      _isPasswordVisible
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),

                              // Sign In Button
                              ElevatedButton(
                                onPressed: _isLoading ? null : _signIn,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: theme
                                      .colorScheme.primary
                                      .withValues(alpha: 0.6),
                                  disabledForegroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shadowColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.4),
                                  elevation: 6,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Sign In',
                                        style: TextStyle(
                                            fontSize: 18, height: 1.0),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'ZaqenCare Care Management System v1.0',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
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
