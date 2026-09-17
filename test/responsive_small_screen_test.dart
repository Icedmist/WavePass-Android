import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/screens/system_admin/system_admin_dashboard_screen.dart';
import 'package:wavepass_mobile/screens/batch_vouchers_screen.dart';
import 'package:wavepass_mobile/screens/sell_pass_screen.dart';

/// Small-phone responsiveness: none of these screens may throw layout
/// overflow errors at 320x568 (iPhone SE-class width).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Some screens call context.canPop()/push during build, so pump inside a
  /// real GoRouter instead of a bare MaterialApp.
  Future<void> pumpSmall(WidgetTester tester, Widget screen) async {
    // physicalSize is in physical pixels: 640x1136 @ DPR 2 == logical 320x568.
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    // Dump full diagnostics (with creator file:line) instead of swallowing.
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
    };
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => screen)],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  group('Small-screen responsiveness (320x568)', () {
    testWidgets('SystemAdminDashboard has no overflow', (tester) async {
      await pumpSmall(tester, const SystemAdminDashboardScreen());
      expect(find.text('System Administrator Hub'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('BatchVouchers has no overflow', (tester) async {
      await pumpSmall(tester, const BatchVouchersScreen());
      final err = tester.takeException();
      if (err != null) debugPrint('BATCH_OVERFLOW_DETAILS:\n$err');
      expect(err, isNull);
    });

    testWidgets('SellPass has no overflow', (tester) async {
      await pumpSmall(tester, const SellPassScreen());
      final err = tester.takeException();
      if (err != null) debugPrint('SELL_OVERFLOW_DETAILS:\n$err');
      expect(err, isNull);
    });
  });
}
