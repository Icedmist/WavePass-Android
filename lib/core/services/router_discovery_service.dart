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

    final hostOnly = cleanHost.contains(':') ? cleanHost.split(':').first : cleanHost;
    final explicitPort = cleanHost.contains(':') ? cleanHost.split(':').last : null;
    final isExplicitHttps = cleanHost.contains(':443') || ip.trim().startsWith('https://');
    // Always permit https fallback when probing http (e.g. when rest-plain is disabled by default on RouterOS v7)
    final schemes = isExplicitHttps ? ['https'] : ['http', 'https'];
    DiscoveredRouter? conclusiveFailureRouter;

    for (final scheme in schemes) {
      final client = createRouterClient(timeout: const Duration(seconds: 6));
      try {
        final targetHost = scheme == 'https'
            ? ((explicitPort != null && explicitPort != '80') ? '$hostOnly:$explicitPort' : hostOnly)
            : cleanHost;
        final uri = Uri.parse("$scheme://$targetHost/rest/system/resource");
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
                ? 'HotSpot Captive Portal intercepted port 80 at $scheme://$targetHost. Your phone is on the router Wi-Fi, but captive portal redirected HTTP to login page. Log in to Wi-Fi HotSpot or set your phone IP as Bypassed in IP > HotSpot > IP Bindings.'
                : (isWebfig
                    ? 'MikroTik WebFig responded on Port 80 at $scheme://$targetHost, but REST API (/rest) returned HTML. Run in MikroTik Terminal: /ip/service/webserver/set rest-plain=yes'
                    : 'Host responded at $scheme://$targetHost on Port 80, but returned HTML instead of RouterOS REST API.');

            return DiscoveredRouter(
              ip: '$scheme://$targetHost',
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
              ip: '$scheme://$targetHost',
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
              ip: '$scheme://$targetHost',
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
              errorMessage: 'Received HTTP 200 from $scheme://$targetHost on Port 80, but failed to parse JSON: $e',
            );
          }
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          return DiscoveredRouter(
            ip: '$scheme://$targetHost',
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
            ip: '$scheme://$targetHost',
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
              Uri.parse("$scheme://$targetHost/rest/system/identity"),
              headers: {
                'Authorization': authHeader,
                'Accept': 'application/json',
              },
            ).timeout(const Duration(seconds: 3));
            if (idRes.statusCode == 200) {
              final dynamic idDecoded = jsonDecode(idRes.body);
              final name = (idDecoded is Map) ? (idDecoded['name']?.toString() ?? 'MikroTik Gateway') : 'MikroTik Gateway';
              return DiscoveredRouter(
                ip: '$scheme://$targetHost',
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

          bool webfigFound = false;
          try {
            final webfigRes = await client.get(Uri.parse('$scheme://$targetHost/')).timeout(const Duration(seconds: 3));
            if (webfigRes.statusCode == 200 && (webfigRes.body.contains('RouterOS') || webfigRes.body.contains('WebFig'))) {
              webfigFound = true;
            }
          } catch (_) {}

          final failure404 = DiscoveredRouter(
            ip: '$scheme://$targetHost',
            identity: webfigFound ? 'MikroTik WebFig (REST 404)' : 'MikroTik Gateway (REST 404)',
            version: 'RouterOS v7 (REST Disabled)',
            cpuLoad: 'N/A',
            uptime: 'N/A',
            totalMemory: 'N/A',
            isReachable: webfigFound,
            connectionType: connectionType,
            latencyMs: sw.elapsedMilliseconds,
            statusCode: 404,
            errorMessage: 'RouterOS v7 REST API is disabled on Port 80 (HTTP 404). Run in MikroTik Terminal: /ip/service/webserver/set rest-plain=yes',
          );

          conclusiveFailureRouter = failure404;

          // If scheme is HTTP, continue to HTTPS (rest-secure on port 443) before returning failure
          if (scheme == 'http' && schemes.contains('https')) {
            continue;
          }

          return failure404;
        } else {
          return DiscoveredRouter(
            ip: '$scheme://$targetHost',
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

    if (conclusiveFailureRouter != null && (conclusiveFailureRouter.statusCode == 404 || !conclusiveFailureRouter.isReachable)) {
      // If HTTP Port 80 returned 404 (HotSpot captive portal / wproxy interception) and HTTPS failed,
      // probe native RouterOS API on Port 8728 (Micro Voucher / Mikhmon parity).
      try {
        final apiRouter = await _probeRouterOsApi(
          host: hostOnly,
          port: 8728,
          username: username,
          password: password,
          connectionType: '$connectionType (API :8728)',
          timeout: const Duration(seconds: 4),
        );
        if (apiRouter != null && apiRouter.isReachable && !apiRouter.authFailed) {
          return apiRouter;
        } else if (apiRouter != null && apiRouter.authFailed) {
          // If port 8728 is open but password failed, surface the auth failed router
          return apiRouter;
        }
      } catch (_) {}
    }

    return conclusiveFailureRouter;
  }

  /// Computes the appropriate user profile name for a given duration in seconds.
  static String profileForDuration(int seconds) {
    if (seconds <= 1800) return 'profile_30m';
    if (seconds <= 3600) return 'profile_1h';
    if (seconds <= 7200) return 'profile_2h';
    if (seconds <= 10800) return 'profile_3h';
    if (seconds <= 21600) return 'profile_6h';
    if (seconds <= 43200) return 'profile_12h';
    if (seconds <= 86400) return 'profile_1d';
    if (seconds <= 604800) return 'profile_7d';
    return 'profile_30d';
  }

  /// Formats seconds into RouterOS standard time representation (e.g. 30m, 1h, 12h, 1d, 7d).
  static String formatRouterOsDuration(int seconds) {
    if (seconds <= 0) return '0s';
    if (seconds % 86400 == 0) return '${seconds ~/ 86400}d';
    if (seconds % 3600 == 0) return '${seconds ~/ 3600}h';
    if (seconds % 60 == 0) return '${seconds ~/ 60}m';

    final d = seconds ~/ 86400;
    var rem = seconds % 86400;
    final h = rem ~/ 3600;
    rem = rem % 3600;
    final m = rem ~/ 60;
    final s = rem % 60;

    final buf = StringBuffer();
    if (d > 0) buf.write('${d}d');
    if (h > 0) buf.write('${h}h');
    if (m > 0) buf.write('${m}m');
    if (s > 0) buf.write('${s}s');
    return buf.toString();
  }

  /// Standard duration-based rate-limit profiles configured on RouterOS with hard timeouts.
  static List<Map<String, String>> get standardDurationProfiles => [
    {
      'name': 'profile_30m',
      'rate-limit': '10M/5M',
      'shared-users': '1',
      'session-timeout': '30m',
      'keepalive-timeout': '2m',
      'idle-timeout': '5m',
      'status-autorefresh': '1m',
      'comment': 'WavePass 30m',
    },
    {
      'name': 'profile_1h',
      'rate-limit': '10M/5M',
      'shared-users': '1',
      'session-timeout': '1h',
      'keepalive-timeout': '2m',
      'idle-timeout': '5m',
      'status-autorefresh': '1m',
      'comment': 'WavePass 1h',
    },
    {
      'name': 'profile_2h',
      'rate-limit': '10M/5M',
      'shared-users': '1',
      'session-timeout': '2h',
      'keepalive-timeout': '2m',
      'idle-timeout': '5m',
      'status-autorefresh': '1m',
      'comment': 'WavePass 2h',
    },
    {
      'name': 'profile_3h',
      'rate-limit': '15M/5M',
      'shared-users': '1',
      'session-timeout': '3h',
      'keepalive-timeout': '2m',
      'idle-timeout': '5m',
      'status-autorefresh': '1m',
      'comment': 'WavePass 3h',
    },
    {
      'name': 'profile_6h',
      'rate-limit': '15M/5M',
      'shared-users': '1',
      'session-timeout': '6h',
      'keepalive-timeout': '2m',
      'idle-timeout': '5m',
      'status-autorefresh': '1m',
      'comment': 'WavePass 6h',
    },
    {
      'name': 'profile_12h',
      'rate-limit': '15M/5M',
      'shared-users': '1',
      'session-timeout': '12h',
      'keepalive-timeout': '2m',
      'idle-timeout': '5m',
      'status-autorefresh': '1m',
      'comment': 'WavePass 12h',
    },
    {
      'name': 'profile_1d',
      'rate-limit': '20M/10M',
      'shared-users': '1',
      'session-timeout': '1d',
      'keepalive-timeout': '2m',
      'idle-timeout': '5m',
      'status-autorefresh': '1m',
      'comment': 'WavePass 24h',
    },
    {
      'name': 'profile_7d',
      'rate-limit': '20M/10M',
      'shared-users': '1',
      'session-timeout': '7d',
      'keepalive-timeout': '2m',
      'idle-timeout': '5m',
      'status-autorefresh': '1m',
      'comment': 'WavePass 7d',
    },
    {
      'name': 'profile_30d',
      'rate-limit': '25M/10M',
      'shared-users': '1',
      'session-timeout': '30d',
      'keepalive-timeout': '2m',
      'idle-timeout': '5m',
      'status-autorefresh': '1m',
      'comment': 'WavePass 30d',
    },
  ];

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

      final uptimeStr = sessionTimeoutSeconds != null && sessionTimeoutSeconds > 0
          ? formatRouterOsDuration(sessionTimeoutSeconds)
          : null;

      final payload = <String, dynamic>{
        'name': code,
        'password': pass ?? code,
        'profile': profile,
        if (uptimeStr != null && uptimeStr.isNotEmpty)
          'limit-uptime': uptimeStr,
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
      } else if (res.statusCode == 400 || res.statusCode == 409) {
        // If user already exists, find ID and update credentials/limits via PATCH (resetting uptime to 0s)
        try {
          final getUri = Uri.parse('$normalized/rest/ip/hotspot/user?name=$code');
          final getRes = await client.get(getUri, headers: headers).timeout(const Duration(seconds: 4));
          if (getRes.statusCode >= 200 && getRes.statusCode < 300) {
            final dynamic list = jsonDecode(getRes.body);
            if (list is List && list.isNotEmpty) {
              final id = list.first['.id'];
              if (id != null) {
                final patchUri = Uri.parse('$normalized/rest/ip/hotspot/user/$id');
                final patchPayload = Map<String, dynamic>.from(payload);
                patchPayload['uptime'] = '0s'; // Reset spent uptime for re-provisioned pass
                final patchRes = await client.patch(
                  patchUri,
                  headers: headers,
                  body: jsonEncode(patchPayload),
                ).timeout(const Duration(seconds: 4));
                if (patchRes.statusCode >= 200 && patchRes.statusCode < 300) {
                  httpSuccess = true;
                }
              }
            }
          }
        } catch (_) {}

        // If profile was custom and not yet installed, retry with 'default' profile
        if (!httpSuccess && profile != 'default') {
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
        }
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

        // 2c. Fallback to HTTPS /rest/ip/hotspot/user if HTTP returned 404 (rest-secure parity)
        if (!httpSuccess && normalized.startsWith('http://')) {
          var httpsHost = normalized.substring(7);
          if (httpsHost.endsWith(':80')) {
            httpsHost = httpsHost.substring(0, httpsHost.length - 3);
          }
          final httpsPutUri = Uri.parse('https://$httpsHost/rest/ip/hotspot/user');
          try {
            final httpsRes = await client.put(
              httpsPutUri,
              headers: headers,
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 5));
            if (httpsRes.statusCode >= 200 && httpsRes.statusCode < 300) {
              httpSuccess = true;
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Direct router HTTP provisioning error: $e');
    } finally {
      client.close();
    }

    // 3. Fallback to native RouterOS API on Port 8728 (Micro Voucher parity when HotSpot intercepts Port 80)
    if (!httpSuccess) {
      var host = raw;
      if (host.startsWith('http://')) host = host.substring(7);
      if (host.startsWith('https://')) host = host.substring(8);
      if (host.contains(':')) host = host.split(':').first;
      if (host.contains('/')) host = host.split('/').first;

      final client8728 = MikrotikApiClient(host: host, port: 8728, timeout: const Duration(seconds: 5));
      try {
        final ok = await client8728.connectAndLogin(username, password);
        if (ok) {
          return await client8728.createHotspotUser(
            code: code,
            pass: pass,
            profile: profile,
            sessionTimeoutSeconds: sessionTimeoutSeconds,
            limitBytesTotal: limitBytesTotal,
            sharedUsers: sharedUsers,
            comment: comment,
          );
        }
      } catch (e) {
        debugPrint('Fallback Port 8728 provisioning error: $e');
      } finally {
        await client8728.close();
      }
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
  /// rate limits, and walled garden directly on the MikroTik router via RouterOS REST API or native API :8728.
  static Future<Map<String, dynamic>> installHotspotOnRouter({
    required String ip,
    required String username,
    required String password,
    required String slug,
    required String venueName,
    String? tunnelEndpoint,
  }) async {
    var hostOnly = ip.trim();
    if (hostOnly.startsWith('http://')) hostOnly = hostOnly.substring(7);
    if (hostOnly.startsWith('https://')) hostOnly = hostOnly.substring(8);
    if (hostOnly.startsWith('api://')) hostOnly = hostOnly.substring(6);
    int port = 80;
    if (hostOnly.contains(':')) {
      port = int.tryParse(hostOnly.split(':').last) ?? 80;
      hostOnly = hostOnly.split(':').first;
    }
    if (hostOnly.contains('/')) hostOnly = hostOnly.split('/').first;

    // Unconditionally persist router credentials and endpoints locally
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyRouterLocalIp, hostOnly);
      await prefs.setString(keyRouterUsername, username);
      await prefs.setString(keyRouterPassword, password);
      if (tunnelEndpoint != null && tunnelEndpoint.isNotEmpty) {
        await prefs.setString(keyRouterTunnelEndpoint, tunnelEndpoint);
      }
    } catch (_) {}

    // If explicit Port 8728 or API scheme, configure via native RouterOS API directly
    if (port == 8728 || ip.trim().startsWith('api://') || ip.contains(':8728')) {
      final client8728 = MikrotikApiClient(host: hostOnly, port: 8728, timeout: const Duration(seconds: 6));
      try {
        final ok = await client8728.connectAndLogin(username, password);
        if (ok) {
          final res = await client8728.installHotspotConfig(slug: slug, venueName: venueName, localIp: hostOnly);
          return res;
        }
      } catch (e) {
        debugPrint('Port 8728 hotspot installation error: $e');
      } finally {
        await client8728.close();
      }
    }

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
        final idUri = Uri.parse("http://$hostOnly:$port/rest/system/identity");
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
        final profUri = Uri.parse("http://$hostOnly:$port/rest/ip/hotspot/profile");
        final profRes = await client.put(
          profUri,
          headers: headers,
          body: jsonEncode({
            'name': 'wavepass-profile',
            'dns-name': 'wavepass.local',
            'hotspot-address': hostOnly,
            'login-by': 'http-chap,http-pap,mac-cookie',
            'html-directory': 'hotspot',
          }),
        ).timeout(const Duration(seconds: 4));
        results['profile'] = profRes.statusCode >= 200 && profRes.statusCode < 300;
      } catch (e) {
        (results['errors'] as List<String>).add('Profile: $e');
      }

      // 3. Add Walled Garden Domains (HTTP & IP/HTTPS)
      try {
        final wgUri = Uri.parse("http://$hostOnly:$port/rest/ip/hotspot/walled-garden");
        final wgIpUri = Uri.parse("http://$hostOnly:$port/rest/ip/hotspot/walled-garden/ip");
        final domains = [
          'nexawavepass.com',
          '*.nexawavepass.com',
          'api.nexawavepass.com',
          '*.paystack.co',
          'api.paystack.co',
          'checkout.paystack.com',
          'standard.paystack.co',
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
          try {
            await client.put(
              wgIpUri,
              headers: headers,
              body: jsonEncode({'dst-host': domain, 'action': 'accept', 'comment': 'WavePass Walled Garden IP'}),
            ).timeout(const Duration(seconds: 3));
          } catch (_) {}
        }
        results['walledGarden'] = wgSuccess > 0;
      } catch (e) {
        (results['errors'] as List<String>).add('WalledGarden: $e');
      }

      // 4. Ensure HotSpot Server on wlan1 or default interface
      try {
        final hsUri = Uri.parse("http://$hostOnly:$port/rest/ip/hotspot");
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

      // 5. Configure Standard Rate-Limit User Profiles (with hard session timeouts)
      try {
        final userProfUri = Uri.parse("http://$hostOnly:$port/rest/ip/hotspot/user/profile");
        int tierSuccess = 0;
        for (final tier in standardDurationProfiles) {
          try {
            final tRes = await client.put(
              userProfUri,
              headers: headers,
              body: jsonEncode(tier),
            ).timeout(const Duration(seconds: 3));
            if (tRes.statusCode >= 200 && tRes.statusCode < 300) tierSuccess++;
          } catch (_) {}
        }
        // Enforce shared-users=1, keepalives, and idle timeout on 'default' profile
        try {
          await client.put(
            userProfUri,
            headers: headers,
            body: jsonEncode({
              'name': 'default',
              'shared-users': '1',
              'keepalive-timeout': '2m',
              'idle-timeout': '5m',
              'status-autorefresh': '1m',
            }),
          ).timeout(const Duration(seconds: 3));
        } catch (_) {}
        results['userProfiles'] = tierSuccess > 0;
      } catch (e) {
        (results['errors'] as List<String>).add('UserProfiles: $e');
      }

      // 6. Inject Low-RAM Memory Auto-Cleanup Script & 1-Minute Limit Enforcer Scheduler
      try {
        final scriptUri = Uri.parse("http://$hostOnly:$port/rest/system/script");
        const scriptSource = ':foreach a in=[/ip hotspot active find] do={ :local stl [/ip hotspot active get \$a session-time-left]; :if ([:len \$stl] > 0 && \$stl = 0s) do={ /ip hotspot active remove \$a; } }; :foreach u in=[/ip hotspot user find] do={ :local lup [/ip hotspot user get \$u limit-uptime]; :local upt [/ip hotspot user get \$u uptime]; :if ([:len \$lup] > 0 && \$lup != 0s && \$upt >= \$lup) do={ :local un [/ip hotspot user get \$u name]; /ip hotspot active remove [find user=\$un]; /ip hotspot user remove \$u; } }; /ip hotspot user remove [find comment~"expired"]';
        await client.put(
          scriptUri,
          headers: headers,
          body: jsonEncode({
            'name': 'wavepass-cleanup',
            'source': scriptSource,
            'comment': 'WavePass user limit enforcer',
          }),
        ).timeout(const Duration(seconds: 3));

        final schedUri = Uri.parse("http://$hostOnly:$port/rest/system/scheduler");
        final schedRes = await client.put(
          schedUri,
          headers: headers,
          body: jsonEncode({
            'name': 'wavepass-cleanup',
            'interval': '1m',
            'on-event': 'wavepass-cleanup',
            'comment': 'WavePass 1-minute user limit enforcer',
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

      // Enforce No Hotspot Sharing (1-device per voucher, client isolation, anti-tethering filter)
      try {
        await enforceNoHotspotSharing(
          endpoint: tunnelEndpoint,
          ip: ip,
          username: username,
          password: password,
        );
      } catch (_) {}

      // If HTTP REST failed or returned 404 (HotSpot wproxy interception), fallback to native Port 8728 API
      if (!anySuccess) {
        final client8728 = MikrotikApiClient(host: hostOnly, port: 8728, timeout: const Duration(seconds: 6));
        try {
          final ok = await client8728.connectAndLogin(username, password);
          if (ok) {
            final apiResults = await client8728.installHotspotConfig(slug: slug, venueName: venueName, localIp: hostOnly);
            if (apiResults['success'] == true) {
              return apiResults;
            }
          }
        } catch (e) {
          debugPrint('Fallback Port 8728 hotspot installation error: $e');
        } finally {
          await client8728.close();
        }
      }

      return results;
    } finally {
      client.close();
    }
  }

  /// Queries live active sessions directly from the MikroTik hardware (/rest/ip/hotspot/active or Port 8728 API).
  static Future<List<Map<String, dynamic>>> fetchActiveHotspotUsers({
    String? endpoint,
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    // 1. Try REST API
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
        if (data is List && data.isNotEmpty) {
          return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {
    } finally {
      client.close();
    }

    // 2. Fallback to RouterOS Binary API (Port 8728)
    try {
      var hostOnly = (endpoint != null && endpoint.isNotEmpty) ? endpoint : ip;
      hostOnly = hostOnly.replaceAll('http://', '').replaceAll('https://', '').split(':').first.split('/').first;
      if (hostOnly.isEmpty) hostOnly = ip;

      final client8728 = MikrotikApiClient(host: hostOnly, port: 8728, timeout: const Duration(seconds: 5));
      if (await client8728.connect()) {
        if (await client8728.login(username, password)) {
          final users = await client8728.getHotspotActiveUsers();
          await client8728.disconnect();
          return users.map((u) => Map<String, dynamic>.from(u)).toList();
        }
        await client8728.disconnect();
      }
    } catch (_) {}

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
    bool ok = false;
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
      if (res.statusCode == 200 || res.statusCode == 204) {
        ok = true;
      }
    } catch (_) {
    } finally {
      client.close();
    }

    // Fallback: RouterOS API Port 8728
    try {
      var hostOnly = (endpoint != null && endpoint.isNotEmpty) ? endpoint : ip;
      hostOnly = hostOnly.replaceAll('http://', '').replaceAll('https://', '').split(':').first.split('/').first;
      if (hostOnly.isEmpty) hostOnly = ip;

      final client8728 = MikrotikApiClient(host: hostOnly, port: 8728, timeout: const Duration(seconds: 5));
      if (await client8728.connect()) {
        if (await client8728.login(username, password)) {
          final removed = await client8728.disconnectActiveUser(activeIdOrUser);
          if (removed) ok = true;
        }
        await client8728.disconnect();
      }
    } catch (_) {}

    return ok;
  }

  /// Enforces no hotspot sharing on the router hardware:
  /// - 1 device per voucher (shared-users=1)
  /// - blocks hotspot tethering/repeaters (drops ttl 63, 127)
  /// - wireless client isolation (default-forwarding=no)
  static Future<Map<String, dynamic>> enforceNoHotspotSharing({
    String? endpoint,
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    // 1. Try Port 8728 RouterOS API first
    try {
      var hostOnly = (endpoint != null && endpoint.isNotEmpty) ? endpoint : ip;
      hostOnly = hostOnly.replaceAll('http://', '').replaceAll('https://', '').split(':').first.split('/').first;
      if (hostOnly.isEmpty) hostOnly = ip;

      final client8728 = MikrotikApiClient(host: hostOnly, port: 8728, timeout: const Duration(seconds: 6));
      if (await client8728.connect()) {
        if (await client8728.login(username, password)) {
          final res = await client8728.enforceNoHotspotSharing();
          await client8728.disconnect();
          return res;
        }
        await client8728.disconnect();
      }
    } catch (_) {}

    // 2. Fallback: REST API
    final results = <String, dynamic>{
      'success': false,
      'profiles': false,
      'isolation': false,
      'firewallFilter': false,
    };
    final client = createRouterClient();
    try {
      var target = (endpoint != null && endpoint.trim().isNotEmpty) ? endpoint.trim() : 'http://$ip';
      if (!target.startsWith('http://') && !target.startsWith('https://')) {
        target = 'http://$target';
      }
      if (target.endsWith('/')) {
        target = target.substring(0, target.length - 1);
      }

      final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      final headers = {
        'Authorization': authHeader,
        'Content-Type': 'application/json',
      };

      // Enforce shared-users=1 on all user profiles
      try {
        final profRes = await client.get(
          Uri.parse("$target/rest/ip/hotspot/user/profile"),
          headers: headers,
        ).timeout(const Duration(seconds: 4));
        if (profRes.statusCode == 200) {
          final list = jsonDecode(profRes.body);
          if (list is List) {
            for (final p in list) {
              final id = p['.id'];
              if (id != null) {
                await client.patch(
                  Uri.parse("$target/rest/ip/hotspot/user/profile/$id"),
                  headers: headers,
                  body: jsonEncode({'shared-users': '1'}),
                ).timeout(const Duration(seconds: 2));
              }
            }
            results['profiles'] = true;
          }
        }
      } catch (_) {}

      // Wireless client isolation
      try {
        final wlanRes = await client.get(
          Uri.parse("$target/rest/interface/wireless"),
          headers: headers,
        ).timeout(const Duration(seconds: 4));
        if (wlanRes.statusCode == 200) {
          final list = jsonDecode(wlanRes.body);
          if (list is List) {
            for (final w in list) {
              final id = w['.id'];
              if (id != null) {
                await client.patch(
                  Uri.parse("$target/rest/interface/wireless/$id"),
                  headers: headers,
                  body: jsonEncode({'default-forwarding': 'false'}),
                ).timeout(const Duration(seconds: 2));
              }
            }
            results['isolation'] = true;
          }
        }
      } catch (_) {}

      results['success'] = results['profiles'] == true || results['isolation'] == true;
    } catch (_) {
    } finally {
      client.close();
    }

    return results;
  }

  /// Uploads captive portal files (login.html, status.html, logout.html) directly to MikroTik router.
  /// Supports both standard `hotspot/` and `flash/hotspot/` directory layouts.
  static Future<Map<String, bool>> uploadPortalFiles({
    required String ip,
    required String username,
    required String password,
    required Map<String, String> files,
    String? endpoint,
  }) async {
    final results = <String, bool>{};
    var target = (endpoint != null && endpoint.trim().isNotEmpty) ? endpoint.trim() : ip.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      target = 'http://$target';
    }
    if (target.endsWith('/')) {
      target = target.substring(0, target.length - 1);
    }

    final client = createRouterClient();
    final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

    for (final entry in files.entries) {
      final fileName = entry.key;
      final content = entry.value;
      bool success = false;

      for (final folder in ['hotspot', 'flash/hotspot']) {
        if (success) break;
        try {
          final uri = Uri.parse('$target/rest/file/$folder/$fileName');
          final res = await client.put(
            uri,
            headers: {
              'Authorization': authHeader,
              'Content-Type': 'text/html; charset=utf-8',
            },
            body: content,
          ).timeout(const Duration(seconds: 5));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            success = true;
          }
        } catch (_) {}

        if (!success) {
          try {
            final uri = Uri.parse('$target/rest/file');
            final res = await client.post(
              uri,
              headers: {
                'Authorization': authHeader,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'name': '$folder/$fileName',
                'contents': content,
              }),
            ).timeout(const Duration(seconds: 5));
            if (res.statusCode >= 200 && res.statusCode < 300) {
              success = true;
            }
          } catch (_) {}
        }
      }

      results[fileName] = success;
    }
    client.close();
    return results;
  }
}
