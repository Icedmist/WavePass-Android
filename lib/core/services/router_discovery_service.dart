import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
    // In production, this posts the serial to Supabase/NestJS to attach to the venue
    await Future.delayed(const Duration(milliseconds: 1200));
    return true;
  }
}
