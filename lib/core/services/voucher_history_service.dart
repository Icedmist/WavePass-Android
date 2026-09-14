import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mikrotik_api_client.dart';
import 'notification_service.dart';
import 'router_discovery_service.dart';

class VoucherRecord {
  final String code;
  final String planTitle;
  final String price;
  final int durationSeconds;
  final DateTime createdAt;
  String status; // 'unused', 'in_use', 'expired'
  String? directMode;
  DateTime? usedAt;
  String? mac;
  String? ip;

  VoucherRecord({
    required this.code,
    required this.planTitle,
    required this.price,
    required this.durationSeconds,
    required this.createdAt,
    this.status = 'unused',
    this.directMode,
    this.usedAt,
    this.mac,
    this.ip,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'planTitle': planTitle,
        'price': price,
        'durationSeconds': durationSeconds,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'directMode': directMode,
        'usedAt': usedAt?.toIso8601String(),
        'mac': mac,
        'ip': ip,
      };

  factory VoucherRecord.fromJson(Map<String, dynamic> json) => VoucherRecord(
        code: json['code']?.toString() ?? '',
        planTitle: json['planTitle']?.toString() ?? 'Pass',
        price: json['price']?.toString() ?? '₦0',
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 3600,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        status: json['status']?.toString() ?? 'unused',
        directMode: json['directMode']?.toString(),
        usedAt: json['usedAt'] != null ? DateTime.tryParse(json['usedAt'].toString()) : null,
        mac: json['mac']?.toString(),
        ip: json['ip']?.toString(),
      );
}

/// Service to store voucher sales history, monitor real-time lifecycle on router,
/// trigger in-app/device notifications, and periodically clean up expired vouchers.
class VoucherHistoryService {
  VoucherHistoryService._();
  static final VoucherHistoryService instance = VoucherHistoryService._();

  static const String _keyHistory = 'wavepass_voucher_history_v1';
  Timer? _monitorTimer;
  bool _isChecking = false;

  /// Starts periodic monitoring of voucher lifecycle on hardware (every 20 seconds)
  void startMonitoring([BuildContext? context]) {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      checkVoucherLifecycle(context);
    });
    // Immediate first check
    checkVoucherLifecycle(context);
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  /// Records a newly generated / sold voucher into history
  Future<void> recordVoucher({
    required String code,
    required String planTitle,
    required String price,
    required int durationSeconds,
    String? directMode,
  }) async {
    try {
      final history = await getHistory();
      // Avoid duplicate entries
      history.removeWhere((v) => v.code.toUpperCase() == code.toUpperCase());

      final record = VoucherRecord(
        code: code,
        planTitle: planTitle,
        price: price,
        durationSeconds: durationSeconds,
        createdAt: DateTime.now(),
        status: 'unused',
        directMode: directMode,
      );

      history.insert(0, record);

      // Keep recent 500 vouchers
      if (history.length > 500) {
        history.removeRange(500, history.length);
      }

      await _saveHistory(history);
    } catch (e) {
      debugPrint('Error recording voucher history: $e');
    }
  }

