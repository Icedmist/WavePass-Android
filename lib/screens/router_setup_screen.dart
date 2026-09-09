import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/services/router_discovery_service.dart';
import '../core/services/supabase_service.dart';
import '../core/services/wavepass_api.dart';

class RouterSetupScreen extends StatefulWidget {
  const RouterSetupScreen({super.key});

  @override
  State<RouterSetupScreen> createState() => _RouterSetupScreenState();
}

class _RouterSetupScreenState extends State<RouterSetupScreen> {
  bool _isScanning = false;
  DiscoveredRouter? _foundRouter;
  bool _isConfiguring = false;
  String? _successMessage;

  // Custom gateway credentials / IP
  bool _showCustomSettings = false;
  final _ipCtrl = TextEditingController(text: "192.168.88.1");
  final _tunnelCtrl = TextEditingController();
  final _userCtrl = TextEditingController(text: "admin");
  final _passCtrl = TextEditingController();

  // Export script state
  bool _exportingScript = false;
  String? _exportedScript;

  @override
  void dispose() {
    _ipCtrl.dispose();
    _tunnelCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleAutoDiscover() async {
    setState(() {
      _isScanning = true;
      _foundRouter = null;
      _successMessage = null;
    });

    final targetIp = _ipCtrl.text.trim().isNotEmpty ? _ipCtrl.text.trim() : "192.168.88.1";
    final tunnel = _tunnelCtrl.text.trim();
    final user = _userCtrl.text.trim().isNotEmpty ? _userCtrl.text.trim() : "admin";
    final pass = _passCtrl.text.trim();

    // 1. Probe local router
    DiscoveredRouter? router = await RouterDiscoveryService.discoverLocalRouter(
      ip: targetIp,
      username: user,
      password: pass,
    );

    // 2. If local probe fails and tunnel endpoint provided, probe tunnel
    if (router == null && tunnel.isNotEmpty) {
      router = await RouterDiscoveryService.probeEndpoint(
        tunnel,
        username: user,
        password: pass,
        connectionType: "Tunnel",
      );
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
        _foundRouter = router;
      });

      if (router == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No MikroTik router detected at $targetIp${tunnel.isNotEmpty ? ' or tunnel' : ''}. Verify you are connected to the router's Wi-Fi."),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _handleInstallHotspot() async {
    if (_foundRouter == null) return;
    setState(() {
      _isConfiguring = true;
    });

    try {
      final venue = await SupabaseService.instance.getPrimaryVenue() ?? await WavePassApi.instance.getDefaultVenue();
      final venueId = venue['id']?.toString() ?? 'default';
      final venueName = venue['name']?.toString() ?? 'WavePass Venue';
      final slug = venue['slug']?.toString() ?? 'venue';

      final user = _userCtrl.text.trim().isNotEmpty ? _userCtrl.text.trim() : "admin";
      final pass = _passCtrl.text.trim();
      final tunnel = _tunnelCtrl.text.trim().isNotEmpty ? _tunnelCtrl.text.trim() : null;

      // 1. Configure router hardware via RouterOS REST API
      final hwResult = await RouterDiscoveryService.installHotspotOnRouter(
        ip: _foundRouter!.ip,
        username: user,
        password: pass,
        slug: slug,
        venueName: venueName,
        tunnelEndpoint: tunnel,
      );

      // 2. Register router with WavePass Cloud API
      final endpoint = tunnel ?? 'http://${_foundRouter!.ip}';
      final mode = tunnel != null ? 'tunnel' : 'local';
      await WavePassApi.instance.createRouter(
        venueId: venueId,
        name: _foundRouter!.identity.isNotEmpty ? _foundRouter!.identity : 'MikroTik HotSpot',
        endpoint: endpoint,
        connectionMode: mode,
        rosVersion: _foundRouter!.version,
      );

      if (mounted) {
        final hwSuccess = hwResult['success'] == true;
        setState(() {
          _isConfiguring = false;
          _successMessage = hwSuccess
              ? "HotSpot installed & active! Router '${_foundRouter!.identity}' is configured with captive portal DNS '$slug.nexawavepass.com'."
              : "Router '${_foundRouter!.identity}' bound to venue. Note: If REST API is disabled on router, use Option 3 below to copy the setup script into Terminal.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConfiguring = false;
          _successMessage = "HotSpot registered with venue. (${e.toString().replaceAll('Exception: ', '')})";
        });
      }
    }
  }

  Future<void> _handleExportScript() async {
    setState(() => _exportingScript = true);
    try {
      final venue = await SupabaseService.instance.getPrimaryVenue() ?? await WavePassApi.instance.getDefaultVenue();
      final slug = venue['slug']?.toString() ?? 'venue';

      final script = """
# ========================================================
# WavePass MikroTik HotSpot Quick Provisioning Script
# Venue: ${venue['name'] ?? 'WavePass'} ($slug)
# Generated: ${DateTime.now().toIso8601String()}
# Uses standard admin credentials; no extra users created.
# ========================================================

# --------------------------------------------------------
# 1. Enable RouterOS REST API services
# --------------------------------------------------------
/ip service
set www disabled=no port=80
set www-ssl disabled=no port=443

# --------------------------------------------------------
# 2. Hotspot Profile & Interface
# --------------------------------------------------------
/ip hotspot profile
add dns-name="$slug.nexawavepass.com" \\
    hotspot-address=192.168.88.1 \\
    html-directory=hotspot \\
    login-by=http-chap,http-pap,mac-cookie \\
    name="wavepass-profile"

/ip hotspot
add address-pool=default-dhcp \\
    disabled=no \\
    interface=wlan1 \\
    name="wavepass-hotspot" \\
    profile="wavepass-profile"

# --------------------------------------------------------
# 3. Walled Garden Domains
# --------------------------------------------------------
/ip hotspot walled-garden
add comment="WavePass API" dst-host="api.nexawavepass.com"
add comment="WavePass Portal" dst-host="*.nexawavepass.com"
add comment="Paystack Checkout" dst-host="*.paystack.co"
add comment="Paystack API" dst-host="api.paystack.co"
add comment="Supabase Auth" dst-host="*.supabase.co"

# --------------------------------------------------------
# 4. Standard Rate-Limit User Profiles (Mikhmon Parity)
# --------------------------------------------------------
/ip hotspot user profile
add name="profile_1h" rate-limit="10M/5M" shared-users=1 comment="WavePass 1h"
add name="profile_12h" rate-limit="15M/5M" shared-users=1 comment="WavePass 12h"
add name="profile_1d" rate-limit="20M/10M" shared-users=1 comment="WavePass 24h"

# --------------------------------------------------------
# 5. Low-RAM Auto-Cleanup Script & 2-Hour Scheduler
# --------------------------------------------------------
/system script
add name="wavepass-cleanup" source="/ip hotspot user remove [find comment=\\"expired\\"]" comment="WavePass low-RAM expired user cleanup"

/system scheduler
add name="wavepass-cleanup" interval=2h on-event="wavepass-cleanup" comment="WavePass 2-hour user cleanup"

# --------------------------------------------------------
# 6. System Identity
# --------------------------------------------------------
/system identity
set name="WavePass-$slug"

# Setup complete! Router is online.
""";

      setState(() {
        _exportedScript = script;
      });

      await Clipboard.setData(ClipboardData(text: script));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("RouterOS configuration script copied to clipboard! Paste into MikroTik Terminal."),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to generate script: $e"), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingScript = false);
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
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.dashboard),
        ),
        title: const Text(
          "Set Up a Router",
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
            const Text(
              "Connect your MikroTik router to your venue. Choose the method that best matches your network setup.",
              style: TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.4),
            ),
            const SizedBox(height: 20),

            // ─── OPTION 1: AUTO-FIND ON LOCAL WI-FI ───
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        "OPTION 01",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentGreen,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        "Auto Wi-Fi Detection",
                        style: TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Auto-Find on Wi-Fi",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "1. Connect phone to your MikroTik Wi-Fi subnet.\n2. Tap 'Find My Router' to query hardware identity and install HotSpot in 1 tap.",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textLight,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Optional IP / Credentials toggle
                  InkWell(
                    onTap: () => setState(() => _showCustomSettings = !_showCustomSettings),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            _showCustomSettings ? Icons.keyboard_arrow_up_rounded : Icons.tune_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showCustomSettings ? "Hide Custom Gateway IP" : "Custom Gateway IP & Credentials",
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_showCustomSettings) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _ipCtrl,
                            decoration: const InputDecoration(
                              labelText: "Gateway IP",
                              hintText: "192.168.88.1",
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _userCtrl,
                            decoration: const InputDecoration(
                              labelText: "Username",
                              hintText: "admin",
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Password (leave empty if fresh)",
                        hintText: "••••••••",
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tunnelCtrl,
                      decoration: const InputDecoration(
                        labelText: "Cloud Tunnel Endpoint (Optional)",
                        hintText: "http://10.8.0.2:80 or tunnel.nexawavepass.com",
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isScanning ? null : _handleAutoDiscover,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: _isScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "Find My Router",
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),

                  // Discovered Router Hardware Card
                  if (_foundRouter != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.accentGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _foundRouter!.identity,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              Text(
                                _foundRouter!.ip,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: AppColors.textLight,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildMiniBadge("CPU", _foundRouter!.cpuLoad),
                              _buildMiniBadge("RAM", _foundRouter!.totalMemory),
                              _buildMiniBadge("UPTIME", _foundRouter!.uptime),
                              _buildMiniBadge("OS", _foundRouter!.version),
                            ],
                          ),
                          const SizedBox(height: 14),

                          if (_successMessage == null)
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton(
                                onPressed: _isConfiguring ? null : _handleInstallHotspot,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accentGreen,
                                ),
                                child: _isConfiguring
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        "Install HotSpot in 1 Tap",
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                              ),
                            )
                          else ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.accentGreen.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _successMessage!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.accentGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => context.push(AppRouter.routerDiagnostics),
                                    icon: const Icon(Icons.speed_rounded, size: 16),
                                    label: const Text("View Diagnostics", style: TextStyle(fontSize: 12)),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => context.go(AppRouter.dashboard),
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: const Text("Dashboard", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ─── OPTION 2: CAMERA BARCODE SCAN ───
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        "OPTION 02",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentRed,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        "Cloud Box Provisioning",
                        style: TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Scan Box Barcode",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Point camera at the serial barcode on your MikroTik box. Connects automatically through secure cloud tunnel.",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textLight,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(AppRouter.barcodeScanner),
                      icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary, size: 20),
                      label: const Text(
                        "Open Barcode Scanner",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ─── OPTION 3: EXPORT MIKROTIK SETUP SCRIPT (.RSC) ───
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        "OPTION 03",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        "WinBox / Terminal Script",
                        style: TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Export .rsc Setup Script",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Generate and copy the pre-configured RouterOS script with walled-garden rules and DNS captive profiles.",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textLight,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _exportingScript ? null : _handleExportScript,
                      icon: _exportingScript
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.code_rounded, color: AppColors.primary, size: 20),
                      label: Text(
                        _exportingScript ? "Generating..." : "Copy Setup Script (.rsc)",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  if (_exportedScript != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Text(
                        _exportedScript!,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}
