import 'package:flutter_test/flutter_test.dart';
import 'package:wavepass_mobile/core/services/router_discovery_service.dart';
import 'package:wavepass_mobile/core/services/voucher_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Rate Limit Formatter Tests', () {
    test('converts various user input formats to valid RouterOS rate limits', () {
      expect(RouterDiscoveryService.formatRouterOsRateLimit('50mbps'), '50M/50M');
      expect(RouterDiscoveryService.formatRouterOsRateLimit('50 Mbps'), '50M/50M');
      expect(RouterDiscoveryService.formatRouterOsRateLimit('50M'), '50M/50M');
      expect(RouterDiscoveryService.formatRouterOsRateLimit('50k'), '50k/50k');
      expect(RouterDiscoveryService.formatRouterOsRateLimit('10M/5M'), '10M/5M');
      expect(RouterDiscoveryService.formatRouterOsRateLimit('10m/5m'), '10M/5M');
      expect(RouterDiscoveryService.formatRouterOsRateLimit('10 / 5'), '10M/5M');
      expect(RouterDiscoveryService.formatRouterOsRateLimit('10'), '10M/10M');
      expect(RouterDiscoveryService.formatRouterOsRateLimit(''), isNull);
      expect(RouterDiscoveryService.formatRouterOsRateLimit(null), isNull);
      expect(RouterDiscoveryService.formatRouterOsRateLimit('none'), isNull);
      expect(RouterDiscoveryService.formatRouterOsRateLimit('unlimited'), isNull);
    });
  });

  group('On-Login Script & Session Eviction Tests', () {
    test('onLoginScript evicts sessions from different devices while preserving same-device cookies', () {
      final script = RouterDiscoveryService.onLoginScript;
      expect(script, contains(r':local u "$user"; :local curMac $"mac-address";'));
      expect(script, contains(r'/ip hotspot active find user=$u'));
      expect(script, contains(r':if ([/ip hotspot active get $i mac-address] != $curMac) do={ /ip hotspot active remove $i; };'));
    });

    test('onLoginScript dynamically adds per-voucher countdown scheduler', () {
      final script = RouterDiscoveryService.onLoginScript;
      expect(script, contains(r':local sn ("exp_" . $u);'));
      expect(script, contains(r'/system scheduler add name=$sn interval=$lu'));
      expect(script, contains(r'/ip hotspot active remove [find user='));
      expect(script, contains(r'/ip hotspot user remove [find name='));
      expect(script, contains(r'/ip hotspot cookie remove [find user='));
      expect(script, contains(r'/system scheduler remove [find name='));
    });
  });

  group('Safety Cleanup Script Tests', () {
    test('cleanupScriptSource cleans active, users, schedulers, and orphan cookies', () {
      final script = RouterDiscoveryService.cleanupScriptSource;
      expect(script, contains(r':foreach a in=[/ip hotspot active find]'));
      expect(script, contains(r':foreach u in=[/ip hotspot user find]'));
      expect(script, contains(r'/ip hotspot cookie remove [find user=$un];'));
      expect(script, contains(r'/system scheduler remove [find name=("exp_" . $un)];'));
      expect(script, contains(r':foreach c in=[/ip hotspot cookie find]'));
      expect(script, contains(r':if ([:len [/ip hotspot user find name=$cu]] = 0) do={ /ip hotspot cookie remove $c; }'));
      expect(script, contains(r'/ip hotspot user remove [find comment~"expired"]'));
    });
  });

  group('Voucher Expiration & Uptime Calculation Tests', () {
    test('VoucherRecord correctly calculates isExpired and remainingSeconds', () {
      final now = DateTime.now();
      // Record used 30 minutes ago, 1 hour duration => 30 min remaining, not expired
      final activeRecord = VoucherRecord(
        code: 'WP-TEST-ACTIVE',
        planTitle: '1 Hour',
        price: '₦500',
        durationSeconds: 3600,
        createdAt: now.subtract(const Duration(minutes: 40)),
        status: 'in_use',
        usedAt: now.subtract(const Duration(minutes: 30)),
      );
      expect(activeRecord.isExpired, isFalse);
      expect(activeRecord.remainingSeconds, inInclusiveRange(1790, 1810));

      // Record used 70 minutes ago, 1 hour duration => expired
      final expiredRecord = VoucherRecord(
        code: 'WP-TEST-EXPIRED',
        planTitle: '1 Hour',
        price: '₦500',
        durationSeconds: 3600,
        createdAt: now.subtract(const Duration(minutes: 80)),
        status: 'in_use',
        usedAt: now.subtract(const Duration(minutes: 70)),
      );
      expect(expiredRecord.isExpired, isTrue);
      expect(expiredRecord.remainingSeconds, 0);

      // Unsold/unused voucher past its expiresAt => proactively expired
      final staleUnsoldRecord = VoucherRecord(
        code: 'WP-TEST-UNSOLD-EXPIRED',
        planTitle: '1 Hour',
        price: '₦500',
        durationSeconds: 3600,
        createdAt: now.subtract(const Duration(days: 31)),
        expiresAt: now.subtract(const Duration(days: 1)),
        status: 'unused',
      );
      expect(staleUnsoldRecord.isExpired, isTrue);
      expect(staleUnsoldRecord.remainingSeconds, 0);

      // Unsold/unused voucher before its expiresAt => not expired
      final validUnsoldRecord = VoucherRecord(
        code: 'WP-TEST-UNSOLD-VALID',
        planTitle: '1 Hour',
        price: '₦500',
        durationSeconds: 3600,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 30)),
        status: 'unused',
      );
      expect(validUnsoldRecord.isExpired, isFalse);
      expect(validUnsoldRecord.remainingSeconds, 3600);
    });

    test('VoucherRecord serializes and restores expiresAt and marks stale json as expired', () {
      final now = DateTime.now();
      final record = VoucherRecord(
        code: 'WP-TEST-SERIALIZE',
        planTitle: 'Daily',
        price: '₦200',
        durationSeconds: 86400,
        createdAt: now.subtract(const Duration(days: 40)),
        expiresAt: now.subtract(const Duration(days: 10)),
        status: 'unused',
      );

      final json = record.toJson();
      expect(json['expiresAt'], isNotNull);
      expect(json['status'], 'expired'); // toJson emits 'expired' when isExpired is true

      final restored = VoucherRecord.fromJson(json);
      expect(restored.expiresAt, isNotNull);
      expect(restored.status, 'expired');
      expect(restored.isExpired, isTrue);
    });
  });
}
