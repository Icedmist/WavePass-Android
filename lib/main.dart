import 'dart:ui';
import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/services/supabase_service.dart';
import 'core/services/venue_state_service.dart';
import 'core/services/activation_code_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/router_discovery_service.dart';
import 'core/widgets/graceful_error_widget.dart';
import 'core/router/app_router.dart';

final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Global error traps to permanently prevent app crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Global FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Global Uncaught Error: $error\n$stack');
    return true; // Handled, prevents fatal process abort
  };

  // Graceful fallback widget instead of the default red screen of death
  ErrorWidget.builder = buildGracefulErrorWidget;

  // Immediately purge any cached blacklisted ISP gateways (e.g. Starlink dish at 192.168.1.1)
  try {
    await RouterDiscoveryService.sanitizeCachedRouterTarget();
  } catch (e) {
    debugPrint('Router target sanitize on startup: $e');
  }

  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase initial connection handled: $e');
  }

  try {
    await VenueStateService.instance.init();
  } catch (e) {
    debugPrint('VenueStateService initial load: $e');
  }

  try {
    await ActivationCodeService.instance.warmCache();
  } catch (e) {
    debugPrint('ActivationCodeService warm cache: $e');
  }

  AppNotifier.instance.bindMessenger(rootMessengerKey);
  try {
    await AppNotifier.instance.init();
  } catch (e) {
    debugPrint('AppNotifier initial init: $e');
  }

  runApp(const WavePassApp());
}

class WavePassApp extends StatelessWidget {
  const WavePassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Wavepass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scaffoldMessengerKey: rootMessengerKey,
      routerConfig: AppRouter.router,
    );
  }
}
