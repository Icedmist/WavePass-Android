import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../screens/splash_screen.dart';
import '../../screens/onboarding_screen.dart';
import '../../screens/login_screen.dart';
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

/// Centralised navigation for WavePass. Every destination is a named route so
/// screens, deep links and future bottom-tab shells all reference one source of
/// truth instead of ad-hoc `MaterialPageRoute` pushes.
class AppRouter {
  AppRouter._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const dashboard = '/dashboard';
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
      GoRoute(path: dashboard, builder: (_, __) => const HomeDashboardScreen()),
      GoRoute(path: routerSetup, builder: (_, __) => const RouterSetupScreen()),
      GoRoute(path: sellPass, builder: (_, __) => const SellPassScreen()),
      GoRoute(path: activeDevices, builder: (_, __) => const ActiveDevicesScreen()),
      GoRoute(path: routerDiagnostics, builder: (_, __) => const RouterDiagnosticsScreen()),
      GoRoute(path: printerSettings, builder: (_, __) => const PrinterSettingsScreen()),
      GoRoute(path: admin, builder: (_, __) => const AdminManagementScreen()),
      GoRoute(path: howToUse, builder: (_, __) => const HowToUseScreen()),
      GoRoute(path: terms, builder: (_, __) => const TermsScreen()),
      GoRoute(path: privacy, builder: (_, __) => const PrivacyScreen()),
      GoRoute(path: barcodeScanner, builder: (_, __) => const BarcodeScannerScreen()),
      GoRoute(path: wallet, builder: (_, __) => const WalletScreen()),
    ],
  );
}

/// Convenience so any screen can do `context.goNamedRoute(AppRouter.wallet)`.
extension AppRouteContext on BuildContext {
  void goNamedRoute(String path) => go(path);
}