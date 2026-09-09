import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'wavepass_api.dart';

class DiscoveredRouter {
  final String ip;
  final String identity;
  final String version;
  final String cpuLoad;
  final String uptime;
  final String totalMemory;
  final bool isReachable;

  DiscoveredRouter({
    required this.ip,
    required this.identity,
    required this.version,
    required this.cpuLoad,
    required this.uptime,
    required this.totalMemory,
    required this.isReachable,
  });
}

class RouterDiscoveryService {
  // Approach 1: Auto-discover MikroTik router over local subnet
  // Tries admin:blank, then wavepass:YOURPASS (setup script), then 192.168.1.1 fallback. Does NOT change admin password.
  static Future<DiscoveredRouter?> discoverLocalRouter({
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    // 1. Probe with supplied creds (default admin:"")
    DiscoveredRouter? router = await _probeRouter(ip, username, password);
    if (router != null) return router;

    // 2. Try wavepass user (created by wavepass-setup.rsc) if admin failed
    if (username == "admin") {
      router = await _probeRouter(ip, "wavepass", password.isEmpty ? "CHANGE_THIS_WAVEPASS_PASSWORD" : password);
      if (router != null) return router;
      // also try wavepass with empty (fresh) — will fail gracefully
      router = await _probeRouter(ip, "wavepass", "");
      if (router != null) return router;
    }

    // 3. If default 192.168.88.1 was specified and failed, probe secondary 192.168.1.1 with both users
    if (ip == "192.168.88.1") {
      router = await _probeRouter("192.168.1.1", username, password);
      if (router != null) return router;
      if (username == "admin") {
        router = await _probeRouter("192.168.1.1", "wavepass", "");
        if (router != null) return router;
      }
    }

    return null;
  }

  static Future<DiscoveredRouter?> _probeRouter(String ip, String username, String password) async {
    final client = http.Client();
    try {
      final uri = Uri.parse("http://$ip/rest/system/resource");
      final authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

      final response = await client.get(
        uri,
        headers: {
          'Authorization': authHeader,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

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
        );
      }
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
    return null;
  }

  // Reboot router via RouterOS REST API over local subnet
  static Future<bool> rebootRouter({
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    final client = http.Client();
    try {
      final uri = Uri.parse("http://$ip/rest/system/reboot");
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

  // Approach 2: Provision via Box Barcode Serial Number
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

  /// Approach 1 Hardware Execution: Installs the Hotspot profile, DNS captive portal,
  /// and walled garden directly on the MikroTik router via RouterOS REST API.
  static Future<Map<String, dynamic>> installHotspotOnRouter({
    required String ip,
    required String username,
    required String password,
    required String slug,
    required String venueName,
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

      // 6. Inject Low-RAM Memory Auto-Cleanup Script & 2-Hour Scheduler (Mikhmon Parity)
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
      return results;
    } finally {
      client.close();
    }
  }

  /// Queries live active sessions directly from the MikroTik hardware (/rest/ip/hotspot/active).
  static Future<List<Map<String, dynamic>>> fetchActiveHotspotUsers({
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    final client = http.Client();
    try {
      final uri = Uri.parse("http://$ip/rest/ip/hotspot/active");
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
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
    required String activeIdOrUser,
  }) async {
    final client = http.Client();
    try {
      final uri = Uri.parse("http://$ip/rest/ip/hotspot/active/$activeIdOrUser");
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
