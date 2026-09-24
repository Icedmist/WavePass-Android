import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/core/services/venue_state_service.dart';
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
  });
}
