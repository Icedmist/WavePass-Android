import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/router/app_router.dart';
import '../core/services/router_discovery_service.dart';
import '../core/services/supabase_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/theme/app_theme.dart';

class ActiveDevicesScreen extends StatefulWidget {
  const ActiveDevicesScreen({super.key});
  @override
  State<ActiveDevicesScreen> createState() => _ActiveDevicesScreenState();
}

class _ActiveDevicesScreenState extends State<ActiveDevicesScreen> {
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  bool _isRefreshing = false;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadDevices(silent: true);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDevices({bool silent = false}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final localIp = prefs.getString(RouterDiscoveryService.keyRouterLocalIp) ?? '192.168.88.1';
      final user = prefs.getString(RouterDiscoveryService.keyRouterUsername) ?? 'admin';
      final pass = prefs.getString(RouterDiscoveryService.keyRouterPassword) ?? '';
      String? tunnel = prefs.getString(RouterDiscoveryService.keyRouterTunnelEndpoint);

      final venue = await SupabaseService.instance.getPrimaryVenue();
      final venueId = venue?['id']?.toString();

      // If tunnel endpoint is empty, look up router endpoint from DB
      if ((tunnel == null || tunnel.isEmpty) && venueId != null) {
        try {
          final rList = await SupabaseService.instance.client
              .from('Router')
              .select('endpoint')
              .eq('venueId', venueId)
              .limit(1);
          if (rList.isNotEmpty) {
            final ep = rList.first['endpoint']?.toString();
            if (ep != null && ep.isNotEmpty) tunnel = ep;
          }
        } catch (_) {}
      }

      // 1. Fetch Supabase active sessions
      List<dynamic> dbSessions = [];
      if (venueId != null) {
        try {
          dbSessions = await SupabaseService.instance.getActiveSessions(venueId);
        } catch (_) {}
      }

      // 2. Fetch live RouterOS active sessions from hardware
      List<Map<String, dynamic>> hwUsers = [];
      try {
        hwUsers = await RouterDiscoveryService.fetchActiveHotspotUsers(
          ip: localIp,
          username: user,
          password: pass,
          endpoint: tunnel,
        );
      } catch (_) {}

      // 3. Merge both sources
      final merged = <Map<String, dynamic>>[];
      final matchedHwIds = <String>{};

      for (final s in dbSessions) {
        final expiresAt = s['expiresAt'] != null ? DateTime.tryParse(s['expiresAt'].toString()) : null;
        final remaining = expiresAt != null ? expiresAt.difference(DateTime.now()).inMinutes : 0;
        final prog = expiresAt != null ? (remaining / 1440).clamp(0.0, 1.0) : 0.5;
        final sMac = (s['mac']?.toString() ?? '').toLowerCase().trim();
        final sIp = s['ip']?.toString().trim() ?? '';
        final sUser = (s['voucherId']?.toString() ?? s['deviceId']?.toString() ?? '').trim();

        // Check if matching hardware user
        Map<String, dynamic>? matchHw;
        for (final hw in hwUsers) {
          final hwMac = (hw['mac-address']?.toString() ?? hw['mac']?.toString() ?? '').toLowerCase().trim();
          final hwIp = (hw['address']?.toString() ?? hw['ip']?.toString() ?? '').trim();
          final hwUser = (hw['user']?.toString() ?? '').trim();

          if ((sMac.isNotEmpty && sMac == hwMac) ||
              (sIp.isNotEmpty && sIp == hwIp) ||
              (sUser.isNotEmpty && sUser == hwUser)) {
            matchHw = hw;
            if (hw['.id'] != null) matchedHwIds.add(hw['.id'].toString());
            if (hw['user'] != null) matchedHwIds.add(hw['user'].toString());
            break;
          }
        }

        final timeLeft = matchHw?['session-time-left'] != null && matchHw!['session-time-left'].toString().isNotEmpty
            ? matchHw['session-time-left'].toString()
            : (remaining > 60 ? '${remaining ~/ 60}h ${remaining % 60}m left' : '${remaining}m left');

        merged.add({
          'id': s['id'],
          'name': s['deviceId'] ?? s['mac'] ?? matchHw?['user'] ?? 'Unknown Device',
          'mac': s['mac'] ?? matchHw?['mac-address'] ?? '—',
          'ip': s['ip'] ?? matchHw?['address'] ?? '—',
          'plan': s['plan'] ?? s['voucherId'] ?? (matchHw?['user'] != null ? 'Voucher (${matchHw!['user']})' : 'Pass'),
          'timeLeft': timeLeft,
          'progress': prog,
          'sessionId': s['id'],
          'hardwareId': matchHw?['.id'],
          'hardwareUser': matchHw?['user'],
          'uptime': matchHw?['uptime'],
          'fromRouter': matchHw != null,
        });
      }

      // Add any router hardware users not already matched
      for (final hw in hwUsers) {
        final id = hw['.id']?.toString() ?? '';
        final u = hw['user']?.toString() ?? '';
        if (matchedHwIds.contains(id) || (u.isNotEmpty && matchedHwIds.contains(u))) {
          continue;
        }

        final userCode = hw['user']?.toString() ?? 'Guest';
        final timeLeft = hw['session-time-left']?.toString();
        final uptime = hw['uptime']?.toString();
        final displayTime = (timeLeft != null && timeLeft.isNotEmpty)
            ? '$timeLeft left'
            : (uptime != null ? 'Online: $uptime' : 'Active');

        merged.add({
          'id': hw['.id'] ?? hw['user'] ?? hw['mac-address'] ?? hw['address'],
          'name': hw['user'] != null && hw['user'].toString().isNotEmpty ? 'Voucher ${hw['user']}' : (hw['mac-address'] ?? 'Connected Device'),
          'mac': hw['mac-address'] ?? '—',
          'ip': hw['address'] ?? '—',
          'plan': 'Active Pass ($userCode)',
          'timeLeft': displayTime,
          'progress': 0.8,
          'sessionId': hw['.id'] ?? hw['user'],
          'hardwareId': hw['.id'],
          'hardwareUser': hw['user'],
          'uptime': uptime,
          'fromRouter': true,
        });
      }

      if (!mounted) return;
      setState(() {
        _devices = merged;
      });
    } finally {
      _isRefreshing = false;
      if (!silent && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _disconnectDevice(int index) async {
    final dev = _devices[index];
    final sessionId = dev['sessionId'] ?? dev['id'];
    final hardwareIdOrUser = dev['hardwareId']?.toString() ?? dev['hardwareUser']?.toString() ?? dev['name'];

    final prefs = await SharedPreferences.getInstance();
    final localIp = prefs.getString(RouterDiscoveryService.keyRouterLocalIp) ?? '192.168.88.1';
    final user = prefs.getString(RouterDiscoveryService.keyRouterUsername) ?? 'admin';
    final pass = prefs.getString(RouterDiscoveryService.keyRouterPassword) ?? '';
    final tunnel = prefs.getString(RouterDiscoveryService.keyRouterTunnelEndpoint);

    // 1. Disconnect on RouterOS hardware directly
    if (hardwareIdOrUser != null && hardwareIdOrUser.toString().isNotEmpty) {
      try {
        await RouterDiscoveryService.disconnectHotspotUser(
          ip: localIp,
          username: user,
          password: pass,
          endpoint: tunnel,
          activeIdOrUser: hardwareIdOrUser.toString(),
        );
      } catch (_) {}
    }

    // 2. Disconnect on Cloud / Local API
    try {
      await WavePassApi.instance.post('/api/v1/sessions/$sessionId/disconnect', {});
    } catch (_) {}

    // 3. Terminate session in database if it exists
    try {
      await SupabaseService.instance.client.from('Session').update({
        'status': 'ENDED',
        'endedAt': DateTime.now().toIso8601String(),
      }).eq('id', sessionId);
    } catch (_) {}

    if (mounted) {
      setState(() => _devices.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${dev['name']} disconnected from router"),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.primary, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.dashboard),
        ),
        title: const Text(
          "Active Devices",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                "${_devices.length} Online",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentGreen,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _devices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.cardBorder)), child: const Icon(Icons.devices_other_rounded, size: 28, color: AppColors.textLight)),
                      const SizedBox(height: 12),
                      const Text('No active devices', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      const Text('Live sessions will appear here when guests connect.', style: TextStyle(fontSize: 11, color: AppColors.textLight), textAlign: TextAlign.center),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDevices,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    itemCount: _devices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final dev = _devices[index];

          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.containerBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.smartphone, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          dev['name'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => _disconnectDevice(index),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Text(
                          "Disconnect",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentRed,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Text(
                      dev['mac'],
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppColors.textLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      dev['ip'],
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Time remaining progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: dev['progress'],
                    minHeight: 6,
                    backgroundColor: Colors.black.withValues(alpha: 0.06),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                  ),
                ),
                const SizedBox(height: 6),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dev['plan'],
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                    ),
                    Text(
                      dev['timeLeft'],
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ),
    );
  }
}
