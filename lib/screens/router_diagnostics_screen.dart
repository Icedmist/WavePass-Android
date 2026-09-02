import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class RouterDiagnosticsScreen extends StatefulWidget {
  const RouterDiagnosticsScreen({super.key});

  @override
  State<RouterDiagnosticsScreen> createState() => _RouterDiagnosticsScreenState();
}

class _RouterDiagnosticsScreenState extends State<RouterDiagnosticsScreen> {
  bool _isRebooting = false;

  void _handleReboot() async {
    setState(() => _isRebooting = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _isRebooting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Router reboot command sent successfully."),
        backgroundColor: AppColors.accentGreen,
      ),
    );
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Router Health & Speed",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Router Overview Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Icon(Icons.router, color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "MikroTik hAP ax² Gateway",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "RouterOS v7.15.2 • 192.168.88.1",
                          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textLight),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Diagnostic metric cards grid
            Row(
              children: [
                Expanded(child: _buildMetricCard("CPU LOAD", "4%", "Normal usage", AppColors.accentGreen)),
                const SizedBox(width: 12),
                Expanded(child: _buildMetricCard("FREE MEMORY", "842 MB", "Of 1024 MB total", AppColors.primary)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildMetricCard("UPTIME", "14d 6h", "No crashes detected", AppColors.primary)),
                const SizedBox(width: 12),
                Expanded(child: _buildMetricCard("WAN IP", "102.89.44.12", "Public backhaul", AppColors.navy)),
              ],
            ),
            const SizedBox(height: 24),

            // Bandwidth Usage Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "LIVE WI-FI TRAFFIC",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text("Download Rate", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      Text("24.6 Mbps", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentGreen)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text("Upload Rate", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      Text("6.2 Mbps", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Reboot button
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _isRebooting ? null : _handleReboot,
                icon: const Icon(Icons.restart_alt, color: AppColors.accentRed),
                label: _isRebooting
                    ? const Text("Sending reboot command...")
                    : const Text("Restart Router Hardware", style: TextStyle(color: AppColors.accentRed)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.accentRed.withOpacity(0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, String subtitle, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: valueColor)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
        ],
      ),
    );
  }
}
