import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/core/services/activation_code_service.dart';
import 'package:wavepass_mobile/core/services/system_admin_service.dart';
import 'package:wavepass_mobile/core/services/voucher_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemAdminService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('isSystemAdmin correctly recognizes super admin email', () async {
      final service = SystemAdminService.instance;
      expect(await service.isSystemAdmin('talk2icedmist@gmail.com'), isTrue);
      expect(await service.isSystemAdmin('TALK2ICEDMIST@GMAIL.COM'), isTrue);
      expect(await service.isSystemAdmin('talk2icedmist@gmail.com '), isTrue);
      expect(await service.isSystemAdmin('user@example.com'), isFalse);
    });

    test('isSystemAdmin recognizes stored admin_token', () async {
      SharedPreferences.setMockInitialValues({
        'admin_token': 'secret-admin-jwt-token',
        'sb-user-email': 'otheradmin@nexawavepass.com',
      });

      final service = SystemAdminService.instance;
      expect(await service.isSystemAdmin(), isTrue);
    });

    test('isSystemAdmin returns false for regular user without token', () async {
      SharedPreferences.setMockInitialValues({
        'sb-user-email': 'regular_owner@venue.com',
      });

      final service = SystemAdminService.instance;
      expect(await service.isSystemAdmin(), isFalse);
    });
  });

  group('ActivationCodeService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('super admin account is permanently activated without code', () async {
      final service = ActivationCodeService.instance;
      expect(await service.isAccountActivated('talk2icedmist@gmail.com'), isTrue);
      expect(await service.isAccountActivated('TALK2ICEDMIST@GMAIL.COM'), isTrue);
    });

    test('regular accounts start unactivated', () async {
      final service = ActivationCodeService.instance;
      expect(await service.isAccountActivated('new_venue_owner@gmail.com'), isFalse);
    });

    test('redeeming activation code activates the account locally', () async {
      final service = ActivationCodeService.instance;
      final testEmail = 'new_venue_owner@gmail.com';

      // Initially not activated
      expect(await service.isAccountActivated(testEmail), isFalse);

      // Redeem authorized code
      final result = await service.redeemActivationCode(
        code: 'WP-ACT-TEST-0001',
        email: testEmail,
      );

      expect(result['ok'], isTrue);
      expect(await service.isAccountActivated(testEmail), isTrue);
      expect(await service.getActivatedCode(testEmail), 'WP-ACT-TEST-0001');
    });

    test('rejects empty or malformed activation codes', () async {
      final service = ActivationCodeService.instance;
      final result = await service.redeemActivationCode(
        code: '   ',
        email: 'user@test.com',
      );

      expect(result['ok'], isFalse);
      expect(result['error'], contains('Activation code is required'));
    });
  });

  group('Voucher Purge Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('purgeExpiredVouchers removes only expired vouchers from storage', () async {
      final service = VoucherHistoryService.instance;

      // Add 1 unused voucher
      await service.recordVoucher(
        code: 'WP-VALID-1',
        planTitle: '1 Hour Pass',
        price: '₦200',
        durationSeconds: 3600,
      );

      // Add another valid voucher
      await service.recordVoucher(
        code: 'WP-VALID-2',
        planTitle: '2 Hour Pass',
        price: '₦400',
        durationSeconds: 7200,
      );

      // Add 2 expired vouchers
      await service.recordVoucher(
        code: 'WP-EXPIRED-1',
        planTitle: '30 Min Pass',
        price: '₦100',
        durationSeconds: 1800,
      );
      await service.expireVoucher('WP-EXPIRED-1');

      await service.recordVoucher(
        code: 'WP-EXPIRED-2',
        planTitle: '6 Hour Pass',
        price: '₦1000',
        durationSeconds: 21600,
      );
      await service.expireVoucher('WP-EXPIRED-2');

      final beforePurge = await service.getHistory();
      expect(beforePurge.length, 4);
      expect(beforePurge.where((v) => v.status == 'expired').length, 2);

      // Execute purge
      final purgedCount = await service.purgeExpiredVouchers();
      expect(purgedCount, 2);

      final afterPurge = await service.getHistory();
      expect(afterPurge.length, 2);
      expect(afterPurge.any((v) => v.code == 'WP-EXPIRED-1'), isFalse);
      expect(afterPurge.any((v) => v.code == 'WP-EXPIRED-2'), isFalse);
      expect(afterPurge.any((v) => v.code == 'WP-VALID-1'), isTrue);
      expect(afterPurge.any((v) => v.code == 'WP-VALID-2'), isTrue);
    });
  });
}
