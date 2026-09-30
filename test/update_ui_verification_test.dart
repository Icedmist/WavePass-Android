import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/core/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget createTestWidget({required Widget child}) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  testWidgets('Check for Updates component triggers update check and displays update dialog', (WidgetTester tester) async {
    final mockRelease = jsonEncode({
      'tag_name': 'v1.0.2',
      'body': 'Brand new router diagnostics & offline recovery.',
      'html_url': 'https://github.com/Icedmist/WavePass-Android/releases/tag/v1.0.2',
      'published_at': '2026-09-30T00:00:00Z',
      'assets': [
        {
          'name': 'app-release.apk',
          'browser_download_url': 'https://github.com/Icedmist/WavePass-Android/releases/download/v1.0.2/app-release.apk',
          'size': 25000000,
        }
      ],
    });

    AppUpdateService.instance.mockClient = MockClient((request) async {
      return http.Response(mockRelease, 200, headers: {'content-type': 'application/json'});
    });

    await tester.pumpWidget(
      createTestWidget(
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                final update = await AppUpdateService.instance.checkForUpdate(force: true);
                if (update.hasUpdate && context.mounted) {
                  AppUpdateService.instance.showUpdateDialog(context, update);
                }
              },
              child: const Text('Check for Updates'),
            );
          },
        ),
      ),
    );

    // Verify component is rendered
    expect(find.text('Check for Updates'), findsOneWidget);

    // Tap component
    await tester.tap(find.text('Check for Updates'));
    await tester.pumpAndSettle();

    // Verify update dialog appears with release details
    expect(find.text('Update Available'), findsOneWidget);
    expect(find.text('What\'s New:'), findsOneWidget);
    expect(find.text('Brand new router diagnostics & offline recovery.'), findsOneWidget);
    expect(find.text('Update Now'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);

    // Tap Later to dismiss
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsNothing);
  });

  testWidgets('Check for Updates component reports up to date when no newer version exists', (WidgetTester tester) async {
    final mockRelease = jsonEncode({
      'tag_name': 'v1.0.1+2',
      'body': 'Current release notes.',
      'assets': [],
    });

    AppUpdateService.instance.mockClient = MockClient((request) async {
      return http.Response(mockRelease, 200, headers: {'content-type': 'application/json'});
    });

    bool upToDateCalled = false;

    await tester.pumpWidget(
      createTestWidget(
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                final update = await AppUpdateService.instance.checkForUpdate(force: true);
                if (!update.hasUpdate) {
                  upToDateCalled = true;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('WavePass is up to date (v${AppUpdateService.currentVersion})')),
                  );
                }
              },
              child: const Text('Check for Updates'),
            );
          },
        ),
      ),
    );

    // Tap component
    await tester.tap(find.text('Check for Updates'));
    await tester.pumpAndSettle();

    expect(upToDateCalled, isTrue);
    expect(find.text('WavePass is up to date (v1.0.1+2)'), findsOneWidget);
    expect(find.text('Update Available'), findsNothing);
  });
}
