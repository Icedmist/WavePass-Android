import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/core/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdateService.isNewerVersion semver comparison', () {
    test('detects patch bump as newer', () {
      expect(AppUpdateService.isNewerVersion('1.0.2', '1.0.1'), isTrue);
      expect(AppUpdateService.isNewerVersion('v1.0.2', '1.0.1'), isTrue);
    });

    test('detects minor bump as newer', () {
      expect(AppUpdateService.isNewerVersion('1.1.0', '1.0.9'), isTrue);
    });

    test('detects major bump as newer', () {
      expect(AppUpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('detects build number bump with equal semver', () {
      expect(AppUpdateService.isNewerVersion('1.0.1+3', '1.0.1+2'), isTrue);
    });

    test('returns false when latest is equal or older', () {
      expect(AppUpdateService.isNewerVersion('1.0.1', '1.0.1'), isFalse);
      expect(AppUpdateService.isNewerVersion('1.0.1+2', '1.0.1+2'), isFalse);
      expect(AppUpdateService.isNewerVersion('1.0.0', '1.0.1'), isFalse);
      expect(AppUpdateService.isNewerVersion('1.0.1+1', '1.0.1+2'), isFalse);
    });
  });

  group('AppUpdateService.checkForUpdate API handling', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('parses newer release and extracts apk download url', () async {
      final mockResponse = jsonEncode({
        'tag_name': 'v2.0.0',
        'body': 'Paystack wallet cashout OTP fix and router resilience.',
        'html_url': 'https://github.com/Icedmist/WavePass-Android/releases/tag/v2.0.0',
        'published_at': '2026-09-30T00:00:00Z',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://github.com/Icedmist/WavePass-Android/releases/download/v2.0.0/app-release.apk',
            'size': 25000000,
          },
          {
            'name': 'app-release.aab',
            'browser_download_url': 'https://github.com/Icedmist/WavePass-Android/releases/download/v2.0.0/app-release.aab',
            'size': 18000000,
          },
        ],
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/releases/latest')) {
          return http.Response(mockResponse, 200);
        }
        return http.Response('Not found', 404);
      });

      final service = AppUpdateService.instance;
      service.mockClient = mockClient;

      final update = await service.checkForUpdate(force: true);

      expect(update.hasUpdate, isTrue);
      expect(update.latestVersion, equals('2.0.0'));
      expect(update.downloadUrl, equals('https://github.com/Icedmist/WavePass-Android/releases/download/v2.0.0/app-release.apk'));
      expect(update.releaseNotes, contains('Paystack wallet'));
      expect(update.assetSizeBytes, equals(25000000));
    });

    test('returns hasUpdate false when release matches current version', () async {
      final mockResponse = jsonEncode({
        'tag_name': 'v${AppUpdateService.currentVersion}',
        'body': 'Current release',
        'assets': [],
      });

      final mockClient = MockClient((request) async {
        return http.Response(mockResponse, 200);
      });

      final service = AppUpdateService.instance;
      service.mockClient = mockClient;

      final update = await service.checkForUpdate(force: true);

      expect(update.hasUpdate, isFalse);
    });

    test('handles network failure gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = AppUpdateService.instance;
      service.mockClient = mockClient;

      final update = await service.checkForUpdate(force: true);

      expect(update.hasUpdate, isFalse);
    });

    test('prioritizes backend API version endpoint when available', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/api/v1/app/version')) {
          return http.Response(
            jsonEncode({
              'version': '1.0.3',
              'downloadUrl': 'https://api.nexawavepass.com/api/v1/app/download',
              'releaseNotes': 'Backend server announced update.',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = AppUpdateService.instance;
      service.mockClient = mockClient;

      final update = await service.checkForUpdate(force: true);

      expect(update.hasUpdate, isTrue);
      expect(update.latestVersion, equals('1.0.3'));
      expect(update.downloadUrl, equals('https://api.nexawavepass.com/api/v1/app/download'));
      expect(update.releaseNotes, equals('Backend server announced update.'));
    });

    test('falls back to WavePass-App distribution repo if backend fails', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/api/v1/app/version')) {
          return http.Response('Internal error', 500);
        }
        if (request.url.path.contains('/WavePass-App/releases/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.0.4',
              'body': 'Public distribution release.',
              'assets': [
                {
                  'name': 'app-release.apk',
                  'browser_download_url': 'https://github.com/Icedmist/WavePass-App/releases/download/v1.0.4/app-release.apk',
                  'size': 26000000,
                }
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = AppUpdateService.instance;
      service.mockClient = mockClient;

      final update = await service.checkForUpdate(force: true);

      expect(update.hasUpdate, isTrue);
      expect(update.latestVersion, equals('1.0.4'));
      expect(update.downloadUrl, contains('WavePass-App'));
      expect(update.releaseNotes, equals('Public distribution release.'));
    });
  });
}
