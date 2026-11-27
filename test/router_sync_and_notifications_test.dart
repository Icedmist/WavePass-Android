import 'package:flutter_test/flutter_test.dart';
import 'package:wavepass_mobile/core/services/notification_service.dart';
import 'package:wavepass_mobile/core/services/router_discovery_service.dart';

void main() {
  group('Cloud Voucher Sync & Auto-Rejoin RouterOS Scripts', () {
    test('buildCloudSyncScript targets api.nexawavepass.com router-sync endpoint with venueId and slug', () {
      final script = RouterDiscoveryService.buildCloudSyncScript(
        venueSlug: 'nexa-cafe',
        venueId: 'venue-uuid-123',
      );
      expect(script, contains('https://api.nexawavepass.com/api/v1/portal/router-sync?venueId=venue-uuid-123&venueSlug=nexa-cafe'));
      expect(script, contains('/tool fetch'));
      expect(script, contains('/import file-name=wp_sync.rsc'));
      expect(script, contains('/file remove wp_sync.rsc'));
    });

    test('onLoginScript and cleanupScriptSource share WP: prefix and guard non-WavePass bindings', () {
      expect(RouterDiscoveryService.onLoginScript, contains('type=bypassed comment=("WP:" . \$u)'));
      expect(RouterDiscoveryService.cleanupScriptSource, contains('[:pick \$bc 0 3] = "WP:"'));
      expect(RouterDiscoveryService.cleanupScriptSource, contains('[:pick \$bc 3 [:len \$bc]]'));
    });
  });

  group('AppNotifier remote notification processing', () {
    test('handles PAYMENT, VOUCHER, SYSTEM, and approval records while respecting read state and deduplication', () {
      final notifier = AppNotifier.instance;
      final beforeCount = notifier.feed.value.length;
      final ts = DateTime.now().microsecondsSinceEpoch;

      notifier.processRemoteNotification(
        {
          'id': 'test-sys-$ts',
          'type': 'SYSTEM',
          'title': 'Provisioning delayed',
          'body': 'Router will sync in 1m',
          'read': false,
        },
        'venue-test-1',
        showBar: false,
        showModal: false,
      );

      notifier.processRemoteNotification(
        {
          'id': 'test-read-$ts',
          'type': 'PAYMENT',
          'title': 'Old payment',
          'body': 'Already read',
          'read': true,
        },
        'venue-test-1',
        showBar: false,
        showModal: false,
      );

      // Duplicate ID must be ignored
      notifier.processRemoteNotification(
        {
          'id': 'test-sys-$ts',
          'type': 'SYSTEM',
          'title': 'Provisioning delayed duplicate',
          'body': 'Should not be added twice',
          'read': false,
        },
        'venue-test-1',
        showBar: false,
        showModal: false,
      );

      final added = notifier.feed.value.take(notifier.feed.value.length - beforeCount).toList();
      expect(added.length, 2);

      final sysNotif = added.firstWhere((n) => n.id == 'test-sys-$ts');
      expect(sysNotif.type, NotifyType.warning);
      expect(sysNotif.read, isFalse);

      final readNotif = added.firstWhere((n) => n.id == 'test-read-$ts');
      expect(readNotif.type, NotifyType.success);
      expect(readNotif.read, isTrue);
    });
  });
}
