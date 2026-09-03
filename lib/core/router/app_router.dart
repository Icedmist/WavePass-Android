import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../screens/splash_screen.dart';
import '../../screens/onboarding_screen.dart';
import '../../screens/login_screen.dart';
import '../../screens/signup_screen.dart';
import '../../screens/home_dashboard_screen.dart';
import '../../screens/router_setup_screen.dart';
import '../../screens/sell_pass_screen.dart';
import '../../screens/active_devices_screen.dart';
import '../../screens/router_diagnostics_screen.dart';
import '../../screens/printer_settings_screen.dart';
import '../../screens/admin_management_screen.dart';
import '../../screens/how_to_use_screen.dart';
import '../../screens/terms_screen.dart';
import '../../screens/privacy_screen.dart';
import '../../screens/barcode_scanner_screen.dart';
import '../../screens/wallet_screen.dart';
import '../../screens/notifications_screen.dart';
import '../../screens/account_center_screen.dart';
import 'scaffold_with_nav.dart';

CustomTransitionPage<T> _slideFade<T>(Widget child, GoRouterState s) => CustomTransitionPage<T>(
      key: s.pageKey,
      child: child,
      transitionsBuilder: (c, a, sa, ch) {
        final curved = CurvedAnimation(parent: a, curve: const Cubic(0.16, 1, 0.3, 1));
        final scale = Tween<double>(begin: 0.98, end: 1.0).animate(curved);
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.08, 0.02), end: Offset.zero).animate(curved),
            child: ScaleTransition(scale: scale, child: ch),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
    );

/// Centralised navigation for WavePass. Every destination is a named route so
/// screens, deep links and future bottom-tab shells all reference one source of
/// truth instead of ad-hoc `MaterialPageRoute` pushes.
class AppRouter {
  AppRouter._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const signup = '/signup';
  static const dashboard = '/dashboard';
  static const notifications = '/notifications';
  static const account = '/account';
  static const routerSetup = '/setup-router';
  static const sellPass = '/sell-pass';
  static const activeDevices = '/active-devices';
  static const routerDiagnostics = '/router-health';
  static const printerSettings = '/printer-settings';
  static const admin = '/admin';
  static const howToUse = '/how-to-use';
  static const terms = '/terms';
  static const privacy = '/privacy';
  static const barcodeScanner = '/barcode-scanner';
  static const wallet = '/wallet';

  static final GoRouter router = GoRouter(
    initialLocation: splash,
    routes: [
      GoRoute(path: splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: onboarding, builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: signup, pageBuilder: (c, s) => _slideFade(const SignupScreen(), s)),
      GoRoute(path: notifications, pageBuilder: (c, s) => _slideFade(const NotificationsScreen(), s)),
      GoRoute(path: account, pageBuilder: (c, s) => _slideFade(const AccountCenterScreen(), s)),
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => ScaffoldWithNav(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: dashboard, pageBuilder: (c, s) => _slideFade(const HomeDashboardScreen(), s))]),
          StatefulShellBranch(routes: [GoRoute(path: activeDevices, pageBuilder: (c, s) => _slideFade(const ActiveDevicesScreen(), s))]),
          StatefulShellBranch(routes: [GoRoute(path: sellPass, pageBuilder: (c, s) => _slideFade(const SellPassScreen(), s))]),
          StatefulShellBranch(routes: [GoRoute(path: wallet, pageBuilder: (c, s) => _slideFade(const WalletScreen(), s))]),
          StatefulShellBranch(routes: [GoRoute(path: admin, pageBuilder: (c, s) => _slideFade(const AdminManagementScreen(), s))]),
        ],
      ),
      GoRoute(path: routerSetup, pageBuilder: (c, s) => _slideFade(const RouterSetupScreen(), s)),
      GoRoute(path: routerDiagnostics, pageBuilder: (c, s) => _slideFade(const RouterDiagnosticsScreen(), s)),
      GoRoute(path: printerSettings, pageBuilder: (c, s) => _slideFade(const PrinterSettingsScreen(), s)),
      GoRoute(path: howToUse, pageBuilder: (c, s) => _slideFade(const HowToUseScreen(), s)),
      GoRoute(path: terms, pageBuilder: (c, s) => _slideFade(const TermsScreen(), s)),
      GoRoute(path: privacy, pageBuilder: (c, s) => _slideFade(const PrivacyScreen(), s)),
      GoRoute(path: barcodeScanner, pageBuilder: (c, s) => _slideFade(const BarcodeScannerScreen(), s)),
    ],
  );
}

/// Convenience so any screen can do `context.goNamedRoute(AppRouter.wallet)`.
extension AppRouteContext on BuildContext {
  void goNamedRoute(String path) => go(path);
}