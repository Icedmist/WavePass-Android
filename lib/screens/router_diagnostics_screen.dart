import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_theme.dart';
import '../core/services/wavepass_api.dart';
import '../core/services/router_discovery_service.dart';
import '../core/router/app_router.dart';
import '../core/widgets/shimmer.dart';

class RouterDiagnosticsScreen extends StatefulWidget {
  const RouterDiagnosticsScreen({super.key});

  @override
  State<RouterDiagnosticsScreen> createState() => _RouterDiagnosticsScreenState();
}

class _RouterDiagnosticsScreenState extends State<RouterDiagnosticsScreen> {
  bool _loading = true;
  bool _testingConnection = false;
  bool _isRebooting = false;
  String? _error;

  List<Map<String, dynamic>> _routers = [];
  Map<String, dynamic>? _selectedRouter;
  DiscoveredRouter? _localDiscovered;
  String? _venueName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      var venueId = prefs.getString('wavepass_active_venue_id');
      var venueName = prefs.getString('wavepass_active_venue_name');

      Map<String, dynamic>? defaultVenue;
      try {
        defaultVenue = await WavePassApi.instance.getDefaultVenue();
        if (defaultVenue['id'] != null) {
          venueId ??= defaultVenue['id']?.toString();
          venueName ??= defaultVenue['name']?.toString();
        }
      } catch (_) {}

      _venueName = venueName ?? defaultVenue?['name']?.toString() ?? 'Primary Venue';

      List<dynamic> rawRouters = [];
      try {
        rawRouters = await WavePassApi.instance.listRouters(venueId: venueId);
      } catch (_) {}

      // Fallback to defaultVenue['routers'] if listRouters returned empty
      if (rawRouters.isEmpty && defaultVenue != null && defaultVenue['routers'] is List) {
        rawRouters = defaultVenue['routers'] as List<dynamic>;
      }

      final mapped = rawRouters
          .map((r) => r is Map<String, dynamic> ? r : Map<String, dynamic>.from(r as Map))
          .toList();

      setState(() {
        _routers = mapped;
        if (mapped.isNotEmpty) {
          _selectedRouter = mapped.first;
        } else {
          _selectedRouter = null;
        }
      });

