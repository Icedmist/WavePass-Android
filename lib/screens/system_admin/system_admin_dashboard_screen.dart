import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/services/system_admin_service.dart';
import '../../core/theme/app_theme.dart';

class SystemAdminDashboardScreen extends StatefulWidget {
  const SystemAdminDashboardScreen({super.key});

  @override
  State<SystemAdminDashboardScreen> createState() => _SystemAdminDashboardScreenState();
}

class _SystemAdminDashboardScreenState extends State<SystemAdminDashboardScreen> {
  bool _loading = true;
  Map<String, dynamic>? _fleet;
  Map<String, dynamic>? _health;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
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
    final summary = _fleet?['summary'] as Map<String, dynamic>? ?? {};
    final totalVenues = summary['totalVenues'] ?? 0;
    final totalRouters = summary['totalRouters'] ?? 0;
    final onlineRouters = summary['onlineRouters'] ?? 0;
    final totalSessions = summary['totalActiveSessions'] ?? 0;
    final totalVouchers = summary['totalVouchers'] ?? 0;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.dashboard),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentGreen,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                "ROOT",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              "System Administrator Hub",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadAdminData,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: "Refresh Metrics",
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
                  // System Status Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.85)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.accentGreen.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.security_rounded, color: AppColors.accentGreen, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "SYSTEM ADMIN ACTIVE",
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accentGreen, letterSpacing: 0.5),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                "talk2icedmist@gmail.com",
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Backend Engine: ${_health?['status'] ?? 'ONLINE'} • DB: ${_health?['database']?['status'] ?? 'ok'}",
                                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4 Summary Metric Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile("TOTAL VENUES", "$totalVenues", Icons.storefront_rounded, AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricTile("ONLINE ROUTERS", "$onlineRouters / $totalRouters", Icons.router_rounded, AppColors.accentGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile("ACTIVE SESSIONS", "$totalSessions", Icons.wifi_tethering_rounded, AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricTile("TOTAL PASSES", "$totalVouchers", Icons.confirmation_number_outlined, AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    "CONTROL & OVERSIGHT SUITE",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 12),

                  // 4 Primary Navigation Cards
                  _buildNavCard(
                    title: "Full System Monitor",
                    subtitle: "Fleet overview, server metrics, database latency & memory telemetry",
                    icon: Icons.monitor_heart_rounded,
                    color: AppColors.primary,
                    badge: "REALTIME",
                    onTap: () => context.push('/system-admin/monitor'),
                  ),
                  const SizedBox(height: 12),
                  _buildNavCard(
                    title: "Platform Control & Commands",
                    subtitle: "Maintenance mode, announcements, fleet anti-tethering & remote reboots",
                    icon: Icons.tune_rounded,
                    color: AppColors.accentOrange,
                    badge: "CONTROLS",
                    onTap: () => context.push('/system-admin/control'),
                  ),
                  const SizedBox(height: 12),
                  _buildNavCard(
                    title: "System Audits & Logs",
                    subtitle: "Comprehensive audit trail for logins, activations, routers and security",
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.primary,
                    badge: "AUDITS",
                    onTap: () => context.push('/system-admin/audits'),
                  ),
                  const SizedBox(height: 12),
                  _buildNavCard(
                    title: "Activation Codes Engine",
                    subtitle: "Generate, authorize, revoke, and inspect venue activation codes (1 per venue)",
                    icon: Icons.vpn_key_rounded,
                    color: AppColors.accentGreen,
                    badge: "LICENSING",
                    onTap: () => context.push('/system-admin/activation-codes'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.containerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.5)),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildNavCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.containerBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight, height: 1.3),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }
}
