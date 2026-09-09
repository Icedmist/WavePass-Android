import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
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
      final venue = await SupabaseService.instance.getPrimaryVenue();
      if (venue != null) {
        final sessions = await SupabaseService.instance.getActiveSessions(venue['id']);
        if (!mounted) return;
        setState(() {
          _devices = sessions.map((s) {
            final expiresAt = s['expiresAt'] != null ? DateTime.tryParse(s['expiresAt'].toString()) : null;
            final remaining = expiresAt != null ? expiresAt.difference(DateTime.now()).inMinutes : 0;
            final prog = expiresAt != null ? (remaining / 1440).clamp(0.0, 1.0) : 0.5;
            return {
              'id': s['id'],
              'name': s['deviceId'] ?? s['mac'] ?? 'Unknown Device',
              'mac': s['mac'] ?? '—',
              'ip': s['ip'] ?? '—',
              'plan': s['plan'] ?? s['voucherId'] ?? 'Pass',
              'timeLeft': remaining > 60 ? '${remaining ~/ 60}h ${remaining % 60}m left' : '${remaining}m left',
              'progress': prog,
              'sessionId': s['id'],
            };
          }).toList();
        });
      }
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

    // 1. Disconnect on RouterOS hardware via Cloud/Local API
    try {
      await WavePassApi.instance.post('/api/v1/sessions/$sessionId/disconnect', {});
    } catch (_) {}

    // 2. Terminate session in database
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
