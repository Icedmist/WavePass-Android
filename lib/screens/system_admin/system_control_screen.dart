import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/system_admin_service.dart';
import '../../core/theme/app_theme.dart';

class SystemControlScreen extends StatefulWidget {
  const SystemControlScreen({super.key});

  @override
  State<SystemControlScreen> createState() => _SystemControlScreenState();
}

class _SystemControlScreenState extends State<SystemControlScreen> {
  bool _loading = true;
  bool _maintenanceMode = false;
  final _announcementCtrl = TextEditingController();
  bool _isSavingAnnouncement = false;
  bool _isEnforcingAntiSharing = false;
  bool _isRebooting = false;

  @override
  void initState() {
    super.initState();
    _loadControlState();
  }

  @override
  void dispose() {
    _announcementCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadControlState() async {
    setState(() => _loading = true);
    final mm = await SystemAdminService.instance.isMaintenanceMode();
    final ann = await SystemAdminService.instance.getSystemAnnouncement();
    if (mounted) {
      setState(() {
        _maintenanceMode = mm;
        if (ann != null) _announcementCtrl.text = ann;
        _loading = false;
      });
    }
  }

  Future<void> _handleToggleMaintenance(bool val) async {
    setState(() => _maintenanceMode = val);
    await SystemAdminService.instance.setMaintenanceMode(val);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(val ? "Maintenance mode ENABLED platform-wide." : "Maintenance mode DISABLED. Normal operations resumed."),
        backgroundColor: val ? AppColors.accentOrange : AppColors.accentGreen,
      ),
    );
  }

  Future<void> _handleSaveAnnouncement() async {
    setState(() => _isSavingAnnouncement = true);
    await SystemAdminService.instance.setSystemAnnouncement(_announcementCtrl.text);
    if (!mounted) return;
    setState(() => _isSavingAnnouncement = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Global broadcast announcement updated!"),
        backgroundColor: AppColors.accentGreen,
      ),
    );
  }

  Future<void> _handleEnforceAntiSharing() async {
    setState(() => _isEnforcingAntiSharing = true);
    final res = await SystemAdminService.instance.triggerFleetAntiTethering();
    if (!mounted) return;
    setState(() => _isEnforcingAntiSharing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['success'] == true
            ? "Universal anti-tethering (iOS, Win, Linux, Android) enforced on hardware!"
            : "Failed to enforce anti-tethering. Check router connectivity."),
        backgroundColor: res['success'] == true ? AppColors.accentGreen : AppColors.accentRed,
      ),
    );
  }

  Future<void> _handleRebootRouter() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reboot Router Hardware?"),
        content: const Text("This will send a remote reboot command to the primary MikroTik router. Connected hotspot clients will be briefly disconnected."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Confirm Reboot", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRebooting = true);
    final ok = await SystemAdminService.instance.rebootRouterHardware();
    if (!mounted) return;
    setState(() => _isRebooting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? "Reboot command dispatched to router hardware!" : "Could not reboot router. Check IP & admin credentials."),
        backgroundColor: ok ? AppColors.accentGreen : AppColors.accentRed,
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
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          "System Control & Commands",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Maintenance Mode Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _maintenanceMode ? AppColors.accentOrange : AppColors.cardBorder,
                        width: _maintenanceMode ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.build_circle_outlined, color: AppColors.accentOrange, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  "Platform Maintenance Mode",
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
                                ),
                              ],
                            ),
                            Switch(
                              value: _maintenanceMode,
                              onChanged: _handleToggleMaintenance,
                              activeThumbColor: AppColors.accentOrange,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "When enabled, non-admin venue owners see a system maintenance banner and new pass purchases are temporarily paused.",
                          style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Global Announcement Banner
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.campaign_outlined, color: AppColors.primary, size: 22),
                            SizedBox(width: 8),
                            Text(
                              "Global Broadcast Announcement",
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Display an urgent alert or operational message across all venue dashboards.",
                          style: TextStyle(fontSize: 12, color: AppColors.textLight),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _announcementCtrl,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: "e.g. Scheduled gateway upgrade tonight at 02:00 UTC.",
                            hintStyle: const TextStyle(fontSize: 12, color: AppColors.textLight),
                            filled: true,
                            fillColor: AppColors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.cardBorder),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSavingAnnouncement ? null : _handleSaveAnnouncement,
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                            child: _isSavingAnnouncement
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text("Update Broadcast Banner", style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Remote Hardware Commands
                  const Text(
                    "REMOTE HARDWARE COMMANDS",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 12),

                  // Anti-Tethering Push
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Fleet Universal Anti-Tethering Push",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Applies Mangle change-ttl=1 and multi-OS TTL filter rules on hardware to terminate iOS, Windows, Linux, and Android hotspot sharing.",
                          style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isEnforcingAntiSharing ? null : _handleEnforceAntiSharing,
                            icon: _isEnforcingAntiSharing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.shield_outlined, size: 18),
                            label: const Text("Enforce Universal Anti-Sharing"),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Reboot Router Hardware
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Remote Router Hardware Reboot",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.accentRed),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Gracefully restarts the connected MikroTik router hardware via Port 8728 binary API command.",
                          style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isRebooting ? null : _handleRebootRouter,
                            icon: _isRebooting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.restart_alt_rounded, size: 18, color: Colors.white),
                            label: const Text("Reboot Router Hardware", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentRed,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
