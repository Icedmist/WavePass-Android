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
    test('onLoginScript includes duplicate session detection and oldest session kick', () {
      final script = RouterDiscoveryService.onLoginScript;
      expect(script, contains(r'/ip hotspot active find user=$u'));
      expect(script, contains(r':if ($uc > 1) do={ /ip hotspot active remove numbers=$ka; };'));
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
    });
  });
}
