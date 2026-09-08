import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/services/supabase_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final user = SupabaseService.instance.currentUser;
      final adminToken = prefs.getString('admin_token');
      if (user != null || (adminToken != null && adminToken.isNotEmpty)) {
        if (!mounted) return;
        context.go(AppRouter.dashboard);
        return;
      }
      final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
      if (!mounted) return;
      if (!hasSeenOnboarding) {
        context.go(AppRouter.onboarding);
      } else {
        context.go(AppRouter.login);
      }
      return;
    } catch (_) {
      // Supabase not yet initialized (e.g. In unit tests)
    }

    if (!mounted) return;
    context.go(AppRouter.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Hero(
                tag: 'wavepass-logo',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "WavePass",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Venue Wi-Fi Management",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.accentRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
