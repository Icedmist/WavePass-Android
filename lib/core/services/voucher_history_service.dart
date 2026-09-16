import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mikrotik_api_client.dart';
import 'notification_service.dart';
import 'router_discovery_service.dart';
import 'supabase_service.dart';
import 'system_admin_service.dart';
import 'venue_state_service.dart';

class VoucherRecord {
  final String code;
  String? password;
  final String planTitle;
  final String price;
  final int durationSeconds;
  final DateTime createdAt;
  String status; // 'unused', 'in_use', 'expired'
  String? directMode;
  DateTime? usedAt;
  String? mac;
  String? ip;
  String? uptime;
  int? bytesIn;
  int? bytesOut;
  String? source; // 'local', 'router', 'supabase'

  VoucherRecord({
    required this.code,
    this.password,
    required this.planTitle,
    required this.price,
    required this.durationSeconds,
    required this.createdAt,
    this.status = 'unused',
    this.directMode,
    this.usedAt,
    this.mac,
    this.ip,
    this.uptime,
    this.bytesIn,
    this.bytesOut,
    this.source,
  });

  String get effectivePassword => (password != null && password!.isNotEmpty) ? password! : code;
  bool get isDualCredential => password != null && password!.isNotEmpty && password != code;

  String get dataTransferredFormatted {
    final totalBytes = (bytesIn ?? 0) + (bytesOut ?? 0);
    if (totalBytes <= 0) return '0 KB';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get uptimeFormatted {
    if (uptime != null && uptime!.isNotEmpty && uptime != '0s') return uptime!;
    if (usedAt == null) return '0s';
    final elapsed = DateTime.now().difference(usedAt!).inSeconds;
    if (elapsed <= 0) return '0s';
    if (elapsed < 60) return '${elapsed}s';
    if (elapsed < 3600) return '${elapsed ~/ 60}m ${elapsed % 60}s';
    return '${elapsed ~/ 3600}h ${(elapsed % 3600) ~/ 60}m';
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'password': password,
        'planTitle': planTitle,
        'price': price,
        'durationSeconds': durationSeconds,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'directMode': directMode,
        'usedAt': usedAt?.toIso8601String(),
        'mac': mac,
        'ip': ip,
        'uptime': uptime,
        'bytesIn': bytesIn,
        'bytesOut': bytesOut,
        'source': source,
      };

  factory VoucherRecord.fromJson(Map<String, dynamic> json) => VoucherRecord(
        code: json['code']?.toString() ?? '',
        password: json['password']?.toString(),
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
        uptime: json['uptime']?.toString(),
        bytesIn: (json['bytesIn'] as num?)?.toInt(),
        bytesOut: (json['bytesOut'] as num?)?.toInt(),
        source: json['source']?.toString(),
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

  /// Wipes the local cached voucher history and stops monitoring timers
  Future<void> clearCache() async {
    try {
      stopMonitoring();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyHistory);
    } catch (_) {}
  }

  /// Records a newly generated / sold voucher into history
  Future<void> recordVoucher({
    required String code,
    String? password,
    required String planTitle,
    required String price,
    required int durationSeconds,
    String? directMode,
    String? source,
  }) async {
    try {
      final history = await getHistory();
      // Avoid duplicate entries
      history.removeWhere((v) => v.code.toUpperCase() == code.toUpperCase());

      final record = VoucherRecord(
        code: code,
        password: password,
        planTitle: planTitle,
        price: price,
        durationSeconds: durationSeconds,
        createdAt: DateTime.now(),
        status: 'unused',
        directMode: directMode,
        source: source ?? 'local',
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

  /// Retrieves all recorded vouchers from local cache
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

  /// Fetches comprehensive voucher activity by consolidating:
  /// 1. Local device sales & batch vouchers history
  /// 2. Live router hardware user accounts & active sessions
  /// 3. Supabase cloud vouchers and session records
  Future<List<VoucherRecord>> fetchFullVoucherActivity([BuildContext? context]) async {
    final localList = await getHistory();
    final Map<String, VoucherRecord> consolidated = {
      for (final v in localList) v.code.toUpperCase(): v,
    };

    final currentVenue = VenueStateService.instance.currentVenue;
    final venueId = currentVenue?['id']?.toString();
    final isSuperAdmin = await SystemAdminService.instance.isSystemAdmin();

    // 1. Query Router Hardware via MikrotikApiClient only if venue is configured or superadmin
    if (currentVenue != null || isSuperAdmin) {
      try {
        final prefs = await SharedPreferences.getInstance();
      final localIp = prefs.getString(RouterDiscoveryService.keyRouterLocalIp) ?? '192.168.88.1';
      final user = prefs.getString(RouterDiscoveryService.keyRouterUsername) ?? 'admin';
      final pass = prefs.getString(RouterDiscoveryService.keyRouterPassword) ?? '';
      final client = MikrotikApiClient(host: localIp);

      if (await client.connectAndLogin(user, pass)) {
        final activeUsers = await client.getHotspotActiveUsers();
        final hotspotUsers = await client.getHotspotUsers();

        final Map<String, Map<String, String>> activeMap = {};
        for (final a in activeUsers) {
          final u = a['user']?.toString().toUpperCase();
          if (u != null && u.isNotEmpty) {
            activeMap[u] = a;
          }
        }

        for (final hu in hotspotUsers) {
          final name = hu['name']?.toString();
          if (name == null || name.isEmpty || name.toLowerCase() == 'admin') continue;

          final key = name.toUpperCase();
          final password = hu['password']?.toString() ?? name;
          final uptimeStr = hu['uptime']?.toString() ?? '0s';
          final limitUptimeStr = hu['limit-uptime']?.toString() ?? '';
          final bytesIn = int.tryParse(hu['bytes-in']?.toString() ?? '0') ?? 0;
          final bytesOut = int.tryParse(hu['bytes-out']?.toString() ?? '0') ?? 0;
          final uptimeSec = parseRouterOsUptimeSeconds(uptimeStr);
          final limitSec = parseRouterOsUptimeSeconds(limitUptimeStr);

          final isActive = activeMap.containsKey(key);
          final activeData = activeMap[key];

          String status = 'unused';
          if (isActive) {
            status = 'in_use';
          } else if (limitSec > 0 && uptimeSec >= limitSec) {
            status = 'expired';
          } else if (uptimeSec > 0) {
            status = 'in_use';
          }

          final mac = activeData?['mac-address']?.toString() ?? hu['mac-address']?.toString();
          final ip = activeData?['address']?.toString() ?? hu['address']?.toString();
          final activeUptime = activeData?['uptime']?.toString() ?? uptimeStr;

          if (consolidated.containsKey(key)) {
            final existing = consolidated[key]!;
            existing.status = status;
            if (mac != null && mac.isNotEmpty && mac != '—') existing.mac = mac;
            if (ip != null && ip.isNotEmpty && ip != '—') existing.ip = ip;
            existing.uptime = activeUptime;
            existing.bytesIn = bytesIn;
            existing.bytesOut = bytesOut;
            if (existing.password == null || existing.password!.isEmpty) {
              existing.password = password;
            }
          } else {
            consolidated[key] = VoucherRecord(
              code: name,
              password: password,
              planTitle: hu['profile']?.toString() ?? 'Hotspot Pass',
              price: '₦0',
              durationSeconds: limitSec > 0 ? limitSec : 3600,
              createdAt: DateTime.now().subtract(Duration(seconds: uptimeSec)),
              status: status,
              mac: mac,
              ip: ip,
              uptime: activeUptime,
              bytesIn: bytesIn,
              bytesOut: bytesOut,
              source: 'router',
            );
          }
        }
        await client.close();
      }
    } catch (routerErr) {
      debugPrint('[VoucherHistoryService] Hardware sync note: $routerErr');
    }
    }

    // 2. Query Supabase Cloud Vouchers & Sessions
    if ((venueId != null && venueId.isNotEmpty) || isSuperAdmin) {
      try {
        final supabase = SupabaseService.instance.client;
        var query = supabase.from('Voucher').select('*, plan:Plan(*), sessions:Session(*)');
        if (venueId != null && venueId.isNotEmpty) {
          query = query.eq('venueId', venueId);
        }
        final cloudVouchers = await query.order('issuedAt', ascending: false).limit(200);

      for (final raw in cloudVouchers) {
        final vMap = Map<String, dynamic>.from(raw as Map);
        final code = vMap['displayCodeEnc']?.toString() ?? vMap['id']?.toString() ?? '';
        if (code.isEmpty) continue;

        final key = code.toUpperCase();
        final plan = vMap['plan'] as Map<String, dynamic>?;
        final planName = plan?['name']?.toString() ?? 'Pass';
        final priceMinor = (plan?['priceMinor'] as num?)?.toInt() ?? 0;
        final durationSec = (plan?['durationSeconds'] as num?)?.toInt() ?? 3600;
        final cloudStatus = vMap['status']?.toString().toUpperCase();

        String status = 'unused';
        if (cloudStatus == 'ACTIVE') {
          status = 'in_use';
        } else if (cloudStatus == 'EXPIRED' || cloudStatus == 'CONSUMED' || cloudStatus == 'REVOKED') {
          status = 'expired';
        }

        final sessions = List<Map<String, dynamic>>.from(vMap['sessions'] as List? ?? []);
        Map<String, dynamic>? latestSession;
        if (sessions.isNotEmpty) {
          latestSession = sessions.first;
        }

        if (consolidated.containsKey(key)) {
          final existing = consolidated[key]!;
          if (existing.status == 'unused' && status != 'unused') {
            existing.status = status;
          }
          if (latestSession != null) {
            existing.mac ??= latestSession['mac']?.toString();
            existing.ip ??= latestSession['ip']?.toString();
            existing.bytesIn ??= (latestSession['bytesIn'] as num?)?.toInt();
            existing.bytesOut ??= (latestSession['bytesOut'] as num?)?.toInt();
          }
        } else {
          consolidated[key] = VoucherRecord(
            code: code,
            planTitle: planName,
            price: '₦${priceMinor ~/ 100}',
            durationSeconds: durationSec,
            createdAt: DateTime.tryParse(vMap['issuedAt']?.toString() ?? '') ?? DateTime.now(),
            status: status,
            mac: latestSession?['mac']?.toString(),
            ip: latestSession?['ip']?.toString(),
            bytesIn: (latestSession?['bytesIn'] as num?)?.toInt(),
            bytesOut: (latestSession?['bytesOut'] as num?)?.toInt(),
            source: 'supabase',
          );
        }
      }
    } catch (cloudErr) {
      debugPrint('[VoucherHistoryService] Cloud vouchers fetch note: $cloudErr');
    }
    }

    final result = consolidated.values.toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Save consolidated sync state to SharedPreferences
    await _saveHistory(result);

    return result;
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

      final currentVenue = VenueStateService.instance.currentVenue;
      final isSuperAdmin = await SystemAdminService.instance.isSystemAdmin();
      if (currentVenue == null && !isSuperAdmin) return;

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

  /// Purges all expired vouchers from storage and router hardware, keeping the history clean
  Future<int> purgeExpiredVouchers() async {
    final history = await getHistory();
    final expired = history.where((v) => v.status == 'expired').toList();
    if (expired.isEmpty) return 0;

    history.removeWhere((v) => v.status == 'expired');
    await _saveHistory(history);

    // Clean up hardware
    try {
      final prefs = await SharedPreferences.getInstance();
      final localIp = prefs.getString(RouterDiscoveryService.keyRouterLocalIp) ?? '192.168.88.1';
      final user = prefs.getString(RouterDiscoveryService.keyRouterUsername) ?? 'admin';
      final pass = prefs.getString(RouterDiscoveryService.keyRouterPassword) ?? '';
      final client = MikrotikApiClient(host: localIp);
      if (await client.connectAndLogin(user, pass)) {
        for (final v in expired) {
          try {
            await client.disconnectActiveUser(v.code);
            await client.removeHotspotUser(v.code);
          } catch (_) {}
        }
        await client.close();
      }
    } catch (_) {}

    return expired.length;
  }
}
