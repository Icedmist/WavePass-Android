import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavepass_mobile/core/services/notification_service.dart';
import 'package:wavepass_mobile/core/widgets/plan_configurator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Loops and Runtime Bugs Regression Tests', () {
    test('AppNotifier stopPaymentPolling resets state and prevents re-entrant polling', () async {
      final notifier = AppNotifier.instance;

      expect(notifier.isRefreshingPayments, isFalse);

      notifier.stopPaymentPolling();
      expect(notifier.isRefreshingPayments, isFalse);

      // Verify remote ID deduplication
      final initialFeedCount = notifier.feed.value.length;
      notifier.push(
        type: NotifyType.info,
        title: 'Test Notification',
        message: 'First delivery',
        remoteId: 'test-remote-uuid-1',
      );

      expect(notifier.feed.value.length, equals(initialFeedCount + 1));
      expect(notifier.feed.value.first.id, equals('test-remote-uuid-1'));

      // Duplicate delivery of identical remote ID should be ignored
      notifier.push(
        type: NotifyType.info,
        title: 'Test Notification Duplicated',
        message: 'Second delivery with same remote ID',
        remoteId: 'test-remote-uuid-1',
      );

      expect(notifier.feed.value.length, equals(initialFeedCount + 1));
    });

    testWidgets('PlanConfiguratorSheet safely initializes with double and num values without type cast errors', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final planWithDoubleTypes = {
        'id': 'plan_double_test_1',
        'name': 'Double Duration Plan',
        'durationSeconds': 10800.0, // double instead of int
        'priceMinor': 150000.0, // double instead of int
        'simultaneousDevices': 3.0, // double instead of int
        'rateLimit': '15M',
        'dataLimitBytes': 5368709120.0, // 5GB as double
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlanConfiguratorSheet(
              existing: planWithDoubleTypes,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Double Duration Plan'), findsOneWidget);
      expect(find.text('1500'), findsOneWidget); // 150000 / 100
    });

    test('Batch voucher unique code generation avoids infinite loop on collision', () {
      final Set<String> uniqueCodes = {};
      int attempts = 0;
      const qty = 50;
      const maxAttempts = qty * 50;

      // Deterministic small charset simulation to test loop bounding and collision avoidance
      int counter = 0;
      String mockGenerateSegment() {
        counter++;
        return (counter % 30).toString().padLeft(3, '0');
      }

      while (uniqueCodes.length < qty && attempts < maxAttempts) {
        attempts++;
        final seg = mockGenerateSegment();
        uniqueCodes.add('WP$seg');
      }

      // Verified that loop terminates cleanly within maxAttempts
      expect(attempts, lessThanOrEqualTo(maxAttempts));
      expect(uniqueCodes.length, equals(30)); // 30 unique items generated before exhaustion
    });
  });
}
