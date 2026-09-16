import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/services/supabase_service.dart';
import 'core/services/venue_state_service.dart';
import 'core/services/activation_code_service.dart';
import 'core/services/notification_service.dart';
import 'core/router/app_router.dart';

final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
