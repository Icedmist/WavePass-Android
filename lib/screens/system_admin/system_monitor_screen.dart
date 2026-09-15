import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/services/system_admin_service.dart';
import '../../core/theme/app_theme.dart';

class SystemMonitorScreen extends StatefulWidget {
  const SystemMonitorScreen({super.key});

  @override
  State<SystemMonitorScreen> createState() => _SystemMonitorScreenState();
}

class _SystemMonitorScreenState extends State<SystemMonitorScreen> {
  bool _loading = true;
  Map<String, dynamic>? _fleet;
  Map<String, dynamic>? _health;

  @override
  void initState() {
    super.initState();
    _loadTelemetry();
  }

  Future<void> _loadTelemetry() async {
    setState(() => _loading = true);
    final fleet = await SystemAdminService.instance.fetchFleetOverview();
    final health = await SystemAdminService.instance.fetchSystemHealth();
    if (mounted) {
      setState(() {
        _fleet = fleet;
        _health = health;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final venues = (_fleet?['venues'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final memory = _health?['memory'] as Map<String, dynamic>? ?? {};
    final db = _health?['database'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          "System Monitor & Fleet",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
        ),
        actions: [
          IconButton(
            onPressed: _loadTelemetry,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "SERVER & TELEMETRY HEALTH",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 12),

                  // Telemetry Grid
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      children: [
                        _buildRow("Cloud API Server", _health?['status'] ?? 'ONLINE', AppColors.accentGreen),
                        const Divider(height: 20, color: AppColors.cardBorder),
                        _buildRow("Database Status", "${db['status'] ?? 'ok'} (${db['latencyMs'] ?? 0}ms latency)", AppColors.primary),
                        const Divider(height: 20, color: AppColors.cardBorder),
                        _buildRow("RAM Memory Usage", "${memory['rssMB'] ?? 0} MB (Heap: ${memory['heapUsedMB'] ?? 0}/${memory['heapTotalMB'] ?? 0} MB)", AppColors.primary),
                        const Divider(height: 20, color: AppColors.cardBorder),
                        _buildRow("Server Node Runtime", "${_health?['nodeVersion'] ?? 'v20'} • Uptime: ${(_health?['uptimeSeconds'] ?? 0) ~/ 3600}h", AppColors.textLight),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "GLOBAL ROUTER FLEET",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.8),
                      ),
                      Text(
                        "${venues.length} registered venues",
                        style: const TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (venues.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: const Text("No venues or routers discovered yet."),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: venues.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final v = venues[index];
                        final routers = (v['routers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                        final primaryRouter = routers.isNotEmpty ? routers.first : null;
                        final isOnline = primaryRouter?['status'] == 'ONLINE';

                        return Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.containerBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      v['name']?.toString() ?? 'Venue',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isOnline
                                          ? AppColors.accentGreen.withValues(alpha: 0.15)
                                          : AppColors.accentRed.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: isOnline ? AppColors.accentGreen : AppColors.accentRed,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          isOnline ? "ONLINE" : "OFFLINE",
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: isOnline ? AppColors.accentGreen : AppColors.accentRed,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Slug: ${v['slug']}.nexawavepass.com",
                                style: const TextStyle(fontSize: 12, color: AppColors.textLight),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          primaryRouter?['name']?.toString() ?? 'No Router Configured',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                                        ),
                                        Text(
                                          "Endpoint: ${primaryRouter?['endpoint'] ?? 'N/A'}",
                                          style: const TextStyle(fontSize: 10, color: AppColors.textLight),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      "${v['activeSessions'] ?? 0} active devices • ${v['vouchersCount'] ?? 0} vouchers",
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        await SystemAdminService.instance.switchActiveVenue(v);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text("Switched app context to venue: ${v['name']}"),
                                              backgroundColor: AppColors.primary,
                                            ),
                                          );
                                          context.go(AppRouter.dashboard);
                                        }
                                      },
                                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                                      label: const Text("Manage & View in App", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.primary,
                                        side: const BorderSide(color: AppColors.primary),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textLight, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 13, color: valueColor, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
