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
    test('Generated login.html defaults to full on-router standalone portal card with voucher redemption and Paystack', () {
      final html = RouterSetupScreen.generateLoginHtml('Apex Lounge', 'apex-lounge');

      // 1. Venue Hosted Subpage Integration
      expect(html, contains('https://apex-lounge.nexawavepass.com/portal'));
      expect(html, contains('Launch Venue Portal'));
      expect(html, contains('Visiting Apex Lounge?'));

      // 2. Segmented Credential and Plan Tabs
      expect(html, contains('id="tabVoucher"'));
      expect(html, contains('id="tabPlans"'));
      expect(html, contains('id="tabCreds"'));
      expect(html, contains('Voucher Code'));
      expect(html, contains('Buy Pass'));
      expect(html, contains('Username / Phone Number'));
      expect(html, contains('Password / PIN'));

      // 3. Venue Plans & Paystack Integration
      expect(html, contains('id="panelPlans"'));
      expect(html, contains('id="pay_email"'));
      expect(html, contains('payWithPaystack'));
      expect(html, contains('https://api.nexawavepass.com/api/v1/portal/init-payment'));

      // 4. Pure-JS RFC 1321 MD5 & CHAP challenge response
      expect(html, contains('function hexMD5('));
      expect(html, contains(r'var chapId = "$(chap-id)";'));
      expect(html, contains(r'var chapChallenge = "$(chap-challenge)";'));
      expect(html, contains('hexMD5(chapId + p + chapChallenge)'));

      // 5. RouterOS Form
      expect(html, contains(r'action="$(link-login-only)"'));
      expect(html, contains(r'name="sendin"'));
    });

    test('Hosted mode login.html generates instant hosted subdomain redirector with offline fail-safe', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'Apex Lounge',
        'apex-lounge',
        null,
        true,
        true, // useHostedSubdomainPortal = true
      );

      // 1. Instant 0-second redirect to venue subdomain with device & CHAP parameters
      expect(html, contains('https://apex-lounge.nexawavepass.com/portal'));
      expect(html, contains('<meta http-equiv="refresh" content="0; url=https://apex-lounge.nexawavepass.com/portal'));
      expect(html, contains(r'mac=$(mac)'));
      expect(html, contains(r'ip=$(ip)'));
      expect(html, contains(r'link-login=$(link-login-only)'));
      expect(html, contains(r'chap-id=$(chap-id)'));
      expect(html, contains(r'chap-challenge=$(chap-challenge)'));
      expect(html, contains('window.location.replace(portalUrl)'));

      // 2. Offline fail-safe form
      expect(html, contains('id="offlineFallback"'));
      expect(html, contains(r'action="$(link-login-only)"'));
      expect(html, contains('placeholder="e.g. 123456"'));
      expect(html, contains('setTimeout('));

      // 3. Programmatic on-box execution for query credentials
      expect(html, contains(r'form name="sendin"'));
      expect(html, contains('executeLogin('));
      expect(html, contains('hexMD5('));
    });

    test('Standalone mode login.html renders custom venue plans dynamically', () {
      final customPlans = [
        {
          'id': 'plan_vip_day',
          'name': 'VIP All-Day Pass',
          'price': 1500,
          'durationMinutes': 1440,
        },
        {
          'id': 'plan_weekly',
          'name': '7-Day Unlimited',
          'price': 5000,
          'duration': '7 Days',
        },
      ];

      final html = RouterSetupScreen.generateLoginHtml(
        'Apex Lounge',
        'apex-lounge',
        customPlans,
        true,
        false, // standalone
      );

      expect(html, contains('VIP All-Day Pass'));
      expect(html, contains('₦1500'));
      expect(html, contains('7-Day Unlimited'));
      expect(html, contains('₦5000'));
      expect(html, contains("payWithPaystack('plan_vip_day', '₦1500')"));
      expect(html, contains("payWithPaystack('plan_weekly', '₦5000')"));
      expect(html, contains('Paystack Online'));
      expect(html, contains('Need Internet to Pay?'));
      expect(html, contains(r'username=T-$(mac-esc)'));
      expect(html, contains('placeholder="e.g. 123456"'));
    });

    test('Standalone mode login.html displays Paystack Not Available when unconfigured', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'Apex Lounge',
        'apex-lounge',
        null,
        false, // isPaystackConfigured = false
        false, // standalone
      );

      expect(html, contains('Paystack Not Available'));
      expect(html, contains('Online card/transfer payments are currently unavailable at this venue'));
      expect(html, contains('class="btn-pay disabled"'));
      expect(html, contains('disabled title="Paystack not available"'));
      expect(html, contains('Need Internet to Pay?'));
    });

    test('Captive portal suite caches active voucher credentials and provides 1-tap reconnect', () {
      final hostedHtml = RouterSetupScreen.generateLoginHtml('Apex Lounge', 'apex-lounge', null, true, true);
      expect(hostedHtml, contains("localStorage.setItem('wp-active-voucher'"));
      expect(hostedHtml, contains("localStorage.getItem('wp-active-voucher')"));
      expect(hostedHtml, contains('btn_offline_connect'));

      final standaloneHtml = RouterSetupScreen.generateLoginHtml('Apex Lounge', 'apex-lounge', null, true, false);
      expect(standaloneHtml, contains('savedVoucherBox'));
      expect(standaloneHtml, contains('Reconnect Active Voucher'));
      expect(standaloneHtml, contains('1-Tap Reconnect Now'));
      expect(standaloneHtml, contains("localStorage.setItem('wp-active-voucher'"));

      final statusHtml = RouterSetupScreen.generateStatusHtml('Apex Lounge', 'apex-lounge');
      expect(statusHtml, contains("localStorage.setItem('wp-active-voucher'"));
      expect(statusHtml, contains(r'var u = "$(username)";'));
    });

    test('Standalone mode login.html renders venue bank accounts and transfer access request workflow', () {
      final bankAccounts = [
        {
          'bankName': 'OPay',
          'accountNumber': '8012345678',
          'accountName': 'Apex Lounge Entertainment',
        },
        {
          'bankName': 'GTBank',
          'accountNumber': '0123456789',
          'accountName': 'Apex Lounge Ltd',
        }
      ];

      final html = RouterSetupScreen.generateLoginHtml(
        'Apex Lounge',
        'apex-lounge',
        null,
        true,
        false,
        bankAccounts,
      );

      // Tab and Panel checks
      expect(html, contains('id="tabTransfer"'));
      expect(html, contains('id="panelTransfer"'));
      expect(html, contains('Direct Bank Transfer'));

      // Bank accounts display
      expect(html, contains('OPay'));
      expect(html, contains('8012345678'));
      expect(html, contains('Apex Lounge Entertainment'));
      expect(html, contains('GTBank'));
      expect(html, contains('0123456789'));

      // Inputs and action button
      expect(html, contains('id="transfer_plan"'));
      expect(html, contains('id="transfer_sender"'));
      expect(html, contains('id="btn_transfer_completed"'));
      expect(html, contains('submitTransferPayment'));

      // Backend API Integration
      expect(html, contains('https://api.nexawavepass.com/api/v1/portal/transfer-request'));
      expect(html, contains('https://api.nexawavepass.com/api/v1/portal/retrieve-voucher'));
    });

    test('Standalone mode login.html renders voucher retrieval panel and auto-login script', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'Apex Lounge',
        'apex-lounge',
      );

      // Tab and Panel checks
      expect(html, contains('id="tabRetrieve"'));
      expect(html, contains('id="panelRetrieve"'));
      expect(html, contains('Retrieve Active Pass'));

      // Input elements
      expect(html, contains('id="retrieve_mac"'));
      expect(html, contains(r'value="$(mac)"'));
      expect(html, contains('id="retrieve_query"'));
      expect(html, contains('id="btn_retrieve"'));
      expect(html, contains('retrieveActivePass'));

      // Endpoint check
      expect(html, contains('https://api.nexawavepass.com/api/v1/portal/retrieve-voucher'));
      expect(html, contains('loadDynamicBankAccounts'));
    });
  });
}
