import 'package:flutter_test/flutter_test.dart';
import 'package:wavepass_mobile/core/services/router_discovery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouterDiscoveryService Models & Dual Status Tests', () {
    test('DiscoveredRouter model initializes with default connectionType LAN', () {
      final router = DiscoveredRouter(
        ip: '192.168.88.1',
        identity: 'MikroTik hEX S',
        version: 'RouterOS v7.14',
        cpuLoad: '4%',
        uptime: '2d 4h',
        totalMemory: '256 MB',
        isReachable: true,
        latencyMs: 3,
      );

      expect(router.ip, equals('192.168.88.1'));
      expect(router.identity, equals('MikroTik hEX S'));
      expect(router.connectionType, equals('LAN'));
      expect(router.isReachable, isTrue);
      expect(router.latencyMs, equals(3));
    });

    test('RouterDualConnectionStatus prefers Local LAN when both links online', () {
      final local = DiscoveredRouter(
        ip: '192.168.88.1',
        identity: 'MikroTik Local',
        version: '7.14',
        cpuLoad: '5%',
        uptime: '1d',
        totalMemory: '128 MB',
        isReachable: true,
        connectionType: 'LAN',
        latencyMs: 2,
      );

      final tunnel = DiscoveredRouter(
        ip: 'http://10.8.0.2:80',
        identity: 'MikroTik Tunnel',
        version: '7.14',
        cpuLoad: '5%',
        uptime: '1d',
        totalMemory: '128 MB',
        isReachable: true,
        connectionType: 'Tunnel',
        latencyMs: 35,
      );

      final status = RouterDualConnectionStatus(
        localRouter: local,
        tunnelRouter: tunnel,
        isLocalOnline: true,
        isTunnelOnline: true,
        activeEndpoint: 'http://192.168.88.1',
        activeMode: 'local',
        latencySummary: 'LAN: 2ms | Tunnel: 35ms',
      );

      expect(status.isAnyOnline, isTrue);
      expect(status.isLocalOnline, isTrue);
      expect(status.isTunnelOnline, isTrue);
      expect(status.activeMode, equals('local'));
      expect(status.activeEndpoint, equals('http://192.168.88.1'));
      expect(status.latencySummary, contains('LAN: 2ms'));
      expect(status.latencySummary, contains('Tunnel: 35ms'));
    });

    test('RouterDualConnectionStatus falls back to Tunnel when Local LAN is offline', () {
      final tunnel = DiscoveredRouter(
        ip: 'https://tunnel.nexawavepass.com/MT1234',
        identity: 'MikroTik Tunnel Only',
        version: '7.14',
        cpuLoad: '2%',
        uptime: '5h',
        totalMemory: '256 MB',
        isReachable: true,
        connectionType: 'Tunnel',
        latencyMs: 40,
      );

      final status = RouterDualConnectionStatus(
        localRouter: null,
        tunnelRouter: tunnel,
        isLocalOnline: false,
        isTunnelOnline: true,
        activeEndpoint: 'https://tunnel.nexawavepass.com/MT1234',
        activeMode: 'tunnel',
        latencySummary: 'Tunnel: 40ms',
      );

      expect(status.isAnyOnline, isTrue);
      expect(status.isLocalOnline, isFalse);
      expect(status.isTunnelOnline, isTrue);
      expect(status.activeMode, equals('tunnel'));
      expect(status.activeEndpoint, equals('https://tunnel.nexawavepass.com/MT1234'));
    });

    test('RouterDualConnectionStatus reports offline when both links are down', () {
      final status = RouterDualConnectionStatus(
        localRouter: null,
        tunnelRouter: null,
        isLocalOnline: false,
        isTunnelOnline: false,
        activeEndpoint: null,
        activeMode: 'offline',
        latencySummary: null,
      );

      expect(status.isAnyOnline, isFalse);
      expect(status.isLocalOnline, isFalse);
      expect(status.isTunnelOnline, isFalse);
      expect(status.activeMode, equals('offline'));
      expect(status.activeEndpoint, isNull);
    });

    test('Default admin credentials keys are defined in RouterDiscoveryService', () {
      expect(RouterDiscoveryService.keyRouterLocalIp, equals('wavepass_router_local_ip'));
      expect(RouterDiscoveryService.keyRouterTunnelEndpoint, equals('wavepass_router_tunnel_endpoint'));
      expect(RouterDiscoveryService.keyRouterUsername, equals('wavepass_router_username'));
      expect(RouterDiscoveryService.keyRouterPassword, equals('wavepass_router_password'));
    });

    test('DiscoveredRouter correctly captures authFailed and errorMessage', () {
      final authFailRouter = DiscoveredRouter(
        ip: 'http://192.168.88.1',
        identity: 'MikroTik Gateway (Auth Failed)',
        version: 'RouterOS v7',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: true,
        authFailed: true,
        errorMessage: 'Login failed (HTTP 401): Invalid password for user "admin"',
      );

      expect(authFailRouter.authFailed, isTrue);
      expect(authFailRouter.errorMessage, contains('HTTP 401'));
      expect(authFailRouter.ip, equals('http://192.168.88.1'));
    });

    test('RouterDualConnectionStatus marks offline and surfaces error if localRouter authFailed', () {
      final authFailRouter = DiscoveredRouter(
        ip: 'http://192.168.88.1',
        identity: 'MikroTik Gateway (Auth Failed)',
        version: 'RouterOS v7',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: true,
        authFailed: true,
        errorMessage: 'Login failed (HTTP 401): Invalid password for user "admin"',
      );

      final status = RouterDualConnectionStatus(
        localRouter: authFailRouter,
        tunnelRouter: null,
        isLocalOnline: false,
        isTunnelOnline: false,
        activeMode: 'offline',
        errorMessage: authFailRouter.errorMessage,
      );

      expect(status.isAnyOnline, isFalse);
      expect(status.isLocalOnline, isFalse);
      expect(status.errorMessage, contains('HTTP 401'));
    });

    test('DiscoveredRouter correctly captures captive portal interception and snippet', () {
      final captivePortalRouter = DiscoveredRouter(
        ip: 'http://192.168.88.1',
        identity: 'MikroTik HotSpot Portal',
        version: 'RouterOS (Captive Portal)',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: true,
        statusCode: 200,
        captivePortalIntercepted: true,
        rawResponseSnippet: '<!DOCTYPE html><html><title>Hotspot login</title>...',
        errorMessage: 'HotSpot Captive Portal intercepted port 80.',
      );

      expect(captivePortalRouter.captivePortalIntercepted, isTrue);
      expect(captivePortalRouter.isReachable, isTrue);
      expect(captivePortalRouter.statusCode, equals(200));
      expect(captivePortalRouter.rawResponseSnippet, contains('Hotspot login'));
      expect(captivePortalRouter.errorMessage, contains('Captive Portal'));
    });

    test('RouterDualConnectionStatus correctly includes local/tunnel diagnostics and device IP', () {
      final status = RouterDualConnectionStatus(
        localRouter: DiscoveredRouter(
          ip: 'http://192.168.88.1',
          identity: 'Unreachable Gateway',
          version: 'N/A',
          cpuLoad: 'N/A',
          uptime: 'N/A',
          totalMemory: 'N/A',
          isReachable: false,
          errorMessage: 'Connection timed out (8s) reaching http://192.168.88.1',
        ),
        tunnelRouter: null,
        isLocalOnline: false,
        isTunnelOnline: false,
        activeMode: 'offline',
        errorMessage: 'Connection timed out (8s) reaching http://192.168.88.1',
        localDiagnosticDetail: 'Connection timed out (8s) reaching http://192.168.88.1',
        tunnelDiagnosticDetail: 'Cloud tunnel offline',
        deviceWifiIp: '192.168.88.25',
      );

      expect(status.isAnyOnline, isFalse);
      expect(status.isLocalOnline, isFalse);
      expect(status.deviceWifiIp, equals('192.168.88.25'));
      expect(status.localDiagnosticDetail, contains('Connection timed out'));
      expect(status.tunnelDiagnosticDetail, equals('Cloud tunnel offline'));
      expect(status.errorMessage, contains('timed out'));
    });

    test('DiscoveredRouter handles WebFig on Port 80 gracefully', () {
      final webfigRouter = DiscoveredRouter(
        ip: 'http://192.168.88.1',
        identity: 'MikroTik WebFig',
        version: 'RouterOS WebFig',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: true,
        statusCode: 200,
        errorMessage: 'MikroTik WebFig responded on Port 80 at http://192.168.88.1',
      );

      expect(webfigRouter.isReachable, isTrue);
      expect(webfigRouter.identity, equals('MikroTik WebFig'));
      expect(webfigRouter.errorMessage, contains('WebFig responded on Port 80'));
    });

    test('Strict Port 80 discovery does not produce Port 8728 errors', () {
      final port80ErrorRouter = DiscoveredRouter(
        ip: 'http://192.168.88.1',
        identity: 'Unreachable Gateway',
        version: 'N/A',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: false,
        errorMessage: 'Connection refused at 192.168.88.1:80. Port is closed or RouterOS www service is disabled.',
      );

      expect(port80ErrorRouter.errorMessage, contains('192.168.88.1:80'));
      expect(port80ErrorRouter.errorMessage, isNot(contains('8728')));
      expect(port80ErrorRouter.errorMessage, isNot(contains('192.168.1.1')));
    });

    test('DiscoveredRouter handles RouterOS v7 rest-plain 404 with actionable CLI command', () {
      final router404 = DiscoveredRouter(
        ip: 'http://192.168.88.1',
        identity: 'MikroTik Gateway (REST 404)',
        version: 'RouterOS v7 (REST Disabled)',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: false,
        statusCode: 404,
        errorMessage: 'RouterOS v7 REST API is disabled on Port 80 (HTTP 404). Run in MikroTik Terminal: /ip/service/webserver/set rest-plain=yes',
      );

      expect(router404.statusCode, equals(404));
      expect(router404.identity, contains('REST 404'));
      expect(router404.errorMessage, contains('rest-plain=yes'));
      expect(router404.errorMessage, contains('/ip/service/webserver/set'));
    });

    test('RouterDualConnectionStatus surfaces rest-plain CLI command when 404 occurs', () {
      final router404 = DiscoveredRouter(
        ip: 'http://192.168.88.1',
        identity: 'MikroTik Gateway (REST 404)',
        version: 'RouterOS v7 (REST Disabled)',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: false,
        statusCode: 404,
        errorMessage: 'RouterOS v7 REST API is disabled on Port 80 (HTTP 404). Run in MikroTik Terminal: /ip/service/webserver/set rest-plain=yes',
      );

      final status = RouterDualConnectionStatus(
        localRouter: router404,
        tunnelRouter: null,
        isLocalOnline: false,
        isTunnelOnline: false,
        activeMode: 'offline',
        errorMessage: router404.errorMessage,
      );

      expect(status.isAnyOnline, isFalse);
      expect(status.errorMessage, contains('rest-plain=yes'));
      expect(status.errorMessage, contains('HTTP 404'));
    });

    test('DiscoveredRouter on Port 8728 API reports online with API connection type', () {
      final apiRouter = DiscoveredRouter(
        ip: '192.168.88.1:8728',
        identity: 'RB951Ui-2HnD',
        version: '7.23.5',
        cpuLoad: '5%',
        uptime: '2d3h',
        totalMemory: '128 MB',
        isReachable: true,
        connectionType: 'LAN (API :8728)',
        latencyMs: 3,
        statusCode: 200,
      );

      expect(apiRouter.isReachable, isTrue);
      expect(apiRouter.connectionType, contains('API :8728'));
      expect(apiRouter.identity, equals('RB951Ui-2HnD'));
      expect(apiRouter.version, equals('7.23.5'));

      final status = RouterDualConnectionStatus(
        localRouter: apiRouter,
        tunnelRouter: null,
        isLocalOnline: true,
        isTunnelOnline: false,
        activeMode: 'local',
        latencySummary: 'LAN: 3ms',
      );

      expect(status.isAnyOnline, isTrue);
      expect(status.isLocalOnline, isTrue);
      expect(status.activeMode, equals('local'));
      expect(status.latencySummary, contains('LAN: 3ms'));
    });
  });
}
