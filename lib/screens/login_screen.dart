import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/services/supabase_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/services/voucher_history_service.dart';
import '../core/services/router_discovery_service.dart';
import '../core/services/activation_code_service.dart';
import '../core/services/session_service.dart';
import '../core/services/biometric_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  bool _biometricsEnabled = false;
  String _biometricLabel = "Fingerprint / Face ID";
  bool _hasEnrolledBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final hadExpired = await SessionService.instance.consumeExpiryNotice();
    if (hadExpired && mounted) {
      setState(() {
        _errorMessage = "Your session expired after 48 hours. Please sign in again.";
      });
    }

    final enabled = await BiometricAuthService.instance.isBiometricLoginEnabled();
    final label = await BiometricAuthService.instance.getBiometricTypeLabel();
    final creds = await BiometricAuthService.instance.getEnrolledCredentials();

    if (mounted) {
      setState(() {
        _biometricsEnabled = enabled;
        _biometricLabel = label;
        _hasEnrolledBiometrics = enabled && creds != null;
        if (_hasEnrolledBiometrics && _emailController.text.isEmpty) {
          _emailController.text = creds!['email'] ?? '';
        }
      });
    }
  }

  Future<void> _handleBiometricSignIn() async {
    setState(() => _errorMessage = null);
    final authenticated = await BiometricAuthService.instance.authenticate(
      reason: "Authenticate with $_biometricLabel to sign in",
    );
    if (!authenticated) return;

    final creds = await BiometricAuthService.instance.getEnrolledCredentials();
    if (creds != null && creds['email'] != null && creds['password'] != null) {
      _emailController.text = creds['email']!;
      _passwordController.text = creds['password']!;
      await _handleSignIn();
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = "No saved credentials found. Please sign in with your password.";
        });
      }
    }
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = "Please enter both email and password.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await SupabaseService.instance.signIn(email, password);
      if (response.user != null) {
        if (!mounted) return;
        final prefs = await SharedPreferences.getInstance();
        final oldEmail = prefs.getString('sb-user-email');
        if (oldEmail != null && oldEmail.toLowerCase().trim() != email.toLowerCase().trim()) {
          await prefs.remove(RouterDiscoveryService.keyRouterLocalIp);
          await prefs.remove(RouterDiscoveryService.keyRouterTunnelEndpoint);
          await prefs.remove(RouterDiscoveryService.keyRouterUsername);
          await prefs.remove(RouterDiscoveryService.keyRouterPassword);
        }
        await prefs.remove('admin_token');
        await prefs.remove('wavepass_voucher_history_v1');
        await VoucherHistoryService.instance.clearCache();
        await prefs.setString('sb-user-email', email);
        await VenueStateService.instance.clearVenue();
        final isSuperAdmin = email.toLowerCase().trim() == 'talk2icedmist@gmail.com';
        await VenueStateService.instance.refreshVenue(allowFallbackToPrimary: isSuperAdmin);
        await ActivationCodeService.instance.isAccountActivated(email);
        await SessionService.instance.recordLogin(email);
        if (_biometricsEnabled) {
          await BiometricAuthService.instance.enrollBiometrics(email: email, password: password);
        }
        if (!mounted) return;
        context.go(AppRouter.dashboard);
        return;
      }
      throw Exception('No session');
    } catch (e) {
      // Fallback: backend admin verify-password with email (for talk2icedmist@gmail.com + NexaAdmin#2025!WavePass)
      try {
        final r = await http.post(Uri.parse('${ApiConstants.cloudBaseUrl}/api/v1/admin/verify-password'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': email, 'password': password})).timeout(const Duration(seconds: 10));
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['ok'] == true && j['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          final oldEmail = prefs.getString('sb-user-email');
          if (oldEmail != null && oldEmail.toLowerCase().trim() != email.toLowerCase().trim()) {
            await prefs.remove(RouterDiscoveryService.keyRouterLocalIp);
            await prefs.remove(RouterDiscoveryService.keyRouterTunnelEndpoint);
            await prefs.remove(RouterDiscoveryService.keyRouterUsername);
            await prefs.remove(RouterDiscoveryService.keyRouterPassword);
          }
          await prefs.setString('admin_token', j['token']);
          await prefs.remove('wavepass_voucher_history_v1');
          await VoucherHistoryService.instance.clearCache();
          await prefs.setString('sb-user-email', email);
          await VenueStateService.instance.clearVenue();
          final isSuperAdmin = email.toLowerCase().trim() == 'talk2icedmist@gmail.com';
          await VenueStateService.instance.refreshVenue(allowFallbackToPrimary: isSuperAdmin);
          await ActivationCodeService.instance.isAccountActivated(email);
          await SessionService.instance.recordLogin(email);
          if (_biometricsEnabled) {
            await BiometricAuthService.instance.enrollBiometrics(email: email, password: password);
          }
          if (!mounted) return;
          context.go(AppRouter.dashboard);
          return;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _errorMessage = e.toString().contains('Invalid') ? 'Invalid credentials' : 'Login failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Logo
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "WavePass",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          "Venue Manager App",
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 36),

                // Welcome Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.containerBg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Sign In to Your Venue",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Manage your Wi-Fi, sell cash passes, and see today's earnings.",
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textLight,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Email Field
                      const Text(
                        "EMAIL ADDRESS",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: "admin@example.com",
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password Field
                      const Text(
                        "PASSWORD",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: "••••••••••••",
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: AppColors.textLight,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.redTint,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.accentRedDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSignIn,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Sign In",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      if (_hasEnrolledBiometrics) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _handleBiometricSignIn,
                            icon: const Icon(Icons.fingerprint_rounded, size: 22, color: AppColors.primary),
                            label: Text(
                              "Sign In with $_biometricLabel",
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.primary, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text("Don't have an account? ", style: TextStyle(fontSize: 13, color: AppColors.textLight)),
                  GestureDetector(onTap: () => context.go(AppRouter.signup), child: const Text('Sign Up', style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 14),
                const Center(child: Text("Built by Nexa Digital Nexus Point", style: TextStyle(fontSize: 12, color: AppColors.textLight))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