  /// Retrieves all recorded vouchers
  Future<List<VoucherRecord>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyHistory);
      if (raw == null || raw.isEmpty) return [];
      final List decoded = jsonDecode(raw);
      return decoded.map((item) => VoucherRecord.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (e) {
      debugPrint('Error loading voucher history: $e');
      return [];
    }
  }

  Future<void> _saveHistory(List<VoucherRecord> history) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = history.map((v) => v.toJson()).toList();
    await prefs.setString(_keyHistory, jsonEncode(jsonList));
  }

  /// Parses RouterOS uptime string (e.g. "01:15:30", "1d02:30:00", "1h30m", "45s") into seconds
  static int parseRouterOsUptimeSeconds(String raw) {
  if (raw.isEmpty) return 0;
  raw = raw.trim();
  if (raw.contains(':')) {
    var days = 0;
    if (raw.contains('d')) {
      final parts = raw.split('d');
      days = int.tryParse(parts[0]) ?? 0;
      raw = parts.length > 1 ? parts[1].trim() : '';
    }
    final colons = raw.split(':');
    if (colons.length == 3) {
      final h = int.tryParse(colons[0]) ?? 0;
      final m = int.tryParse(colons[1]) ?? 0;
      final s = int.tryParse(colons[2]) ?? 0;
      return days * 86400 + h * 3600 + m * 60 + s;
    } else if (colons.length == 2) {
      final m = int.tryParse(colons[0]) ?? 0;
      final s = int.tryParse(colons[1]) ?? 0;
      return days * 86400 + m * 60 + s;
    }
  }

  int total = 0;
  final dMatch = RegExp(r'(\d+)d').firstMatch(raw);
  if (dMatch != null) total += (int.tryParse(dMatch.group(1)!) ?? 0) * 86400;
  final hMatch = RegExp(r'(\d+)h').firstMatch(raw);
  if (hMatch != null) total += (int.tryParse(hMatch.group(1)!) ?? 0) * 3600;
  final mMatch = RegExp(r'(\d+)m').firstMatch(raw);
  if (mMatch != null) total += (int.tryParse(mMatch.group(1)!) ?? 0) * 60;
  final sMatch = RegExp(r'(\d+)s').firstMatch(raw);
  if (sMatch != null) total += int.tryParse(sMatch.group(1)!) ?? 0;
  return total > 0 ? total : (int.tryParse(raw) ?? 0);
}

  /// Checks the router hardware for active vouchers, marks them in use,
  /// detects expirations, sends notifications, and removes expired accounts.
  Future<void> checkVoucherLifecycle([BuildContext? context]) async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final history = await getHistory();
      if (history.isEmpty) return;

      // 1. Fetch active users & configured accounts on MikroTik
      final prefs = await SharedPreferences.getInstance();
      final localIp = prefs.getString(RouterDiscoveryService.keyRouterLocalIp) ?? '192.168.88.1';
      final user = prefs.getString(RouterDiscoveryService.keyRouterUsername) ?? 'admin';
      final pass = prefs.getString(RouterDiscoveryService.keyRouterPassword) ?? '';

      final client = MikrotikApiClient(host: localIp);
      List<Map<String, String>> activeUsers = [];
      List<Map<String, String>> hotspotUsers = [];
      bool routerConnected = false;

      try {
        if (await client.connectAndLogin(user, pass)) {
          routerConnected = true;
          activeUsers = await client.getHotspotActiveUsers();
          hotspotUsers = await client.getHotspotUsers();
        }
      } catch (_) {}

      bool stateChanged = false;
      final now = DateTime.now();

      // 2. Cross-reference active users with history (accurately backdating usedAt)
      if (routerConnected) {
        for (final active in activeUsers) {
          final activeCode = active['user']?.toString().toUpperCase();
          final mac = active['mac-address']?.toString() ?? '—';
          final ip = active['address']?.toString() ?? '—';
          final uptimeStr = active['uptime']?.toString() ?? '';
          final uptimeSec = parseRouterOsUptimeSeconds(uptimeStr);

          if (activeCode == null || activeCode.isEmpty) continue;

          for (final record in history) {
            if (record.code.toUpperCase() == activeCode && record.status == 'unused') {
              record.status = 'in_use';
              // Backdate usedAt based on actual router elapsed uptime
              record.usedAt = now.subtract(Duration(seconds: uptimeSec));
              record.mac = mac;
              record.ip = ip;
              stateChanged = true;

              // In-app and device notification for owner
              if (context != null && context.mounted) {
                AppNotifier.instance.show(
                  context,
                  type: NotifyType.success,
                  title: 'Voucher In Use',
                  message: 'Pass ${record.code} (${record.planTitle}) is now active on $mac ($ip).',
                );
              }
            }
          }
        }
      }

      // 3. Detect expired vouchers from elapsed duration and delete from hardware
      for (final record in history) {
        if (record.status == 'in_use' && record.usedAt != null) {
          final elapsed = now.difference(record.usedAt!).inSeconds;
          if (elapsed >= record.durationSeconds) {
            record.status = 'expired';
            stateChanged = true;

            // Notify owner of expiration
            if (context != null && context.mounted) {
              AppNotifier.instance.show(
                context,
                type: NotifyType.warning,
                title: 'Voucher Expired',
                message: 'Pass ${record.code} (${record.planTitle}) has expired and was removed.',
              );
            }

            // Remove expired user from router hardware
            if (routerConnected) {
              try {
                await client.disconnectActiveUser(record.code);
                await client.removeHotspotUser(record.code);
              } catch (_) {}
            }
          }
        }
      }

      // 4. Proactively check router user accounts that reached limit-uptime
      if (routerConnected && hotspotUsers.isNotEmpty) {
        for (final u in hotspotUsers) {
          final uName = u['name']?.toString();
          if (uName == null || uName.isEmpty || uName.toLowerCase() == 'admin') continue;

          final limitUptime = u['limit-uptime']?.toString() ?? '';
          final currentUptime = u['uptime']?.toString() ?? '';

          if (limitUptime.isNotEmpty && limitUptime != '0s') {
            final limitSec = parseRouterOsUptimeSeconds(limitUptime);
            final currentSec = parseRouterOsUptimeSeconds(currentUptime);

            if (limitSec > 0 && currentSec >= limitSec) {
              try {
                await client.disconnectActiveUser(uName);
                await client.removeHotspotUser(uName);
              } catch (_) {}

              for (final record in history) {
                if (record.code.toUpperCase() == uName.toUpperCase() && record.status != 'expired') {
                  record.status = 'expired';
                  stateChanged = true;
                }
              }
            }
          }
        }
      }

      // 5. Purge any remaining expired vouchers in history from router
      if (routerConnected) {
        for (final record in history) {
          if (record.status == 'expired') {
            try {
              await client.removeHotspotUser(record.code);
            } catch (_) {}
          }
        }
      }

      try {
        await client.close();
      } catch (_) {}

      if (stateChanged) {
        await _saveHistory(history);
      }
    } catch (e) {
      debugPrint('Error checking voucher lifecycle: $e');
    } finally {
      _isChecking = false;
    }
  }

  /// Manually marks a voucher as expired and removes it from router
  Future<void> expireVoucher(String code) async {
    final history = await getHistory();
    for (final v in history) {
      if (v.code.toUpperCase() == code.toUpperCase()) {
        v.status = 'expired';
        break;
      }
    }
    await _saveHistory(history);

    try {
      final prefs = await SharedPreferences.getInstance();
      final localIp = prefs.getString(RouterDiscoveryService.keyRouterLocalIp) ?? '192.168.88.1';
      final user = prefs.getString(RouterDiscoveryService.keyRouterUsername) ?? 'admin';
      final pass = prefs.getString(RouterDiscoveryService.keyRouterPassword) ?? '';
      final client = MikrotikApiClient(host: localIp);
      if (await client.connectAndLogin(user, pass)) {
        await client.disconnectActiveUser(code);
        await client.removeHotspotUser(code);
        await client.close();
      }
    } catch (_) {}
  }
}
