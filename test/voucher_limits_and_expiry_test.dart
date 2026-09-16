import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/core/services/router_discovery_service.dart';
import 'package:wavepass_mobile/core/services/voucher_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Duration & Profile Mapping Tests', () {
    test('profileForDuration maps durations correctly to profile tiers', () {
      expect(RouterDiscoveryService.profileForDuration(900), 'profile_30m');
      expect(RouterDiscoveryService.profileForDuration(1800), 'profile_30m');
      expect(RouterDiscoveryService.profileForDuration(3600), 'profile_1h');
      expect(RouterDiscoveryService.profileForDuration(7200), 'profile_2h');
      expect(RouterDiscoveryService.profileForDuration(10800), 'profile_3h');
      expect(RouterDiscoveryService.profileForDuration(21600), 'profile_6h');
      expect(RouterDiscoveryService.profileForDuration(43200), 'profile_12h');
      expect(RouterDiscoveryService.profileForDuration(86400), 'profile_1d');
      expect(RouterDiscoveryService.profileForDuration(604800), 'profile_7d');
      expect(RouterDiscoveryService.profileForDuration(2592000), 'profile_30d');
    });

    test('formatRouterOsDuration produces valid RouterOS time strings', () {
      expect(RouterDiscoveryService.formatRouterOsDuration(0), '0s');
      expect(RouterDiscoveryService.formatRouterOsDuration(1800), '30m');
      expect(RouterDiscoveryService.formatRouterOsDuration(3600), '1h');
      expect(RouterDiscoveryService.formatRouterOsDuration(7200), '2h');
      expect(RouterDiscoveryService.formatRouterOsDuration(43200), '12h');
      expect(RouterDiscoveryService.formatRouterOsDuration(86400), '1d');
      expect(RouterDiscoveryService.formatRouterOsDuration(604800), '7d');
      expect(RouterDiscoveryService.formatRouterOsDuration(90), '1m30s');
      expect(RouterDiscoveryService.formatRouterOsDuration(3665), '1h1m5s');
    });

    test('standardDurationProfiles configures hard timeouts and keepalives for all tiers', () {
      final profiles = RouterDiscoveryService.standardDurationProfiles;
      expect(profiles.length, 10);

      for (final p in profiles) {
        expect(p['shared-users'], '1');
        expect(p['keepalive-timeout'], '2m');
        expect(p['idle-timeout'], isNotNull);
        expect(p['status-autorefresh'], '1m');
        expect(p['session-timeout'], isNotNull);
        expect(p['rate-limit'], isNotNull);
      }

      expect(profiles.firstWhere((p) => p['name'] == 'profile_1h')['session-timeout'], '1h');
      expect(profiles.firstWhere((p) => p['name'] == 'profile_12h')['session-timeout'], '12h');
      expect(profiles.firstWhere((p) => p['name'] == 'profile_1d')['session-timeout'], '1d');
      expect(profiles.firstWhere((p) => p['name'] == 'wp-payment-trial')['session-timeout'], '2m');
    });
  });

  group('RouterOS Uptime Parsing Tests', () {
    test('parseRouterOsUptimeSeconds accurately parses various RouterOS time formats', () {
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds('00:00:00'), 0);
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds('00:15:30'), 930);
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds('01:00:00'), 3600);
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds('12:34:56'), 12 * 3600 + 34 * 60 + 56);
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds('1d02:30:00'), 86400 + 7200 + 1800);
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds('1h30m'), 5400);
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds('45s'), 45);
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds('12m'), 720);
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds('2d4h'), 2 * 86400 + 4 * 3600);
      expect(VoucherHistoryService.parseRouterOsUptimeSeconds(''), 0);
    });
  });

  group('Voucher Lifecycle & History Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('recordVoucher stores voucher with duration and status', () async {
      final service = VoucherHistoryService.instance;
      await service.recordVoucher(
        code: 'WP-TEST1',
        planTitle: '1 Hour Pass',
        price: '₦200',
        durationSeconds: 3600,
        directMode: 'local',
      );

      final history = await service.getHistory();
      expect(history.length, 1);
      final v = history.first;
      expect(v.code, 'WP-TEST1');
      expect(v.planTitle, '1 Hour Pass');
      expect(v.price, '₦200');
      expect(v.durationSeconds, 3600);
      expect(v.status, 'unused');
      expect(v.directMode, 'local');
    });

    test('expireVoucher marks voucher status as expired', () async {
      final service = VoucherHistoryService.instance;
      await service.recordVoucher(
        code: 'WP-EXPIRE-ME',
        planTitle: '12 Hour Pass',
        price: '₦500',
        durationSeconds: 43200,
      );

      await service.expireVoucher('WP-EXPIRE-ME');
      final history = await service.getHistory();
      final v = history.firstWhere((item) => item.code == 'WP-EXPIRE-ME');
      expect(v.status, 'expired');
    });

    test('VoucherRecord supports dual credentials, serialization, and telemetry formatting', () {
      final record = VoucherRecord(
        code: 'WP-USER100',
        password: 'PIN-9876',
        planTitle: 'Daily Pass',
        price: '₦500',
        durationSeconds: 86400,
        createdAt: DateTime.now(),
        status: 'in_use',
        uptime: '02:30:00',
        bytesIn: 52428800, // 50 MB
        bytesOut: 104857600, // 100 MB
        source: 'batch',
      );

      expect(record.isDualCredential, isTrue);
      expect(record.effectivePassword, 'PIN-9876');
      expect(record.dataTransferredFormatted, '150.0 MB');
      expect(record.uptimeFormatted, '02:30:00');

      final json = record.toJson();
      expect(json['code'], 'WP-USER100');
      expect(json['password'], 'PIN-9876');
      expect(json['source'], 'batch');

      final restored = VoucherRecord.fromJson(json);
      expect(restored.code, 'WP-USER100');
      expect(restored.password, 'PIN-9876');
      expect(restored.isDualCredential, isTrue);
      expect(restored.bytesIn, 52428800);
      expect(restored.bytesOut, 104857600);
      expect(restored.dataTransferredFormatted, '150.0 MB');
    });

    test('recordVoucher stores password and custom source', () async {
      final service = VoucherHistoryService.instance;
      await service.recordVoucher(
        code: 'WP-DUAL-1',
        password: 'SECRET-PIN',
        planTitle: 'VIP Pass',
        price: '₦1000',
        durationSeconds: 86400,
        source: 'pos',
      );

      final history = await service.getHistory();
      final v = history.firstWhere((item) => item.code == 'WP-DUAL-1');
      expect(v.isDualCredential, isTrue);
      expect(v.effectivePassword, 'SECRET-PIN');
      expect(v.source, 'pos');
    });

    test('fetchFullVoucherActivity merges and returns consolidated records', () async {
      final service = VoucherHistoryService.instance;
      await service.recordVoucher(
        code: 'WP-HIST-1',
        planTitle: 'Basic Pass',
        price: '₦100',
        durationSeconds: 3600,
      );

      final activity = await service.fetchFullVoucherActivity();
      expect(activity.isNotEmpty, isTrue);
      expect(activity.any((v) => v.code == 'WP-HIST-1'), isTrue);
    });
  });
}
