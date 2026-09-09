import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'wavepass_api.dart';

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

  RouterDualConnectionStatus({
    this.localRouter,
    this.tunnelRouter,
    required this.isLocalOnline,
    required this.isTunnelOnline,
    this.activeEndpoint,
    required this.activeMode,
    this.latencySummary,
  });

  bool get isAnyOnline => isLocalOnline || isTunnelOnline;
}

class RouterDiscoveryService {
  // Preference keys for persistent router configuration
  static const String keyRouterLocalIp = 'wavepass_router_local_ip';
  static const String keyRouterTunnelEndpoint = 'wavepass_router_tunnel_endpoint';
  static const String keyRouterUsername = 'wavepass_router_username';
  static const String keyRouterPassword = 'wavepass_router_password';

  /// Auto-discovers MikroTik router over local subnet.
  /// Uses default admin credentials (default empty password), without creating extra users.
  static Future<DiscoveredRouter?> discoverLocalRouter({
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    // 1. Probe with supplied credentials (default admin:"")
    DiscoveredRouter? router = await _probeRouter(ip, username, password, connectionType: "LAN");
    if (router != null) return router;

    // If password was non-empty and failed, try empty password as fallback for default admin
    if (password.isNotEmpty) {
      router = await _probeRouter(ip, username, "", connectionType: "LAN");
      if (router != null) return router;
    }

    // 2. If default 192.168.88.1 was specified and failed, probe secondary 192.168.1.1 fallback
    if (ip == "192.168.88.1") {
      router = await _probeRouter("192.168.1.1", username, password, connectionType: "LAN");
      if (router != null) return router;
      if (password.isNotEmpty) {
        router = await _probeRouter("192.168.1.1", username, "", connectionType: "LAN");
        if (router != null) return router;
      }
    }

    return null;
  }

  /// Probes any arbitrary HTTP/HTTPS endpoint or IP (LAN or WireGuard/Cloud tunnel).
  static Future<DiscoveredRouter?> probeEndpoint(
    String rawEndpoint, {
    String username = "admin",
    String password = "",
    String connectionType = "Endpoint",
  }) async {
    final client = http.Client();
    try {
      var normalized = rawEndpoint.trim();
      if (normalized.isEmpty) return null;
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
      ).timeout(const Duration(seconds: 4));
      sw.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DiscoveredRouter(
          ip: normalized,
          identity: data['board-name'] ?? data['platform'] ?? 'MikroTik Gateway',
          version: data['version'] ?? 'RouterOS v7',
          cpuLoad: '${data['cpu-load'] ?? 0}%',
          uptime: data['uptime'] ?? '0m',
          totalMemory: '${((data['total-memory'] ?? 0) / (1024 * 1024)).toStringAsFixed(0)} MB',
          isReachable: true,
          connectionType: connectionType,
          latencyMs: sw.elapsedMilliseconds,
        );
      }
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
    return null;
  }

  /// Probes both Local Subnet (LAN Direct) and Remote Cloud/WireGuard Tunnel concurrently.
  static Future<RouterDualConnectionStatus> checkDualConnection({
    String localIp = "192.168.88.1",
    String? tunnelEndpoint,
    String username = "admin",
    String password = "",
  }) async {
    final futures = <Future<DiscoveredRouter?>>[
      discoverLocalRouter(ip: localIp, username: username, password: password),
      if (tunnelEndpoint != null && tunnelEndpoint.trim().isNotEmpty)
        probeEndpoint(tunnelEndpoint, username: username, password: password, connectionType: "Tunnel")
      else
        Future.value(null),
    ];

    final results = await Future.wait(futures);
    final localRouter = results[0];
    final tunnelRouter = results.length > 1 ? results[1] : null;

    final isLocalOnline = localRouter != null && localRouter.isReachable;
    final isTunnelOnline = tunnelRouter != null && tunnelRouter.isReachable;

    String? activeEndpoint;
    String activeMode = 'offline';

    // Prioritize local LAN if available (sub-millisecond latency, no internet reliance)
    if (isLocalOnline) {
      activeEndpoint = 'http://${localRouter.ip}';
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

    return RouterDualConnectionStatus(
      localRouter: localRouter,
      tunnelRouter: tunnelRouter,
      isLocalOnline: isLocalOnline,
      isTunnelOnline: isTunnelOnline,
      activeEndpoint: activeEndpoint,
      activeMode: activeMode,
      latencySummary: latency,
    );
  }

  static Future<DiscoveredRouter?> _probeRouter(
    String ip,
    String username,
    String password, {
    String connectionType = 'LAN',
  }) async {
    final client = http.Client();
    try {
      final uri = Uri.parse("http://$ip/rest/system/resource");
      final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

      final sw = Stopwatch()..start();
      final response = await client.get(
        uri,
        headers: {
          'Authorization': authHeader,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));
      sw.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DiscoveredRouter(
          ip: ip,
          identity: data['board-name'] ?? data['platform'] ?? 'MikroTik Gateway',
          version: data['version'] ?? 'RouterOS v7',
          cpuLoad: '${data['cpu-load'] ?? 0}%',
          uptime: data['uptime'] ?? '0m',
          totalMemory: '${((data['total-memory'] ?? 0) / (1024 * 1024)).toStringAsFixed(0)} MB',
          isReachable: true,
          connectionType: connectionType,
          latencyMs: sw.elapsedMilliseconds,
        );
      }
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
    return null;
  }

  /// Synchronously provisions a HotSpot user/voucher directly onto the MikroTik router hardware
  /// via RouterOS REST API (/rest/ip/hotspot/user).
  /// Works over Local LAN (http://192.168.88.1) or Remote Tunnel.
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
    final client = http.Client();
    try {
      var normalized = endpoint.trim();
      if (normalized.isEmpty) return false;
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

      // 1. First attempt RouterOS v7 standard PUT /rest/ip/hotspot/user
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
        return true;
      }

      // If custom profile returned 400 (e.g. profile doesn't exist yet on router), fallback to 'default'
      if (res.statusCode == 400 && profile != 'default') {
        payload['profile'] = 'default';
        try {
          final retryRes = await client.put(
            putUri,
            headers: headers,
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 4));
          if (retryRes.statusCode >= 200 && retryRes.statusCode < 300) {
            return true;
          }
        } catch (_) {}
      }

      // 2. Fallback to POST /rest/ip/hotspot/user/add (supported by mock-router and custom setups)
      if (res.statusCode == 404 || res.statusCode == 405) {
        final postUri = Uri.parse('$normalized/rest/ip/hotspot/user/add');
        final postRes = await client.post(
          postUri,
          headers: headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 5));
        if (postRes.statusCode >= 200 && postRes.statusCode < 300) {
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('Direct router provisioning error: $e');
      return false;
    } finally {
      client.close();
    }
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
    final client = http.Client();
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
  }) async {
    try {
      final res = await WavePassApi.instance.createRouter(
        venueId: venueId,
        name: routerName.isNotEmpty ? routerName : 'MikroTik-$serialNumber',
        endpoint: 'https://tunnel.nexawavepass.com/$serialNumber',
        connectionMode: 'tunnel',
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
    final client = http.Client();
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
    final client = http.Client();
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
    final client = http.Client();
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
