import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/core/services/mikrotik_api_client.dart';
import 'package:wavepass_mobile/screens/home_dashboard_screen.dart';
import 'package:wavepass_mobile/screens/wallet_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Balance Eye Toggler Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('HomeDashboardScreen balance is hidden by default and toggles on eye icon tap', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: HomeDashboardScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Check balance is hidden by default (sticky strip + earnings card)
      expect(find.text("TODAY'S WI-FI EARNINGS"), findsOneWidget);
      expect(find.text("₦ • • • • • •"), findsNWidgets(2));
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tap eye toggler to reveal
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      expect(find.text("₦ • • • • • •"), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // Check SharedPreferences updated
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('hide_balance_preference'), isFalse);

      // Tap eye toggler to hide again
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text("₦ • • • • • •"), findsNWidgets(2));
      expect(prefs.getBool('hide_balance_preference'), isTrue);
    });

    testWidgets('WalletScreen balance is hidden by default and toggles on eye icon tap', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: WalletScreen(venueId: 'test-venue'),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('AVAILABLE BALANCE'), findsOneWidget);
      expect(find.text('₦ • • • • • •'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tap eye toggler to reveal
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      expect(find.text('₦ • • • • • •'), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('MikrotikApiClient Enforce No Hotspot Sharing Tests', () {
    late ServerSocket server;
    late int port;

    setUp(() async {
      server = await ServerSocket.bind('127.0.0.1', 0);
      port = server.port;
    });

    tearDown(() async {
      await server.close();
    });

    test('enforceNoHotspotSharing executes profile, isolation, and filter rules', () async {
      final receivedCommands = <String>[];

      server.listen((socket) {
        socket.listen((data) {
          final str = utf8.decode(data, allowMalformed: true);
          if (str.contains('/login')) {
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]); // !done
          } else if (str.contains('/ip/hotspot/user/profile/print')) {
            receivedCommands.add('user_profile_print');
            final resBytes = <int>[
              3, 0x21, 0x72, 0x65,
              ...MikrotikApiClient.encodeWord('=.id=*1'),
              ...MikrotikApiClient.encodeWord('=name=default'),
              0,
              5, 0x21, 0x64, 0x6F, 0x6E, 0x65,
              0,
            ];
            socket.add(resBytes);
          } else if (str.contains('/ip/hotspot/user/profile/set')) {
            receivedCommands.add('user_profile_set');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          } else if (str.contains('/ip/hotspot/profile/print')) {
            receivedCommands.add('srv_profile_print');
            final resBytes = <int>[
              3, 0x21, 0x72, 0x65,
              ...MikrotikApiClient.encodeWord('=.id=*H1'),
              ...MikrotikApiClient.encodeWord('=name=hsprof1'),
              0,
              5, 0x21, 0x64, 0x6F, 0x6E, 0x65,
              0,
            ];
            socket.add(resBytes);
          } else if (str.contains('/ip/hotspot/profile/set')) {
            receivedCommands.add('srv_profile_set');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          } else if (str.contains('/interface/wireless/print')) {
            receivedCommands.add('wireless_print');
            final resBytes = <int>[
              3, 0x21, 0x72, 0x65,
              ...MikrotikApiClient.encodeWord('=.id=*W1'),
              ...MikrotikApiClient.encodeWord('=name=wlan1'),
              0,
              5, 0x21, 0x64, 0x6F, 0x6E, 0x65,
              0,
            ];
            socket.add(resBytes);
          } else if (str.contains('/interface/wireless/set')) {
            receivedCommands.add('wireless_set');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          } else if (str.contains('/ip/hotspot/user/profile/add')) {
            receivedCommands.add('user_profile_add');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          } else if (str.contains('/interface/bridge/port/print')) {
            receivedCommands.add('bridge_port_print');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          } else if (str.contains('/ip/firewall/mangle/print')) {
            receivedCommands.add('mangle_print');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]); // empty
          } else if (str.contains('/ip/firewall/mangle/add')) {
            receivedCommands.add('mangle_add');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          } else if (str.contains('/ip/firewall/filter/print')) {
            receivedCommands.add('filter_print');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]); // empty -> add filter
          } else if (str.contains('/ip/firewall/filter/add')) {
            receivedCommands.add('filter_add');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          } else if (str.contains('/ipv6')) {
            receivedCommands.add('ipv6_cmd');
            socket.add([5, 0x21, 0x64, 0x6F, 0x6E, 0x65, 0]);
          }
        });
      });

      final client = MikrotikApiClient(host: '127.0.0.1', port: port);
      await client.connect();
      await client.login('admin', '');
      final res = await client.enforceNoHotspotSharing();
      await client.close();

      expect(res['success'], isTrue);
      expect(res['profiles'], isTrue);
      expect(res['serverProfiles'], isTrue);
      expect(res['isolation'], isTrue);
      expect(res['mangleTtl'], isTrue);
      expect(res['firewallFilter'], isTrue);

      expect(receivedCommands, contains('user_profile_print'));
      expect(receivedCommands, contains('user_profile_set'));
      expect(receivedCommands, contains('user_profile_add'));
      expect(receivedCommands, contains('srv_profile_print'));
      expect(receivedCommands, contains('srv_profile_set'));
      expect(receivedCommands, contains('wireless_print'));
      expect(receivedCommands, contains('wireless_set'));
      expect(receivedCommands, contains('mangle_add'));
      expect(receivedCommands, contains('filter_print'));
      expect(receivedCommands, contains('ipv6_cmd'));
    });
  });
}
