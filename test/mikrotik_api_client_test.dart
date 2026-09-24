import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavepass_mobile/core/services/mikrotik_api_client.dart';
import 'package:wavepass_mobile/core/services/router_discovery_service.dart';

void main() {
  group('MikrotikApiClient Encoding & Parsing Tests', () {
    test('encodeWord properly encodes short ASCII words (< 128 bytes)', () {
      final bytes = MikrotikApiClient.encodeWord('/login');
      expect(bytes.length, equals(7));
      expect(bytes[0], equals(6)); // length byte
      expect(utf8.decode(bytes.sublist(1)), equals('/login'));
    });

    test('encodeWord properly encodes attribute words', () {
      final bytes = MikrotikApiClient.encodeWord('=name=admin');
      expect(bytes.length, equals(12));
      expect(bytes[0], equals(11));
      expect(utf8.decode(bytes.sublist(1)), equals('=name=admin'));
    });

    test('encodeWord handles words longer than 127 bytes', () {
      final longStr = 'A' * 200;
      final bytes = MikrotikApiClient.encodeWord(longStr);
      expect(bytes.length, equals(202));
      // 200 in length header: (200 >> 8) | 0x80 = 0x80, 200 & 0xFF = 200 (0xC8)
      expect(bytes[0], equals(0x80));
      expect(bytes[1], equals(200));
      expect(utf8.decode(bytes.sublist(2)), equals(longStr));
    });

    test('Sentence and attribute parsing handles typical RouterOS responses', () {
      final words = ['!re', '=board-name=hAP ac3', '=cpu-load=3', '=uptime=12h30m', '=version=7.14'];
      // Use client to test sentence parsing behavior
      final sentence = MikrotikSentence(words[0], {
        'board-name': 'hAP ac3',
        'cpu-load': '3',
        'uptime': '12h30m',
        'version': '7.14',
      });

      expect(sentence.type, equals('!re'));
      expect(sentence.attributes['board-name'], equals('hAP ac3'));
      expect(sentence.attributes['cpu-load'], equals('3'));
      expect(sentence.attributes['uptime'], equals('12h30m'));
      expect(sentence.attributes['version'], equals('7.14'));
    });
  });

  group('MikrotikApiClient Real Loopback Socket Server Tests', () {
    late ServerSocket server;
    int port = 0;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
    });

    tearDown(() async {
      await server.close();
    });

    test('connectAndLogin succeeds when mock RouterOS returns !done', () async {
      server.listen((socket) {
        socket.listen((data) {
          // Verify client sent /login
          // Respond with !done (length 5: 0x05, '!done', 0x00)
          socket.add([
            5, 0x21, 0x64, 0x6F, 0x6E, 0x65, // !done
            0, // End of sentence
          ]);
        });
      });

      final client = MikrotikApiClient(host: '127.0.0.1', port: port);
      final ok = await client.connectAndLogin('admin', 'pass123');
      expect(ok, isTrue);
      await client.close();
    });

    test('connectAndLogin throws MikrotikAuthException when mock RouterOS returns !trap with login error', () async {
      server.listen((socket) {
        socket.listen((data) {
          // Respond with !trap: =message=cannot log in, followed by !done
          final trapBytes = <int>[
            5, 0x21, 0x74, 0x72, 0x61, 0x70, // !trap
            ...MikrotikApiClient.encodeWord('=message=cannot log in'),
            0, // End of sentence
            5, 0x21, 0x64, 0x6F, 0x6E, 0x65, // !done
            0, // End of sentence
          ];
          socket.add(trapBytes);
        });
      });

      final client = MikrotikApiClient(host: '127.0.0.1', port: port);
      expect(
        () async => await client.connectAndLogin('admin', 'wrongpass'),
        throwsA(isA<MikrotikAuthException>()),
      );
      await client.close();
    });

    test('getSystemResource parses system info correctly from mock RouterOS', () async {
      server.listen((socket) {
        socket.listen((data) {
          final str = utf8.decode(data, allowMalformed: true);
          if (str.contains('/login')) {
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]); // !done
          } else if (str.contains('/system/resource/print')) {
            final resBytes = <int>[
              3, 0x21, 0x72, 0x65, // !re
              ...MikrotikApiClient.encodeWord('=board-name=MikroTik hEX'),
              ...MikrotikApiClient.encodeWord('=cpu-load=2'),
              ...MikrotikApiClient.encodeWord('=version=7.15.2'),
              0, // End of sentence
              5, 0x21, 0x64, 0x6F, 0x6E, 0x65, // !done
              0,
            ];
            socket.add(resBytes);
          }
        });
      });

      final client = MikrotikApiClient(host: '127.0.0.1', port: port);
      await client.connectAndLogin('admin', 'pass123');
      final resource = await client.getSystemResource();

      expect(resource['board-name'], equals('MikroTik hEX'));
      expect(resource['cpu-load'], equals('2'));
      expect(resource['version'], equals('7.15.2'));
      await client.close();
    });

    test('getSystemIdentity parses router identity correctly from mock RouterOS', () async {
      server.listen((socket) {
        socket.listen((data) {
          final str = utf8.decode(data, allowMalformed: true);
          if (str.contains('/login')) {
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]); // !done
          } else if (str.contains('/system/identity/print')) {
            final resBytes = <int>[
              3, 0x21, 0x72, 0x65, // !re
              ...MikrotikApiClient.encodeWord('=name=WavePass-CoreRouter'),
              0, // End of sentence
              5, 0x21, 0x64, 0x6F, 0x6E, 0x65, // !done
              0,
            ];
            socket.add(resBytes);
          }
        });
      });

      final client = MikrotikApiClient(host: '127.0.0.1', port: port);
      await client.connectAndLogin('admin', 'pass123');
      final identity = await client.getSystemIdentity();

      expect(identity, equals('WavePass-CoreRouter'));
      await client.close();
    });

    test('createHotspotUser provisions voucher directly via /ip/hotspot/user/add', () async {
      String? executedCommand;
      server.listen((socket) {
        socket.listen((data) {
          final str = utf8.decode(data, allowMalformed: true);
          if (str.contains('/login')) {
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]); // !done
          } else if (str.contains('/ip/hotspot/user/add')) {
            executedCommand = str;
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]); // !done
          }
        });
      });

      final client = MikrotikApiClient(host: '127.0.0.1', port: port);
      await client.connectAndLogin('admin', 'pass123');
      final success = await client.createHotspotUser(
        code: 'TEST-VOUCHER-1',
        pass: 'TEST-PASS-1',
        profile: 'default',
        sessionTimeoutSeconds: 3600,
      );

      expect(success, isTrue);
      expect(executedCommand, contains('TEST-VOUCHER-1'));
      await client.close();
    });

    test('createHotspotUser updates user via fallback when user already exists', () async {
      bool setExecuted = false;
      server.listen((socket) {
        socket.listen((data) {
          final str = utf8.decode(data, allowMalformed: true);
          if (str.contains('/login')) {
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]); // !done
          } else if (str.contains('/ip/hotspot/user/add')) {
            // Return !trap: already have user with this name
            socket.add([
              5, 0x21, 0x74, 0x72, 0x61, 0x70, // !trap
              ...MikrotikApiClient.encodeWord('=message=already have user with this name'),
              0,
              5, 0x21, 0x64, 0x6F, 0x6E, 0x65,
              0,
            ]);
          } else if (str.contains('/ip/hotspot/user/print')) {
            // Return !re with .id=*1
            socket.add([
              3, 0x21, 0x72, 0x65, // !re
              ...MikrotikApiClient.encodeWord('=.id=*1'),
              ...MikrotikApiClient.encodeWord('=name=EXISTING-USER'),
              0,
              5, 0x21, 0x64, 0x6F, 0x6E, 0x65,
              0,
            ]);
          } else if (str.contains('/ip/hotspot/user/set')) {
            setExecuted = true;
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]); // !done
          }
        });
      });

      final client = MikrotikApiClient(host: '127.0.0.1', port: port);
      await client.connectAndLogin('admin', 'pass123');
      final success = await client.createHotspotUser(
        code: 'EXISTING-USER',
        pass: 'NEW-PASS',
        profile: 'default',
        sessionTimeoutSeconds: 3600,
      );

      expect(success, isTrue);
      expect(setExecuted, isTrue);
      await client.close();
    });

    test('RouterDiscoveryService includes wp-payment-trial in standardDurationProfiles', () {
      final trial = RouterDiscoveryService.standardDurationProfiles
          .firstWhere((p) => p['name'] == 'wp-payment-trial');
      expect(trial['rate-limit'], equals('2M/2M'));
      expect(trial['session-timeout'], equals('2m'));
      expect(trial['shared-users'], equals('2'));
      expect(trial['transparent-proxy'], equals('yes'));
    });

    test('installHotspotConfig configures hotspot profile with trial support and addresses-per-mac=1', () async {
      final executedWords = <String>[];
      server.listen((socket) {
        socket.listen((data) {
          final str = utf8.decode(data, allowMalformed: true);
          if (str.contains('/login')) {
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          } else {
            executedWords.add(str);
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          }
        });
      });

      final client = MikrotikApiClient(host: '127.0.0.1', port: port);
      await client.connectAndLogin('admin', 'pass123');
      final res = await client.installHotspotConfig(slug: 'testvenue', venueName: 'Test Venue', localIp: '192.168.88.1');
      await client.close();

      expect(res['profile'], isTrue);
      final profileSentence = executedWords.firstWhere((w) => w.contains('/ip/hotspot/profile/add'));
      expect(profileSentence, contains('login-by=http-pap,http-chap,mac-cookie,trial'));
      expect(profileSentence, contains('trial-user-profile=wp-payment-trial'));
      expect(profileSentence, contains('trial-uptime=2m/24h'));
      expect(profileSentence, isNot(contains('addresses-per-mac=1')));
      expect(profileSentence, isNot(contains('mac-cookie-timeout=3d')));

      final hotspotSentence = executedWords.firstWhere((w) => w.contains('/ip/hotspot/add'));
      expect(hotspotSentence, contains('addresses-per-mac=1'));

      final dhcpSentence = executedWords.firstWhere((w) => w.contains('/ip/dhcp-server/set'));
      expect(dhcpSentence, contains('lease-time=1d'));

      final userProfileSentence = executedWords.firstWhere((w) => w.contains('/ip/hotspot/user/profile/add'));
      expect(userProfileSentence, contains('add-mac-cookie=yes'));
      expect(userProfileSentence, contains('mac-cookie-timeout=3d'));
    });
  });
}
