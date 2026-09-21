import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/core/services/venue_state_service.dart';
import 'package:wavepass_mobile/core/widgets/graceful_error_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Venue Creation, Subdomain Disabling & Plan Self-Healing Tests (#120)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('createVenue auto-generates collision-free internal slug without requiring user input', () async {
      final service = VenueStateService.instance;
      await service.clearVenue();

      final venue = await service.createVenue(name: 'Mama Put Lagos');
      expect(venue, isNotNull);
      expect(venue['name'], equals('Mama Put Lagos'));
      expect(venue['slug'], isNotNull);
      // Auto-generated slug format: v-<timestamp>-<hash>
      expect(venue['slug'].toString().startsWith('v-'), isTrue);

      expect(service.currentVenue, isNotNull);
      expect(service.currentVenueId, equals(venue['id']));
      expect(service.currentVenueName, equals('Mama Put Lagos'));
    });

    test('checkSlugAvailability is permanently bypassed and always available', () async {
      final service = VenueStateService.instance;
      final res1 = await service.checkSlugAvailability('taken-slug');
      expect(res1['available'], isTrue);
      expect(res1['isCurrent'], isTrue);

      final res2 = await service.checkSlugAvailability('any-custom-slug');
      expect(res2['available'], isTrue);
      expect(res2['isCurrent'], isTrue);
    });

    test('updateVenue updates venue name and retains/auto-generates slug without user input', () async {
      final service = VenueStateService.instance;
      await service.createVenue(name: 'Initial Name');
      final originalSlug = service.currentVenueSlug;

      await service.updateVenue(name: 'Renamed Lounge');
      expect(service.currentVenueName, equals('Renamed Lounge'));
      expect(service.currentVenueSlug, equals(originalSlug));
    });

    test('createPlan self-heals when currentVenueId is null by provisioning default venue', () async {
      final service = VenueStateService.instance;
      await service.clearVenue();
      expect(service.currentVenueId, isNull);

      // In previous versions, this threw Exception('Cannot create plan: no active venue found.')
      // Now, it self-heals by initializing/provisioning a venue and successfully creating the plan offline
      final plan = await service.createPlan({
        'name': '1 Hour Fast Pass',
        'priceMinor': 50000,
        'durationSeconds': 3600,
      });

      expect(plan, isNotNull);
      expect(plan['name'], equals('1 Hour Fast Pass'));
      expect(plan['priceMinor'], equals(50000));
      expect(plan['durationSeconds'], equals(3600));
      expect(service.currentVenueId, isNotNull);
      expect(service.currentPlans.any((p) => p['name'] == '1 Hour Fast Pass'), isTrue);
    });

    testWidgets('buildGracefulErrorWidget displays soft recovery card instead of red screen', (tester) async {
      final errorWidget = buildGracefulErrorWidget(
        FlutterErrorDetails(
          exception: Exception('Test layout exception'),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: errorWidget),
      ));

      expect(find.text('Something temporarily interrupted this view'), findsOneWidget);
      expect(find.textContaining('Test layout exception'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    });
  });
}
