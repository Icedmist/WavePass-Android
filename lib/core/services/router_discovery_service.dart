import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wavepass_api.dart';
import 'mikrotik_api_client.dart';

class DiscoveredRouter {
  final String ip;
  final String identity;
  final String version;
  final String cpuLoad;
  final String uptime;
  final String totalMemory;
  final bool isReachable;
  final String connectionType; // 'LAN' or 'Tunnel'
  final int? latencyMs;
  final bool authFailed;
  final String? errorMessage;
  final int? statusCode;
  final bool captivePortalIntercepted;
  final String? rawResponseSnippet;

  DiscoveredRouter({
    required this.ip,
    required this.identity,
    required this.version,
    required this.cpuLoad,
    required this.uptime,
    required this.totalMemory,
    required this.isReachable,
    this.connectionType = 'LAN',
    this.latencyMs,
    this.authFailed = false,
    this.errorMessage,
    this.statusCode,
    this.captivePortalIntercepted = false,
    this.rawResponseSnippet,
  });
}

class RouterDualConnectionStatus {
  final DiscoveredRouter? localRouter;
  final DiscoveredRouter? tunnelRouter;
  final bool isLocalOnline;
  final bool isTunnelOnline;
  final String? activeEndpoint;
  final String activeMode; // 'local', 'tunnel', or 'offline'
  final String? latencySummary;
  final String? errorMessage;
  final String? localDiagnosticDetail;
  final String? tunnelDiagnosticDetail;
  final String? deviceWifiIp;

  RouterDualConnectionStatus({
    this.localRouter,
    this.tunnelRouter,
    required this.isLocalOnline,
    required this.isTunnelOnline,
    this.activeEndpoint,
    required this.activeMode,
    this.latencySummary,
    this.errorMessage,
    this.localDiagnosticDetail,
    this.tunnelDiagnosticDetail,
    this.deviceWifiIp,
  });

  bool get isAnyOnline => isLocalOnline || isTunnelOnline;
}

class RouterDiscoveryService {
  // Preference keys for persistent router configuration
  static const String keyRouterLocalIp = 'wavepass_router_local_ip';
  static const String keyRouterTunnelEndpoint = 'wavepass_router_tunnel_endpoint';
  static const String keyRouterUsername = 'wavepass_router_username';
  static const String keyRouterPassword = 'wavepass_router_password';

  /// Creates an HTTP client configured to accept self-signed certificates on local router hardware.
  static http.Client createRouterClient({Duration timeout = const Duration(seconds: 8)}) {
    if (kIsWeb) return http.Client();
    final ioHttpClient = HttpClient()
      ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = timeout;
    return IOClient(ioHttpClient);
  }

