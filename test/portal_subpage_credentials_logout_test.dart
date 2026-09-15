import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/core/services/activation_code_service.dart';
import 'package:wavepass_mobile/core/services/venue_state_service.dart';
import 'package:wavepass_mobile/screens/router_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VenueStateService & ActivationCodeService Logout Purge Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('clearVenue wipes in-memory state and all shared preferences keys', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(VenueStateService.keyVenueId, 'v-123');
      await prefs.setString(VenueStateService.keyVenueName, 'Test Cafe');
      await prefs.setString(VenueStateService.keyVenueSlug, 'test-cafe');

      final service = VenueStateService.instance;
      service.venueNotifier.value = {
        'id': 'v-123',
        'name': 'Test Cafe',
        'slug': 'test-cafe',
      };
      expect(service.currentVenueId, equals('v-123'));

      await service.clearVenue();

      expect(service.currentVenue, isNull);
      expect(service.currentVenueId, isNull);
      expect(prefs.getString(VenueStateService.keyVenueId), isNull);
      expect(prefs.getString(VenueStateService.keyVenueName), isNull);
      expect(prefs.getString(VenueStateService.keyVenueSlug), isNull);
    });

    test('ActivationCodeService clearCache wipes activation locks on logout', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wavepass_venue_activated_operator@example.com', true);
      await prefs.setString('wavepass_venue_activation_code_operator@example.com', 'WP-ACT-1234');

      final service = ActivationCodeService.instance;
      expect(await service.isAccountActivated('operator@example.com'), isTrue);

      await service.clearCache('operator@example.com');

      expect(await service.isAccountActivated('operator@example.com'), isFalse);
      expect(await service.getActivatedCode('operator@example.com'), isNull);
    });

    test('refreshVenue does not auto-bind to primary venue when logged out and allowFallback is false', () async {
      final service = VenueStateService.instance;
      await service.clearVenue();

      final result = await service.refreshVenue(allowFallbackToPrimary: false);
      expect(result, isNull);
      expect(service.currentVenue, isNull);
    });
  });

  group('Captive Portal Suite & Venue Subpage Integration Tests', () {
    test('Generated login.html contains venue subpage, dual credential tabs, and pure-JS MD5 CHAP logic', () {
      final html = RouterSetupScreen.generateLoginHtml('Apex Lounge', 'apex-lounge');

      // 1. Venue Hosted Subpage Integration
      expect(html, contains('https://apex-lounge.nexawavepass.com/portal'));
      expect(html, contains('Launch Venue Portal'));
      expect(html, contains('Visiting Apex Lounge?'));

      // 2. Segmented Dual Credential Tabs
      expect(html, contains('id="tabVoucher"'));
      expect(html, contains('id="tabCreds"'));
      expect(html, contains('Voucher Code'));
      expect(html, contains('Username / Phone Number'));
      expect(html, contains('Password / PIN'));

      // 3. Pure-JS RFC 1321 MD5 & CHAP challenge response
      expect(html, contains('function hexMD5('));
      expect(html, contains(r'var chapId = "$(chap-id)";'));
      expect(html, contains(r'var chapChallenge = "$(chap-challenge)";'));
      expect(html, contains('hexMD5(chapId + p + chapChallenge)'));

      // 4. RouterOS Form
      expect(html, contains(r'action="$(link-login-only)"'));
      expect(html, contains(r'name="sendin"'));
    });
  });
}