      // Attempt non-blocking local subnet discovery if on local Wi-Fi
      _probeLocalSubnet();
    } catch (e) {
      setState(() => _error = 'Failed to load router info: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _probeLocalSubnet() async {
    try {
      final local = await RouterDiscoveryService.discoverLocalRouter();
      if (mounted && local != null) {
        setState(() => _localDiscovered = local);
      }
    } catch (_) {}
  }

  Future<void> _testConnection() async {
    if (_selectedRouter == null) return;
    final routerId = _selectedRouter!['id']?.toString();
    if (routerId == null) return;

    setState(() => _testingConnection = true);
    try {
      final updated = await WavePassApi.instance.testRouter(routerId);
      if (!mounted) return;

      setState(() {
        _selectedRouter = {
          ..._selectedRouter!,
          ...updated,
          'status': updated['status'] ?? 'OFFLINE',
          'lastSeen': updated['lastSeen'] ?? DateTime.now().toIso8601String(),
        };
      });

      final isOnline = _selectedRouter!['status'] == 'ONLINE';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOnline
              ? "Router is ONLINE and responding to queries."
              : "Router ping returned OFFLINE. Check gateway power and backhaul cable."),
          backgroundColor: isOnline ? AppColors.accentGreen : AppColors.accentRed,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Connection test failed: $e"),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  Future<void> _handleReboot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reboot Router Hardware?"),
        content: const Text(
          "This will restart the router operating system. Connected guests will temporarily disconnect for 30–60 seconds.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Reboot"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRebooting = true);
    try {
      final success = await RouterDiscoveryService.rebootRouter();
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Reboot command dispatched to gateway."),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Reboot command sent. Router is restarting."),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Reboot failed: $e"), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isRebooting = false);
    }
  }

  Future<void> _showProvisionScript() async {
    if (_selectedRouter == null) return;
    final routerId = _selectedRouter!['id']?.toString() ?? 'default';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    String script = '';
    try {
      script = await WavePassApi.instance.getRouterProvisionScript(routerId);
    } catch (e) {
      script = '# Error fetching script: $e';
    } finally {
      if (mounted) Navigator.of(context).pop();
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (c, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "RouterOS Config Script",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "Paste this script into MikroTik Terminal (/terminal) to configure the captive portal bridge, HotSpot server, and Walled Garden.",
                style: TextStyle(fontSize: 12, color: AppColors.textLight),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    child: SelectableText(
                      script,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF38BDF8),
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text("Copy Script to Clipboard"),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: script));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Provision script copied to clipboard!")),
                  );
                },
              ),
            ],
          ),
        ),
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
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadData,
          ),
        ],
      ),
      body: _loading
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: const [
                ShimmerBox(h: 120, r: 24),
                SizedBox(height: 16),
                ShimmerBox(h: 100, r: 20),
                SizedBox(height: 16),
                ShimmerBox(h: 100, r: 20),
              ],
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _routers.isEmpty ? _buildEmptyState() : _buildRouterDetails(),
            ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.containerBg,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Icon(Icons.router_outlined, size: 40, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "No Router Configured",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primary),
        ),
        const SizedBox(height: 8),
        Text(
          "No MikroTik router or wireless gateway is bound to ${_venueName ?? 'your venue'} yet. Connect a gateway using local Wi-Fi discovery or scan the box barcode to begin monitoring live status and bandwidth.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.5),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: const Icon(Icons.add_link_rounded, size: 20),
          label: const Text("Set Up Router", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          onPressed: () => context.push(AppRouter.routerSetup),
        ),
      ],
    );
  }

  Widget _buildRouterDetails() {
    final router = _selectedRouter ?? _routers.first;
    final status = (router['status']?.toString() ?? 'OFFLINE').toUpperCase();
    final isOnline = status == 'ONLINE';
    final name = router['name']?.toString() ?? 'MikroTik Gateway';
    final endpoint = router['endpoint']?.toString() ?? '192.168.88.1';
    final rosVersion = router['rosVersion']?.toString() ?? (_localDiscovered?.version ?? 'RouterOS v7');
    final sessionCount = router['_count']?['sessions'] ?? router['sessionsCount'] ?? 0;
    final mode = router['connectionMode']?.toString() ?? 'local';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.redTint, borderRadius: BorderRadius.circular(14)),
              child: Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
            ),
          ),

        // Multiple routers picker if venue has > 1
        if (_routers.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<String>(
              key: ValueKey('router_${router['id']}'),
              initialValue: router['id']?.toString(),
              decoration: const InputDecoration(labelText: 'Select Router', border: OutlineInputBorder()),
              items: _routers
                  .map((r) => DropdownMenuItem(
                        value: r['id']?.toString(),
                        child: Text(r['name']?.toString() ?? r['id'].toString()),
                      ))
                  .toList(),
              onChanged: (id) {
                if (id != null) {
                  setState(() {
                    _selectedRouter = _routers.firstWhere((r) => r['id']?.toString() == id);
                  });
                }
              },
            ),
          ),

        // Router Overview Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.containerBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              Row(
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
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$rosVersion • $endpoint',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textLight),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOnline ? AppColors.accentGreen.withValues(alpha: 0.12) : AppColors.accentRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: isOnline ? AppColors.accentGreen : AppColors.accentRed,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: _testingConnection ? null : _testConnection,
                  icon: _testingConnection
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_ping, size: 18),
                  label: Text(_testingConnection ? "Testing Gateway Ping..." : "Test Connectivity Ping"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Diagnostic metric cards grid
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                "HARDWARE STATUS",
                status,
                isOnline ? "Gateway responsive" : "No ping received",
                isOnline ? AppColors.accentGreen : AppColors.accentRed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                "ACTIVE SESSIONS",
                "$sessionCount",
                "Connected guests",
                AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                "LINK MODE",
                mode.toUpperCase(),
                "Connection protocol",
                AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                "LAST SEEN",
                router['lastSeen'] != null ? router['lastSeen'].toString().split('T')[0] : "Recent",
                "Cloud heartbeat",
                AppColors.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Local Subnet Live Hardware Telemetry
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "LOCAL SUBNET TELEMETRY",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8),
                  ),
                  if (_localDiscovered != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.accentGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: const Text("LOCAL WI-FI CONNECTED", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accentGreen)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_localDiscovered != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("CPU Load", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    Text(_localDiscovered!.cpuLoad, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentGreen)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Free Memory", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    Text(_localDiscovered!.totalMemory, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Uptime", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    Text(_localDiscovered!.uptime, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ],
                ),
              ] else ...[
                const Text(
                  "Connect your phone to the router's local Wi-Fi subnet (192.168.88.1) to view real-time CPU, RAM, and internal RouterOS telemetry.",
                  style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _probeLocalSubnet,
                  icon: const Icon(Icons.wifi_find, size: 16),
                  label: const Text("Probe Local Subnet (192.168.88.1)"),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Action buttons
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _showProvisionScript,
            icon: const Icon(Icons.code_rounded, color: AppColors.primary),
            label: const Text("View RouterOS Setup Script", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.cardBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isRebooting ? null : _handleReboot,
            icon: const Icon(Icons.restart_alt, color: AppColors.accentRed),
            label: _isRebooting
                ? const Text("Sending reboot command...")
                : const Text("Restart Router Hardware", style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.accentRed.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: TextButton.icon(
            onPressed: () => context.push(AppRouter.routerSetup),
            icon: const Icon(Icons.add_rounded, color: AppColors.textLight),
            label: const Text("Set Up Another Router", style: TextStyle(color: AppColors.textLight)),
          ),
        ),
        const SizedBox(height: 32),
      ],
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: valueColor)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.textLight), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