  /// Discovers the device's local Wi-Fi / LAN IPv4 address.
  static Future<String?> getLocalDeviceIp() async {
    if (kIsWeb) return null;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('wifi') || name.contains('en') || name.contains('eth')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.address.isNotEmpty) {
              return addr.address;
            }
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.isNotEmpty) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Auto-discovers MikroTik router over local subnet.
  /// Uses default admin credentials (default empty password), without creating extra users.
  static Future<DiscoveredRouter?> discoverLocalRouter({
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    // 1. Probe with supplied credentials
    DiscoveredRouter? router = await _probeRouter(ip, username, password, connectionType: "LAN");
    if (router != null && router.isReachable && !router.authFailed && !router.captivePortalIntercepted) {
      return router;
    }

    // If password was non-empty and probe returned authFailed or unreachable, try empty password fallback on same IP
    if (password.isNotEmpty && (router == null || router.authFailed)) {
      final emptyPassRouter = await _probeRouter(ip, username, "", connectionType: "LAN");
      if (emptyPassRouter != null && emptyPassRouter.isReachable && !emptyPassRouter.authFailed) {
        return emptyPassRouter;
      }
    }

    // Return the router with its diagnostic state (even if auth failed, captive portal, or unreachable)
    return router;
  }

  /// Probes any arbitrary HTTP/HTTPS endpoint or IP (LAN or WireGuard/Cloud tunnel).
  static Future<DiscoveredRouter?> probeEndpoint(
    String rawEndpoint, {
    String username = "admin",
    String password = "",
    String connectionType = "Endpoint",
  }) async {
    var normalized = rawEndpoint.trim();
    if (normalized.isEmpty) return null;

    // Direct Port 8728 RouterOS API endpoint handling
    if (normalized.startsWith('api://') || normalized.contains(':8728')) {
      var clean = normalized;
      if (clean.startsWith('api://')) clean = clean.substring(6);
      if (clean.startsWith('http://')) clean = clean.substring(7);
      if (clean.startsWith('https://')) clean = clean.substring(8);
      int port = 8728;
      if (clean.contains(':')) {
        final parts = clean.split(':');
        clean = parts[0];
        port = int.tryParse(parts[1]) ?? 8728;
      }
      if (clean.contains('/')) clean = clean.split('/').first;

      return await _probeRouterOsApi(
        host: clean,
        port: port,
        username: username,
        password: password,
        connectionType: connectionType == 'Endpoint' ? 'Tunnel (API :$port)' : connectionType,
      );
    }

    final client = createRouterClient(timeout: const Duration(seconds: 8));
    try {
      if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
        normalized = 'http://$normalized';
      }
      if (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }

      final uri = Uri.parse('$normalized/rest/system/resource');
      final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

      final sw = Stopwatch()..start();
      final response = await client.get(
        uri,
        headers: {
          'Authorization': authHeader,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));
      sw.stop();

      final rawBody = response.body.trim();

      if (response.statusCode == 200) {
        if (rawBody.startsWith('<') || rawBody.toLowerCase().contains('<!doctype') || rawBody.toLowerCase().contains('<html')) {
          return DiscoveredRouter(
            ip: normalized,
            identity: 'Remote Web Endpoint',
            version: 'N/A',
            cpuLoad: 'N/A',
            uptime: 'N/A',
            totalMemory: 'N/A',
            isReachable: false,
            connectionType: connectionType,
            statusCode: 200,
            errorMessage: 'Cloud tunnel URL returned HTML instead of RouterOS REST API (WireGuard tunnel pending).',
          );
        }

        final dynamic decoded = jsonDecode(response.body);
        final Map<String, dynamic> data = decoded is List
            ? (decoded.isNotEmpty ? Map<String, dynamic>.from(decoded.first as Map) : <String, dynamic>{})
            : Map<String, dynamic>.from(decoded as Map);

        return DiscoveredRouter(
          ip: normalized,
          identity: data['board-name']?.toString() ?? data['platform']?.toString() ?? 'MikroTik Gateway',
          version: data['version']?.toString() ?? 'RouterOS v7',
          cpuLoad: '${data['cpu-load'] ?? 0}%',
          uptime: data['uptime']?.toString() ?? '0m',
          totalMemory: '${((data['total-memory'] ?? 0) / (1024 * 1024)).toStringAsFixed(0)} MB',
          isReachable: true,
          connectionType: connectionType,
          latencyMs: sw.elapsedMilliseconds,
          authFailed: false,
          statusCode: 200,
        );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return DiscoveredRouter(
          ip: normalized,
          identity: 'MikroTik Gateway (Auth Failed)',
          version: 'RouterOS v7',
          cpuLoad: 'N/A',
          uptime: 'N/A',
          totalMemory: 'N/A',
          isReachable: true,
          connectionType: connectionType,
          latencyMs: sw.elapsedMilliseconds,
          authFailed: true,
          statusCode: response.statusCode,
          errorMessage: 'Login failed (HTTP ${response.statusCode}): Invalid password for user "$username"',
        );
      } else {
        return DiscoveredRouter(
          ip: normalized,
          identity: 'Tunnel Endpoint',
          version: 'N/A',
          cpuLoad: 'N/A',
          uptime: 'N/A',
          totalMemory: 'N/A',
          isReachable: false,
          connectionType: connectionType,
          statusCode: response.statusCode,
          errorMessage: 'Tunnel endpoint returned HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return DiscoveredRouter(
        ip: rawEndpoint,
        identity: 'Tunnel Endpoint',
        version: 'N/A',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: false,
        connectionType: connectionType,
        errorMessage: 'Tunnel connection failed: $e',
      );
    } finally {
      client.close();
    }
  }

  /// Probes both Local Subnet (LAN Direct) and Remote Cloud/WireGuard Tunnel concurrently.
  static Future<RouterDualConnectionStatus> checkDualConnection({
    String localIp = "192.168.88.1",
    String? tunnelEndpoint,
    String username = "admin",
    String password = "",
  }) async {
    final futures = <Future<dynamic>>[
      discoverLocalRouter(ip: localIp, username: username, password: password),
      if (tunnelEndpoint != null && tunnelEndpoint.trim().isNotEmpty)
        probeEndpoint(tunnelEndpoint, username: username, password: password, connectionType: "Tunnel")
      else
        Future.value(null),
      getLocalDeviceIp(),
    ];

    final results = await Future.wait(futures);
    final localRouter = results[0] as DiscoveredRouter?;
    final tunnelRouter = (results.length > 1 ? results[1] : null) as DiscoveredRouter?;
    final deviceWifiIp = (results.length > 2 ? results[2] : null) as String?;

    final isLocalOnline = localRouter != null && localRouter.isReachable && !localRouter.authFailed && !localRouter.captivePortalIntercepted;
    final isTunnelOnline = tunnelRouter != null && tunnelRouter.isReachable && !tunnelRouter.authFailed;

    String? activeEndpoint;
    String activeMode = 'offline';

    // Prioritize local LAN if available (sub-millisecond latency, no internet reliance)
    if (isLocalOnline) {
      activeEndpoint = localRouter.ip.startsWith('http') ? localRouter.ip : 'http://${localRouter.ip}';
      activeMode = 'local';
    } else if (isTunnelOnline) {
      activeEndpoint = tunnelRouter.ip;
      activeMode = 'tunnel';
    }

    String? latency;
    if (isLocalOnline && localRouter.latencyMs != null) {
      latency = 'LAN: ${localRouter.latencyMs}ms';
    }
    if (isTunnelOnline && tunnelRouter.latencyMs != null) {
      final t = 'Tunnel: ${tunnelRouter.latencyMs}ms';
      latency = latency != null ? '$latency | $t' : t;
    }

    String? error;
    if (localRouter?.captivePortalIntercepted == true) {
      error = localRouter?.errorMessage;
    } else if (localRouter?.authFailed == true) {
      error = localRouter?.errorMessage;
    } else if (!isLocalOnline && localRouter?.errorMessage != null) {
      error = localRouter?.errorMessage;
    } else if (tunnelRouter?.authFailed == true) {
      error = tunnelRouter?.errorMessage;
    } else if (!isTunnelOnline && tunnelRouter?.errorMessage != null) {
      error = tunnelRouter?.errorMessage;
    }

    final localDetail = isLocalOnline
        ? '${localRouter.ip} • ${localRouter.latencyMs ?? 0}ms'
        : (localRouter?.errorMessage ?? 'Local LAN probe failed');

    final tunnelDetail = isTunnelOnline
        ? '${tunnelRouter.ip} • ${tunnelRouter.latencyMs ?? 0}ms'
        : (tunnelRouter?.errorMessage ?? 'Cloud tunnel offline');

    return RouterDualConnectionStatus(
      localRouter: localRouter,
      tunnelRouter: tunnelRouter,
      isLocalOnline: isLocalOnline,
      isTunnelOnline: isTunnelOnline,
      activeEndpoint: activeEndpoint,
      activeMode: activeMode,
      latencySummary: latency,
      errorMessage: error,
      localDiagnosticDetail: localDetail,
      tunnelDiagnosticDetail: tunnelDetail,
      deviceWifiIp: deviceWifiIp,
    );
  }

  /// Probes native MikroTik RouterOS binary API protocol on Port 8728.
  /// Not intercepted by HotSpot captive portals (unlike Port 80 HTTP).
  static Future<DiscoveredRouter?> _probeRouterOsApi({
    required String host,
    int port = 8728,
    required String username,
    required String password,
    String connectionType = 'LAN (API :8728)',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = MikrotikApiClient(
      host: host,
      port: port,
      timeout: timeout,
    );
    final sw = Stopwatch()..start();
    try {
      final loginSuccess = await client.connectAndLogin(username, password);
      sw.stop();
      if (!loginSuccess) {
        return DiscoveredRouter(
          ip: '$host:$port',
          identity: 'MikroTik Gateway (API :$port)',
          version: 'RouterOS API',
          cpuLoad: 'N/A',
          uptime: 'N/A',
          totalMemory: 'N/A',
          isReachable: true,
          connectionType: connectionType,
          latencyMs: sw.elapsedMilliseconds,
          authFailed: true,
          errorMessage: 'Port $port responded, but authentication failed for user "$username". Check username and password.',
        );
      }

      final resource = await client.getSystemResource();
      final identity = await client.getSystemIdentity();
      final board = (identity != null && identity.isNotEmpty)
          ? identity
          : (resource['board-name'] ?? resource['platform'] ?? 'MikroTik Gateway');
      final version = resource['version'] ?? 'RouterOS API';
      final cpu = resource['cpu-load'] != null ? '${resource['cpu-load']}%' : 'N/A';
      final uptime = resource['uptime'] ?? 'N/A';
      final totalMemBytes = int.tryParse(resource['total-memory'] ?? '');
      final totalMem = totalMemBytes != null ? '${(totalMemBytes / (1024 * 1024)).toStringAsFixed(0)} MB' : 'N/A';

      return DiscoveredRouter(
        ip: '$host:$port',
        identity: board,
        version: version,
        cpuLoad: cpu,
        uptime: uptime,
        totalMemory: totalMem,
        isReachable: true,
        connectionType: connectionType,
        latencyMs: sw.elapsedMilliseconds,
        authFailed: false,
        statusCode: 200,
      );
    } on MikrotikAuthException catch (e) {
      sw.stop();
      return DiscoveredRouter(
        ip: '$host:$port',
        identity: 'MikroTik Gateway (Auth Failed)',
        version: 'RouterOS API',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: true,
        connectionType: connectionType,
        latencyMs: sw.elapsedMilliseconds,
        authFailed: true,
        errorMessage: 'Login failed on port $port: ${e.message}',
      );
    } on SocketException catch (e) {
      sw.stop();
      return DiscoveredRouter(
        ip: '$host:$port',
        identity: 'Unreachable Gateway',
        version: 'N/A',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: false,
        connectionType: connectionType,
        errorMessage: 'Port $port socket error: ${e.message}',
      );
    } on TimeoutException {
      sw.stop();
      return DiscoveredRouter(
        ip: '$host:$port',
        identity: 'Unreachable Gateway',
        version: 'N/A',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: false,
        connectionType: connectionType,
        errorMessage: 'Connection timed out (${timeout.inSeconds}s) to port $port at $host',
      );
    } catch (e) {
      sw.stop();
      return DiscoveredRouter(
        ip: '$host:$port',
        identity: 'Unreachable Gateway',
        version: 'N/A',
        cpuLoad: 'N/A',
        uptime: 'N/A',
        totalMemory: 'N/A',
        isReachable: false,
        connectionType: connectionType,
        errorMessage: 'Port $port probe error: $e',
      );
    } finally {
      await client.close();
    }
  }

  static Future<DiscoveredRouter?> _probeRouter(
    String ip,
    String username,
    String password, {
    String connectionType = 'LAN',
  }) async {
    var cleanHost = ip.trim();
    if (cleanHost.startsWith('api://')) cleanHost = cleanHost.substring(6);
    if (cleanHost.startsWith('http://')) cleanHost = cleanHost.substring(7);
    if (cleanHost.startsWith('https://')) cleanHost = cleanHost.substring(8);
    if (cleanHost.endsWith('/')) cleanHost = cleanHost.substring(0, cleanHost.length - 1);
    if (cleanHost.isEmpty) return null;

    // Direct Port 8728 or api scheme handling
    if (cleanHost.contains(':8728') || ip.trim().startsWith('api://')) {
      final hostOnly = cleanHost.contains(':') ? cleanHost.split(':').first : cleanHost;
      final port = cleanHost.contains(':') ? (int.tryParse(cleanHost.split(':').last) ?? 8728) : 8728;
      return await _probeRouterOsApi(
        host: hostOnly,
        port: port,
        username: username,
        password: password,
        connectionType: '$connectionType (API :$port)',
      );
    }

    final isExplicitHttps = cleanHost.contains(':443') || ip.trim().startsWith('https://');
    final isExplicitHttp = cleanHost.contains(':80') || ip.trim().startsWith('http://');
    final schemes = isExplicitHttps
        ? ['https']
        : (isExplicitHttp ? ['http'] : ['http', 'https']);
    DiscoveredRouter? conclusiveFailureRouter;

    for (final scheme in schemes) {
      final client = createRouterClient(timeout: const Duration(seconds: 6));
      try {
        final uri = Uri.parse("$scheme://$cleanHost/rest/system/resource");
        final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

        final sw = Stopwatch()..start();
        final response = await client.get(
          uri,
          headers: {
            'Authorization': authHeader,
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 6));
        sw.stop();

        final rawBody = response.body.trim();

        // 1. Success (HTTP 200)
        if (response.statusCode == 200) {
          // Check if response is actually HTML (Hotspot captive portal redirect or WebFig)
          if (rawBody.startsWith('<') ||
              rawBody.toLowerCase().contains('<!doctype') ||
              rawBody.toLowerCase().contains('<html')) {
            final isHotspot = rawBody.toLowerCase().contains('hotspot') ||
                rawBody.toLowerCase().contains('login');
            final isWebfig = rawBody.toLowerCase().contains('webfig') ||
                rawBody.toLowerCase().contains('routeros');
            final snippet = rawBody.length > 80 ? rawBody.substring(0, 80).replaceAll('\n', ' ') : rawBody;

            final errorDesc = isHotspot
                ? 'HotSpot Captive Portal intercepted port 80 at $scheme://$cleanHost. Your phone is on the router Wi-Fi, but captive portal redirected HTTP to login page. Log in to Wi-Fi HotSpot or set your phone IP as Bypassed in IP > HotSpot > IP Bindings.'
                : (isWebfig
                    ? 'MikroTik WebFig responded on Port 80 at $scheme://$cleanHost, but REST API (/rest) returned HTML. Check that RouterOS v7.1+ REST API is enabled.'
                    : 'Host responded at $scheme://$cleanHost on Port 80, but returned HTML instead of RouterOS REST API.');

            return DiscoveredRouter(
              ip: '$scheme://$cleanHost',
              identity: isHotspot
                  ? 'MikroTik HotSpot Portal'
                  : (isWebfig ? 'MikroTik WebFig' : 'Web Server (HTML)'),
              version: isHotspot ? 'RouterOS (Captive Portal)' : (isWebfig ? 'RouterOS WebFig' : 'N/A'),
              cpuLoad: 'N/A',
              uptime: 'N/A',
              totalMemory: 'N/A',
              isReachable: isHotspot || isWebfig,
              connectionType: connectionType,
              latencyMs: sw.elapsedMilliseconds,
              authFailed: false,
              statusCode: 200,
              captivePortalIntercepted: isHotspot,
              rawResponseSnippet: snippet,
              errorMessage: errorDesc,
            );
          }

          try {
            final dynamic decoded = jsonDecode(response.body);
            final Map<String, dynamic> data = decoded is List
                ? (decoded.isNotEmpty ? Map<String, dynamic>.from(decoded.first as Map) : <String, dynamic>{})
                : Map<String, dynamic>.from(decoded as Map);

            return DiscoveredRouter(
              ip: '$scheme://$cleanHost',
              identity: data['board-name']?.toString() ?? data['platform']?.toString() ?? 'MikroTik Gateway',
              version: data['version']?.toString() ?? 'RouterOS v7',
              cpuLoad: '${data['cpu-load'] ?? 0}%',
              uptime: data['uptime']?.toString() ?? '0m',
              totalMemory: '${((data['total-memory'] ?? 0) / (1024 * 1024)).toStringAsFixed(0)} MB',
              isReachable: true,
              connectionType: connectionType,
              latencyMs: sw.elapsedMilliseconds,
              authFailed: false,
              statusCode: 200,
            );
          } catch (e) {
            return DiscoveredRouter(
              ip: '$scheme://$cleanHost',
              identity: 'MikroTik Gateway',
              version: 'RouterOS v7',
              cpuLoad: 'N/A',
              uptime: 'N/A',
              totalMemory: 'N/A',
              isReachable: true,
              connectionType: connectionType,
              latencyMs: sw.elapsedMilliseconds,
              authFailed: false,
              statusCode: 200,
              errorMessage: 'Received HTTP 200 from $scheme://$cleanHost on Port 80, but failed to parse JSON: $e',
            );
          }
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          return DiscoveredRouter(
            ip: '$scheme://$cleanHost',
            identity: 'MikroTik Gateway (Auth Failed)',
            version: 'RouterOS v7',
            cpuLoad: 'N/A',
            uptime: 'N/A',
            totalMemory: 'N/A',
            isReachable: true,
            connectionType: connectionType,
            latencyMs: sw.elapsedMilliseconds,
            authFailed: true,
            statusCode: response.statusCode,
            errorMessage: 'Login failed (HTTP ${response.statusCode}) on Port 80: Invalid password for user "$username". Check admin password in Router LAN Settings.',
          );
        } else if (response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 307) {
          final loc = response.headers['location'] ?? '';
          return DiscoveredRouter(
            ip: '$scheme://$cleanHost',
            identity: 'MikroTik HotSpot (Redirect)',
            version: 'RouterOS (Captive Portal)',
            cpuLoad: 'N/A',
            uptime: 'N/A',
            totalMemory: 'N/A',
            isReachable: true,
            connectionType: connectionType,
            latencyMs: sw.elapsedMilliseconds,
            statusCode: response.statusCode,
            captivePortalIntercepted: true,
            errorMessage: 'HotSpot Captive Portal redirected HTTP to ${loc.isNotEmpty ? loc : "login page"}. Log in to Wi-Fi HotSpot or set phone IP as Bypassed in IP > HotSpot > IP Bindings.',
          );
        } else if (response.statusCode == 404) {
          // Check if system identity or root WebFig is reachable
          try {
            final idRes = await client.get(
              Uri.parse("$scheme://$cleanHost/rest/system/identity"),
              headers: {
                'Authorization': authHeader,
                'Accept': 'application/json',
              },
            ).timeout(const Duration(seconds: 3));
            if (idRes.statusCode == 200) {
              final dynamic idDecoded = jsonDecode(idRes.body);
              final name = (idDecoded is Map) ? (idDecoded['name']?.toString() ?? 'MikroTik Gateway') : 'MikroTik Gateway';
              return DiscoveredRouter(
                ip: '$scheme://$cleanHost',
                identity: name,
                version: 'RouterOS v7',
                cpuLoad: 'N/A',
                uptime: 'N/A',
                totalMemory: 'N/A',
                isReachable: true,
                connectionType: connectionType,
                latencyMs: sw.elapsedMilliseconds,
                authFailed: false,
                statusCode: 200,
              );
            }
          } catch (_) {}

          try {
            final webfigRes = await client.get(Uri.parse('$scheme://$cleanHost/')).timeout(const Duration(seconds: 3));
            if (webfigRes.statusCode == 200 && (webfigRes.body.contains('RouterOS') || webfigRes.body.contains('WebFig'))) {
              return DiscoveredRouter(
                ip: '$scheme://$cleanHost',
                identity: 'MikroTik WebFig (REST 404)',
                version: 'RouterOS (REST API missing)',
                cpuLoad: 'N/A',
                uptime: 'N/A',
                totalMemory: 'N/A',
                isReachable: true,
                connectionType: connectionType,
                latencyMs: sw.elapsedMilliseconds,
                statusCode: 404,
                errorMessage: 'WebFig is reachable on Port 80 at $scheme://$cleanHost, but REST API (/rest) returned 404. Ensure RouterOS v7.1+ is running and REST API is enabled.',
              );
            }
          } catch (_) {}

          return DiscoveredRouter(
            ip: '$scheme://$cleanHost',
            identity: 'Endpoint (HTTP 404)',
            version: 'N/A',
            cpuLoad: 'N/A',
            uptime: 'N/A',
            totalMemory: 'N/A',
            isReachable: false,
            connectionType: connectionType,
            statusCode: 404,
            errorMessage: 'Endpoint returned HTTP 404 Not Found at $scheme://$cleanHost/rest/system/resource.',
          );
        } else {
          return DiscoveredRouter(
            ip: '$scheme://$cleanHost',
            identity: 'Gateway (HTTP ${response.statusCode})',
            version: 'N/A',
            cpuLoad: 'N/A',
            uptime: 'N/A',
            totalMemory: 'N/A',
            isReachable: false,
            connectionType: connectionType,
            statusCode: response.statusCode,
            errorMessage: 'Router returned HTTP ${response.statusCode} on Port 80: ${rawBody.length > 80 ? rawBody.substring(0, 80) : rawBody}',
          );
        }
      } catch (e) {
        String msg;
        if (e is TimeoutException) {
          msg = 'Connection timed out (6s) reaching $scheme://$cleanHost on Port 80. Router took too long to reply.';
        } else if (e is SocketException) {
          if (e.osError?.errorCode == 111 || e.message.toLowerCase().contains('connection refused')) {
            msg = 'Connection refused at $cleanHost:80. Port is closed or RouterOS www service is disabled.';
          } else if (e.osError?.errorCode == 101 ||
              e.message.toLowerCase().contains('network is unreachable') ||
              e.message.toLowerCase().contains('no route')) {
            msg = 'Network unreachable to $cleanHost. Verify your phone is connected to the router Wi-Fi.';
          } else {
            msg = 'Network socket error to $cleanHost: ${e.message}';
          }
        } else if (e is HandshakeException) {
          msg = 'TLS/SSL handshake error on $scheme://$cleanHost: ${e.message}';
        } else {
          msg = 'Probe error on $scheme://$cleanHost: $e';
        }

        conclusiveFailureRouter ??= DiscoveredRouter(
          ip: '$scheme://$cleanHost',
          identity: 'Unreachable Gateway',
          version: 'N/A',
          cpuLoad: 'N/A',
          uptime: 'N/A',
          totalMemory: 'N/A',
          isReachable: false,
          connectionType: connectionType,
          errorMessage: msg,
        );
      } finally {
        client.close();
      }
    }

    return conclusiveFailureRouter;
  }

  /// Synchronously provisions a HotSpot user/voucher directly onto the MikroTik router hardware
  /// via RouterOS REST API (/rest/ip/hotspot/user) or RouterOS binary API on Port 8728.
  /// Works over Local LAN (http://192.168.88.1, 192.168.88.1:8728) or Remote Tunnel.
  static Future<bool> createHotspotUserDirectly({
    required String endpoint,
    String username = "admin",
    String password = "",
    required String code,
    String? pass,
    String profile = "default",
    int? sessionTimeoutSeconds,
    int? limitBytesTotal,
    int? sharedUsers,
    String comment = "wavepass-provisioned",
  }) async {
    var raw = endpoint.trim();
    if (raw.isEmpty) return false;

    // 1. If endpoint is explicit Port 8728 or api scheme, provision directly via native RouterOS API
    if (raw.contains(':8728') || raw.startsWith('api://')) {
      var host = raw;
      if (host.startsWith('api://')) host = host.substring(6);
      if (host.startsWith('http://')) host = host.substring(7);
      if (host.startsWith('https://')) host = host.substring(8);
      int port = 8728;
      if (host.contains(':')) {
        final parts = host.split(':');
        host = parts[0];
        port = int.tryParse(parts[1]) ?? 8728;
      }
      if (host.contains('/')) host = host.split('/').first;

      final client = MikrotikApiClient(host: host, port: port);
      try {
        final ok = await client.connectAndLogin(username, password);
        if (ok) {
          return await client.createHotspotUser(
            code: code,
            pass: pass,
            profile: profile,
            sessionTimeoutSeconds: sessionTimeoutSeconds,
            limitBytesTotal: limitBytesTotal,
            sharedUsers: sharedUsers,
            comment: comment,
          );
        }
        return false;
      } catch (e) {
        debugPrint('Port $port API user add error: $e');
        return false;
      } finally {
        await client.close();
      }
    }

    // 2. Otherwise attempt HTTP REST API first
    final client = createRouterClient();
    bool httpSuccess = false;
    try {
      var normalized = raw;
      if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
        normalized = 'http://$normalized';
      }
      if (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }

      final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      final headers = {
        'Authorization': authHeader,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final payload = <String, dynamic>{
        'name': code,
        'password': pass ?? code,
        'profile': profile,
        if (sessionTimeoutSeconds != null && sessionTimeoutSeconds > 0)
          'limit-uptime': '${sessionTimeoutSeconds}s',
        if (limitBytesTotal != null && limitBytesTotal > 0)
          'limit-bytes-total': limitBytesTotal.toString(),
        if (sharedUsers != null && sharedUsers > 0)
          'shared-users': sharedUsers.toString(),
        'comment': comment,
      };

      // 2a. Standard RouterOS v7 PUT /rest/ip/hotspot/user
      final putUri = Uri.parse('$normalized/rest/ip/hotspot/user');
      http.Response res;
      try {
        res = await client.put(
          putUri,
          headers: headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        res = http.Response('timeout', 504);
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        httpSuccess = true;
      } else if (res.statusCode == 400 && profile != 'default') {
        payload['profile'] = 'default';
        try {
          final retryRes = await client.put(
            putUri,
            headers: headers,
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 4));
          if (retryRes.statusCode >= 200 && retryRes.statusCode < 300) {
            httpSuccess = true;
          }
        } catch (_) {}
      } else if (res.statusCode == 404 || res.statusCode == 405) {
        // 2b. Fallback to POST /rest/ip/hotspot/user/add
        final postUri = Uri.parse('$normalized/rest/ip/hotspot/user/add');
        try {
          final postRes = await client.post(
            postUri,
            headers: headers,
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 5));
          if (postRes.statusCode >= 200 && postRes.statusCode < 300) {
            httpSuccess = true;
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Direct router HTTP provisioning error: $e');
    } finally {
      client.close();
    }

    return httpSuccess;
  }

  /// Orchestrates direct router provisioning using cached router credentials & endpoints.
  /// Tries local LAN direct first; if unreachable, falls back to remote tunnel endpoint.
  static Future<Map<String, dynamic>> provisionVoucherDualRoute({
    required String code,
    String? pass,
    String profile = "default",
    int? sessionTimeoutSeconds,
    int? limitBytesTotal,
    int? sharedUsers,
    String? localIp,
    String? tunnelEndpoint,
    String? username,
    String? password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveLocalIp = localIp ?? prefs.getString(keyRouterLocalIp) ?? '192.168.88.1';
    final effectiveTunnel = tunnelEndpoint ?? prefs.getString(keyRouterTunnelEndpoint);
    final effectiveUser = username ?? prefs.getString(keyRouterUsername) ?? 'admin';
    final effectivePass = password ?? prefs.getString(keyRouterPassword) ?? '';

    // 1. Try local LAN direct first
    final localSuccess = await createHotspotUserDirectly(
      endpoint: effectiveLocalIp,
      username: effectiveUser,
      password: effectivePass,
      code: code,
      pass: pass,
      profile: profile,
      sessionTimeoutSeconds: sessionTimeoutSeconds,
      limitBytesTotal: limitBytesTotal,
      sharedUsers: sharedUsers,
    );

    if (localSuccess) {
      return {'success': true, 'mode': 'local', 'endpoint': effectiveLocalIp};
    }

    // 2. Fallback to tunnel endpoint if configured
    if (effectiveTunnel != null && effectiveTunnel.trim().isNotEmpty) {
      final tunnelSuccess = await createHotspotUserDirectly(
        endpoint: effectiveTunnel,
        username: effectiveUser,
        password: effectivePass,
        code: code,
        pass: pass,
        profile: profile,
        sessionTimeoutSeconds: sessionTimeoutSeconds,
        limitBytesTotal: limitBytesTotal,
        sharedUsers: sharedUsers,
      );
      if (tunnelSuccess) {
        return {'success': true, 'mode': 'tunnel', 'endpoint': effectiveTunnel};
      }
    }

    return {'success': false, 'mode': 'none', 'error': 'Router unreachable via LAN and Tunnel'};
  }

  /// Reboot router via RouterOS REST API over local subnet or tunnel endpoint
  static Future<bool> rebootRouter({
    String? endpoint,
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    if (endpoint != null && (endpoint.contains(':8728') || endpoint.startsWith('api://'))) {
      var host = endpoint.trim();
      if (host.startsWith('api://')) host = host.substring(6);
      int port = 8728;
      if (host.contains(':')) {
        final parts = host.split(':');
        host = parts[0];
        port = int.tryParse(parts[1]) ?? 8728;
      }
      final api = MikrotikApiClient(host: host, port: port);
      try {
        if (await api.connectAndLogin(username, password)) {
          await api.executeSentence(['/system/reboot']);
          return true;
        }
      } catch (_) {
        return false;
      } finally {
        await api.close();
      }
    }

    final client = createRouterClient();
    try {
      var target = (endpoint != null && endpoint.trim().isNotEmpty) ? endpoint.trim() : 'http://$ip';
      if (!target.startsWith('http://') && !target.startsWith('https://')) {
        target = 'http://$target';
      }
      if (target.endsWith('/')) {
        target = target.substring(0, target.length - 1);
      }

      final uri = Uri.parse("$target/rest/system/reboot");
      final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      final response = await client.post(
        uri,
        headers: {
          'Authorization': authHeader,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Provision via Box Barcode Serial Number
  static Future<bool> provisionWithSerial({
    required String serialNumber,
    required String venueId,
    required String routerName,
    String? localIp,
  }) async {
    try {
      final res = await WavePassApi.instance.createRouter(
        venueId: venueId,
        name: routerName.isNotEmpty ? routerName : 'MikroTik-$serialNumber',
        endpoint: localIp ?? 'http://192.168.88.1',
        connectionMode: 'local',
      );
      return res['id'] != null || res['status'] == 200 || res['status'] == 201;
    } catch (_) {
      return false;
    }
  }

  /// Hardware Execution: Installs the Hotspot profile, DNS captive portal,
  /// rate limits, and walled garden directly on the MikroTik router via RouterOS REST API.
  static Future<Map<String, dynamic>> installHotspotOnRouter({
    required String ip,
    required String username,
    required String password,
    required String slug,
    required String venueName,
    String? tunnelEndpoint,
  }) async {
    final client = createRouterClient();
    final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    final headers = {
      'Authorization': authHeader,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final results = <String, dynamic>{
      'identity': false,
      'profile': false,
      'walledGarden': false,
      'hotspot': false,
      'userProfiles': false,
      'cleanupScheduler': false,
      'errors': <String>[],
    };

    try {
      // 1. Set System Identity: WavePass-$slug
      try {
        final idUri = Uri.parse("http://$ip/rest/system/identity");
        final idRes = await client.patch(
          idUri,
          headers: headers,
          body: jsonEncode({'name': 'WavePass-$slug'}),
        ).timeout(const Duration(seconds: 4));
        results['identity'] = idRes.statusCode >= 200 && idRes.statusCode < 300;
      } catch (e) {
        (results['errors'] as List<String>).add('Identity: $e');
      }

      // 2. Add / Update Hotspot Profile: wavepass-profile
      try {
        final profUri = Uri.parse("http://$ip/rest/ip/hotspot/profile");
        final profRes = await client.put(
          profUri,
          headers: headers,
          body: jsonEncode({
            'name': 'wavepass-profile',
            'dns-name': '$slug.nexawavepass.com',
            'hotspot-address': ip,
            'login-by': 'http-chap,http-pap,mac-cookie',
            'html-directory': 'hotspot',
          }),
        ).timeout(const Duration(seconds: 4));
        results['profile'] = profRes.statusCode >= 200 && profRes.statusCode < 300;
      } catch (e) {
        (results['errors'] as List<String>).add('Profile: $e');
      }

      // 3. Add Walled Garden Domains
      try {
        final wgUri = Uri.parse("http://$ip/rest/ip/hotspot/walled-garden");
        final domains = [
          'api.nexawavepass.com',
          '*.nexawavepass.com',
          '*.paystack.co',
          'api.paystack.co',
          '*.supabase.co',
        ];
        int wgSuccess = 0;
        for (final domain in domains) {
          try {
            final res = await client.put(
              wgUri,
              headers: headers,
              body: jsonEncode({'dst-host': domain, 'comment': 'WavePass Walled Garden'}),
            ).timeout(const Duration(seconds: 3));
            if (res.statusCode >= 200 && res.statusCode < 300) wgSuccess++;
          } catch (_) {}
        }
        results['walledGarden'] = wgSuccess > 0;
      } catch (e) {
        (results['errors'] as List<String>).add('WalledGarden: $e');
      }

      // 4. Ensure HotSpot Server on wlan1 or default interface
      try {
        final hsUri = Uri.parse("http://$ip/rest/ip/hotspot");
        final hsRes = await client.put(
          hsUri,
          headers: headers,
          body: jsonEncode({
            'name': 'wavepass-hotspot',
            'interface': 'wlan1',
            'profile': 'wavepass-profile',
            'disabled': 'false',
          }),
        ).timeout(const Duration(seconds: 4));
        results['hotspot'] = hsRes.statusCode >= 200 && hsRes.statusCode < 300;
      } catch (e) {
        (results['errors'] as List<String>).add('HotSpot: $e');
      }

      // 5. Configure Standard Rate-Limit User Profiles (Mikhmon Parity)
      try {
        final userProfUri = Uri.parse("http://$ip/rest/ip/hotspot/user/profile");
        final tiers = [
          {'name': 'profile_1h', 'rate-limit': '10M/5M', 'shared-users': '1', 'comment': 'WavePass 1h'},
          {'name': 'profile_12h', 'rate-limit': '15M/5M', 'shared-users': '1', 'comment': 'WavePass 12h'},
          {'name': 'profile_1d', 'rate-limit': '20M/10M', 'shared-users': '1', 'comment': 'WavePass 24h'},
        ];
        int tierSuccess = 0;
        for (final tier in tiers) {
          try {
            final tRes = await client.put(
              userProfUri,
              headers: headers,
              body: jsonEncode(tier),
            ).timeout(const Duration(seconds: 3));
            if (tRes.statusCode >= 200 && tRes.statusCode < 300) tierSuccess++;
          } catch (_) {}
        }
        results['userProfiles'] = tierSuccess > 0;
      } catch (e) {
        (results['errors'] as List<String>).add('UserProfiles: $e');
      }

      // 6. Inject Low-RAM Memory Auto-Cleanup Script & 2-Hour Scheduler
      try {
        final scriptUri = Uri.parse("http://$ip/rest/system/script");
        await client.put(
          scriptUri,
          headers: headers,
          body: jsonEncode({
            'name': 'wavepass-cleanup',
            'source': '/ip hotspot user remove [find comment="expired"]',
            'comment': 'WavePass low-RAM expired user cleanup',
          }),
        ).timeout(const Duration(seconds: 3));

        final schedUri = Uri.parse("http://$ip/rest/system/scheduler");
        final schedRes = await client.put(
          schedUri,
          headers: headers,
          body: jsonEncode({
            'name': 'wavepass-cleanup',
            'interval': '2h',
            'on-event': 'wavepass-cleanup',
            'comment': 'WavePass 2-hour user cleanup',
          }),
        ).timeout(const Duration(seconds: 3));
        results['cleanupScheduler'] = schedRes.statusCode >= 200 && schedRes.statusCode < 300;
      } catch (e) {
        (results['errors'] as List<String>).add('CleanupScheduler: $e');
      }

      final anySuccess = results['identity'] == true ||
          results['profile'] == true ||
          results['walledGarden'] == true ||
          results['hotspot'] == true;

      results['success'] = anySuccess;

      // Persist router credentials and endpoints locally for seamless synchronous voucher creation
      if (anySuccess) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(keyRouterLocalIp, ip);
          await prefs.setString(keyRouterUsername, username);
          await prefs.setString(keyRouterPassword, password);
          if (tunnelEndpoint != null && tunnelEndpoint.isNotEmpty) {
            await prefs.setString(keyRouterTunnelEndpoint, tunnelEndpoint);
          }
        } catch (_) {}
      }

      return results;
    } finally {
      client.close();
    }
  }

  /// Queries live active sessions directly from the MikroTik hardware (/rest/ip/hotspot/active).
  static Future<List<Map<String, dynamic>>> fetchActiveHotspotUsers({
    String? endpoint,
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    final client = createRouterClient();
    try {
      var target = (endpoint != null && endpoint.trim().isNotEmpty) ? endpoint.trim() : 'http://$ip';
      if (!target.startsWith('http://') && !target.startsWith('https://')) {
        target = 'http://$target';
      }
      if (target.endsWith('/')) {
        target = target.substring(0, target.length - 1);
      }

      final uri = Uri.parse("$target/rest/ip/hotspot/active");
      final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      final res = await client.get(
        uri,
        headers: {
          'Authorization': authHeader,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
    return [];
  }

  /// Disconnects an active hotspot client directly on the physical MikroTik router.
  static Future<bool> disconnectHotspotUser({
    String? endpoint,
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
    required String activeIdOrUser,
  }) async {
    final client = createRouterClient();
    try {
      var target = (endpoint != null && endpoint.trim().isNotEmpty) ? endpoint.trim() : 'http://$ip';
      if (!target.startsWith('http://') && !target.startsWith('https://')) {
        target = 'http://$target';
      }
      if (target.endsWith('/')) {
        target = target.substring(0, target.length - 1);
      }

      final uri = Uri.parse("$target/rest/ip/hotspot/active/$activeIdOrUser");
      final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      final res = await client.delete(
        uri,
        headers: {
          'Authorization': authHeader,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}
