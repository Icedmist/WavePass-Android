import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/core/services/venue_state_service.dart';
import 'package:wavepass_mobile/core/services/router_discovery_service.dart';
import 'package:wavepass_mobile/screens/router_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Plan Retention Across Logout/Login Tests (Issue #130)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('init() immediately hydrates plans from SharedPreferences before network latency', () async {
      final samplePlans = [
        {
          'id': '6c1b9d80-4cfc-44ee-a5b2-9372b22be0a5',
          'venueId': '087e2f20-899e-419e-8af2-b8978f8cb70b',
          'name': '1day',
          'priceMinor': 30000,
          'durationSeconds': 86400,
          'rateLimit': '50M/50M',
          'active': true,
        }
      ];

      SharedPreferences.setMockInitialValues({
        VenueStateService.keyVenueId: '087e2f20-899e-419e-8af2-b8978f8cb70b',
        VenueStateService.keyVenueName: 'DAN MUSA WIFI',
        VenueStateService.keyVenueSlug: 'v-1790085427954-myve',
        VenueStateService.keyVenuePlans: jsonEncode(samplePlans),
        '${VenueStateService.keyCachedPlansPrefix}087e2f20-899e-419e-8af2-b8978f8cb70b': jsonEncode(samplePlans),
        '${VenueStateService.keyUserVenuePrefix}sahabimusa963@gmail.com': '087e2f20-899e-419e-8af2-b8978f8cb70b',
        'sb-user-email': 'sahabimusa963@gmail.com',
      });

      final service = VenueStateService.instance;
      // Pre-clear in-memory state
      service.venueNotifier.value = null;
      service.plansNotifier.value = [];

      // Calling init() should restore both venue and plans from disk cache
      await service.init();

      expect(service.currentVenue, isNotNull);
      expect(service.currentVenueId, equals('087e2f20-899e-419e-8af2-b8978f8cb70b'));
      expect(service.currentVenueName, equals('DAN MUSA WIFI'));
      expect(service.currentPlans, isNotEmpty);
      expect(service.currentPlans.length, equals(1));
      expect(service.currentPlans.first['name'], equals('1day'));
      expect(service.currentPlans.first['priceMinor'], equals(30000));
    });

    test('clearVenue(preserveUserCache: true) clears memory while preserving offline plan cache for re-login', () async {
      final samplePlans = [
        {
          'id': 'plan-test-1',
          'venueId': 'venue-test-1',
          'name': 'Hourly Pass',
          'priceMinor': 10000,
          'active': true,
        }
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(VenueStateService.keyVenueId, 'venue-test-1');
      await prefs.setString(VenueStateService.keyVenuePlans, jsonEncode(samplePlans));
      await prefs.setString('${VenueStateService.keyCachedPlansPrefix}venue-test-1', jsonEncode(samplePlans));
      await prefs.setString('${VenueStateService.keyUserVenuePrefix}operator@example.com', 'venue-test-1');
      await prefs.setString('sb-user-email', 'operator@example.com');

      final service = VenueStateService.instance;
      service.venueNotifier.value = {'id': 'venue-test-1', 'name': 'Test Venue'};
      service.plansNotifier.value = samplePlans;

      // Operator logs out:
      await service.clearVenue(preserveUserCache: true);

      // In-memory state is cleared immediately for security
      expect(service.currentVenue, isNull);
      expect(service.currentPlans, isEmpty);

      // But disk mapping for the operator survives logout
      expect(prefs.getString('${VenueStateService.keyUserVenuePrefix}operator@example.com'), equals('venue-test-1'));
      expect(prefs.getString('${VenueStateService.keyCachedPlansPrefix}venue-test-1'), isNotNull);

      // Operator logs back in with the same email:
      await prefs.setString('sb-user-email', 'operator@example.com');
      await service.refreshVenue();

      // Venue and plans are immediately hydrated from cache!
      expect(service.currentVenueId, equals('venue-test-1'));
      expect(service.currentPlans, isNotEmpty);
      expect(service.currentPlans.first['name'], equals('Hourly Pass'));
    });

    test('clearVenue(preserveUserCache: false) completely purges all caches on account switch', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(VenueStateService.keyVenueId, 'venue-old');
      await prefs.setString(VenueStateService.keyVenuePlans, jsonEncode([{'name': 'Old Plan'}]));

      final service = VenueStateService.instance;
      await service.clearVenue(preserveUserCache: false);

      expect(service.currentVenue, isNull);
      expect(service.currentPlans, isEmpty);
      expect(prefs.getString(VenueStateService.keyVenuePlans), isNull);
    });

    test('createPlan, updatePlan, and deletePlan update SharedPreferences plan cache', () async {
      final service = VenueStateService.instance;
      await service.clearVenue();
      final venue = await service.createVenue(name: 'Auto-Cache Venue');
      final vid = venue['id'].toString();

      final newPlan = await service.createPlan({
        'name': 'Test Persistence Pass',
        'priceMinor': 25000,
        'durationSeconds': 3600,
      });

      final prefs = await SharedPreferences.getInstance();
      final cachedRaw = prefs.getString('${VenueStateService.keyCachedPlansPrefix}$vid');
      expect(cachedRaw, isNotNull);
      final decoded = jsonDecode(cachedRaw!) as List;
      expect(decoded.any((p) => p['name'] == 'Test Persistence Pass'), isTrue);

      // Test update
      await service.updatePlan(newPlan['id'].toString(), {'name': 'Updated Pass'});
      final updatedRaw = prefs.getString('${VenueStateService.keyCachedPlansPrefix}$vid');
      expect(updatedRaw, isNotNull);
      expect(updatedRaw!.contains('Updated Pass'), isTrue);

      // Test delete
      await service.deletePlan(newPlan['id'].toString());
      final deletedRaw = prefs.getString('${VenueStateService.keyCachedPlansPrefix}$vid');
      expect(deletedRaw, isNotNull);
      expect(deletedRaw!.contains('Updated Pass'), isFalse);
    });
  });

  group('Captive Portal Auto-Connect Tests (Issue #130)', () {
    test('generateLoginHtml builds autoUrl with BOTH &mac= and &q= without suppressing saved voucher', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'DAN MUSA WIFI',
        'v-1790085427954-myve',
        [],
        true,
        false,
        null,
        'onyx',
        null,
        null,
        '087e2f20-899e-419e-8af2-b8978f8cb70b',
      );

      // Verify URL construction sends both &mac= and &q=
      expect(html.contains("if (devMac) autoUrl += '&mac=' + encodeURIComponent(devMac);"), isTrue);
      expect(html.contains("if (savedV) autoUrl += '&q=' + encodeURIComponent(savedV);"), isTrue);
      // Ensure the old 'else if (savedV)' bug that starved saved vouchers on MikroTik is eliminated
      expect(html.contains("else if (savedV) autoUrl += '&q='"), isFalse);
    });

    test('generateLoginHtml includes RouterOS error detection and loop guard without wiping saved voucher', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'Test Venue',
        'test-slug',
      );

      // Verify that RouterOS error message (.error-msg) clears attempt flags to prevent infinite submit loops
      // but PRESERVES the saved voucher in localStorage for 1-tap reconnect
      expect(html.contains("var errEl = document.querySelector('.error-msg');"), isTrue);
      expect(html.contains("var hasError = errEl && errEl.innerText && errEl.innerText.trim().length > 0;"), isTrue);
      expect(html.contains("sessionStorage.removeItem('wp-auto-attempt');"), isTrue);
      expect(html.contains("setTimeout(function() { controller.abort(); }, 4500)"), isTrue);
      expect(html.contains("doFetch(attempt + 1);"), isTrue);
    });

    test('generateLoginHtml provides offline captive portal fallback to executeLogin with saved voucher', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'Test Venue',
        'test-slug',
      );

      // Verify offline/captive portal fallback exists when fetch fails before network is authenticated
      expect(html.contains("if (savedV) {"), isTrue);
      expect(html.contains("executeLogin(savedV, savedV);"), isTrue);
      expect(html.contains("executeLogin(savedU, savedP);"), isTrue);
    });

    test('generateLoginHtml renders 1-tap reconnect box with savedVoucherBox', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'DAN MUSA WIFI',
        'dan-musa-wifi',
      );

      expect(html.contains('id="savedVoucherBox"'), isTrue);
      expect(html.contains('id="savedVoucherCode"'), isTrue);
      expect(html.contains('1-Tap Reconnect Now'), isTrue);
    });

    test('generateLoginHtml prioritizes data.authorization_url and stores pending reference for captive portal', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'Nexa WavePass',
        'flagship',
      );

      // Verify that authorization_url auto-grants payment trial for captive clients before navigating to checkout
      expect(html.contains("localStorage.setItem('wp_pending_ref', data.reference);"), isTrue);
      expect(html.contains("recordTrialStart();"), isTrue);
      expect(html.contains("wp-payment-trial"), isTrue);
      expect(html.contains("window.location.href = data.authorization_url;"), isTrue);
      // Verify DOMContentLoaded auto-retrieves payment reference on return
      expect(html.contains("var ref = params.get('reference') || params.get('trxref') || params.get('ref');"), isTrue);
      expect(html.contains("wp_pending_ref"), isTrue);
      expect(html.contains("retrieve-voucher?reference="), isTrue);
    });
  });

  group('Venue & Plan Persistence Across Logout / Update Tests (Issue #150)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('VenueStateService preserves and hydrates plans via keyLastKnownVenueId', () async {
      final samplePlans = [
        {
          'id': 'plan-flagship-1',
          'venueId': 'venue-flagship-1',
          'name': 'Custom Pass',
          'priceMinor': 20000,
          'durationSeconds': 1800,
          'active': true,
        },
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(VenueStateService.keyLastKnownVenueId, 'venue-flagship-1');
      await prefs.setString('${VenueStateService.keyCachedPlansPrefix}venue-flagship-1', jsonEncode(samplePlans));
      await prefs.setString(VenueStateService.keyVenuePlans, jsonEncode(samplePlans));

      final service = VenueStateService.instance;
      service.venueNotifier.value = null;
      service.plansNotifier.value = [];

      // Even if currentVenueId in memory is null and keyVenueId is not set, refreshPlans recovers using keyLastKnownVenueId
      final plans = await service.refreshPlans();
      expect(plans, isNotEmpty);
      expect(plans.first['name'], equals('Custom Pass'));
      expect(service.currentPlans, isNotEmpty);
    });
  });

  group('Issue #152: Captive Checkout Trial & Super-Admin Flagship Plans Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('login_screen preserves router credentials when same operator logs in', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sb-last-signed-in-email', 'talk2icedmist@gmail.com');
      await prefs.setString(RouterDiscoveryService.keyRouterLocalIp, '192.168.88.1');
      await prefs.setString(RouterDiscoveryService.keyRouterPassword, 'Secret#2026');

      // Simulating login check:
      final oldEmail = prefs.getString('sb-user-email') ?? prefs.getString('sb-last-signed-in-email');
      const incomingEmail = 'talk2icedmist@gmail.com';
      final isDifferentUser = oldEmail != null && oldEmail.isNotEmpty && oldEmail.toLowerCase().trim() != incomingEmail.toLowerCase().trim();

      expect(isDifferentUser, isFalse);
      expect(prefs.getString(RouterDiscoveryService.keyRouterPassword), equals('Secret#2026'));
      expect(prefs.getString(RouterDiscoveryService.keyRouterLocalIp), equals('192.168.88.1'));
    });
  });

  group('Issue #193: Resilient Portal Auto-Rejoin & Supabase Direct Query Tests', () {
    test('generateLoginHtml performs instant local auto-rejoin when saved voucher exists', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'Apex Lounge',
        'apex-lounge',
        [],
        true,
        false,
        null,
        'onyx',
        null,
        null,
        '0e65c025-480a-4a42-8c49-68b6f0b27712',
      );

      // Verify instant local auto-login happens without hanging on external cloud timeout
      expect(html.contains('executeLogin(savedV, savedV);'), isTrue);
      expect(html.contains('executeLogin(savedU, savedP);'), isTrue);

      // Verify direct Supabase REST query fallback for MAC-only ephemeral browsers
      expect(html.contains('https://vvoenmdzavyzlisykhks.supabase.co/rest/v1/Voucher?venueId=eq.'), isTrue);
      expect(html.contains('&redeemedMac=ilike.'), isTrue);

      // Verify dead voucher cleanup on uptime limit or expiration error
      expect(html.contains("localStorage.removeItem('wp-active-voucher');"), isTrue);
      expect(html.contains("sessionStorage.removeItem('wp-active-voucher');"), isTrue);
    });
  });

  group('Issue #196: Captive Portal MAC Binding & Live Supabase Notification Sync Tests', () {
    test('generateLoginHtml binds redeemedMac and posts notification on submitVoucher', () {
      final html = RouterSetupScreen.generateLoginHtml(
        'Flagship Lounge',
        'flagship',
        [],
        true,
        false,
        null,
        'onyx',
        null,
        null,
        '9a8fa6f7-4e94-4579-84ad-cb76312af80b',
      );

      // Verify submitVoucher binds device MAC to Supabase
      expect(html.contains("fetch('https://vvoenmdzavyzlisykhks.supabase.co/rest/v1/Voucher?displayCodeEnc=eq.' + encodeURIComponent(v)"), isTrue);
      expect(html.contains("patchBody.redeemedMac = devMac;"), isTrue);
      expect(html.contains("status: 'ACTIVE'"), isTrue);

      // Verify submitVoucher pushes live notification to Supabase Notification table
      expect(html.contains("fetch('https://vvoenmdzavyzlisykhks.supabase.co/rest/v1/Notification'"), isTrue);
      expect(html.contains("type: 'VOUCHER'"), isTrue);
      expect(html.contains("reference: 'VOUCHER_IN_USE:'"), isTrue);

      // Verify auto-rejoin query includes GENERATED, ACTIVE, and REDEEMED statuses
      expect(html.contains("&status=in.(ACTIVE,REDEEMED,GENERATED)"), isTrue);

      // Verify expired error marks voucher EXPIRED in Supabase
      expect(html.contains("body: JSON.stringify({ status: 'EXPIRED'"), isTrue);
    });

    test('generateStatusHtml binds MAC and dispatches Supabase notification with venue UUID', () {
      final statusHtml = RouterSetupScreen.generateStatusHtml(
        'Flagship Lounge',
        'flagship',
        '9a8fa6f7-4e94-4579-84ad-cb76312af80b',
      );

      // Verify status.html binds voucher and device MAC
      expect(statusHtml.contains("fetch('https://vvoenmdzavyzlisykhks.supabase.co/rest/v1/Voucher?displayCodeEnc=eq.' + encodeURIComponent(u)"), isTrue);
      expect(statusHtml.contains("patchBody.redeemedMac = cleanMac;"), isTrue);
      expect(statusHtml.contains("patchBody.redeemedIp = cleanIp;"), isTrue);

      // Verify status.html pushes notification to Supabase Notification table with safe venue UUID
      expect(statusHtml.contains("fetch('https://vvoenmdzavyzlisykhks.supabase.co/rest/v1/Notification'"), isTrue);
      expect(statusHtml.contains('var venueId = "9a8fa6f7-4e94-4579-84ad-cb76312af80b";'), isTrue);
      expect(statusHtml.contains("venueId: venueId,"), isTrue);
      expect(statusHtml.contains("type: 'VOUCHER'"), isTrue);
      expect(statusHtml.contains("title: 'Pass Active: ' + u"), isTrue);
    });
  });
}
