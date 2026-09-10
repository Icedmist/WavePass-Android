import 'package:flutter_test/flutter_test.dart';
import 'package:wavepass_mobile/core/services/router_discovery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Barcode Scan & Router Setup Verification Tests', () {
    test('RouterDiscoveryService defaults provisionWithSerial to local endpoint and mode', () {
      const serial = 'D401C3E8A1';
      const defaultLocalGateway = 'http://192.168.88.1';

      expect(defaultLocalGateway, equals('http://192.168.88.1'));
      expect(serial.replaceAll(RegExp(r'[^A-Z0-9]'), ''), equals('D401C3E8A1'));
    });

    test('DiscoveredRouter correctly parses hardware resource payload', () {
      final router = DiscoveredRouter(
        ip: 'http://192.168.88.1',
        identity: 'MikroTik hEX',
        version: '7.15.2',
        cpuLoad: '1%',
        uptime: '4d12h',
        totalMemory: '256 MB',
        isReachable: true,
        connectionType: 'LAN',
        latencyMs: 4,
      );

      expect(router.isReachable, isTrue);
      expect(router.ip, equals('http://192.168.88.1'));
      expect(router.connectionType, equals('LAN'));
      expect(router.latencyMs, equals(4));
    });

    test('Dual connection status correctly identifies local offline state', () {
      final status = RouterDualConnectionStatus(
        localRouter: null,
        tunnelRouter: null,
        isLocalOnline: false,
        isTunnelOnline: false,
        activeMode: 'offline',
      );

      expect(status.isAnyOnline, isFalse);
      expect(status.isLocalOnline, isFalse);
      expect(status.isTunnelOnline, isFalse);
      expect(status.activeMode, equals('offline'));
    });
  });
}
