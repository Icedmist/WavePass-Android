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
  static Future<DiscoveredRouter?> discoverLocalRouter({
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    try {
      final client = http.Client();
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
          identity: data['board-name'] ?? 'MikroTik Gateway',
          version: data['version'] ?? 'RouterOS v7',
          cpuLoad: '${data['cpu-load'] ?? 0}%',
          uptime: data['uptime'] ?? '0m',
          totalMemory: '${((data['total-memory'] ?? 0) / (1024 * 1024)).toStringAsFixed(0)} MB',
          isReachable: true,
        );
      }
    } catch (e) {
      // Unreachable or not connected to router Wi-Fi subnet
      return null;
    }
    return null;
  }

  // Reboot router via RouterOS REST API over local subnet
  static Future<bool> rebootRouter({
    String ip = "192.168.88.1",
    String username = "admin",
    String password = "",
  }) async {
    try {
      final client = http.Client();
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
