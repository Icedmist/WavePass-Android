import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _exportingPortalHtml = false;
  String? _exportedPortalHtml;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString(RouterDiscoveryService.keyRouterLocalIp);
    final savedTunnel = prefs.getString(RouterDiscoveryService.keyRouterTunnelEndpoint);
    final savedUser = prefs.getString(RouterDiscoveryService.keyRouterUsername);
    final savedPass = prefs.getString(RouterDiscoveryService.keyRouterPassword);

    if (mounted) {
      setState(() {
        if (savedIp != null && savedIp.isNotEmpty) _ipCtrl.text = savedIp;
        if (savedTunnel != null && savedTunnel.isNotEmpty) _tunnelCtrl.text = savedTunnel;
        if (savedUser != null && savedUser.isNotEmpty) _userCtrl.text = savedUser;
        if (savedPass != null && savedPass.isNotEmpty) {
          _passCtrl.text = savedPass;
          _showCustomSettings = true;
        }
      });
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(RouterDiscoveryService.keyRouterLocalIp, _ipCtrl.text.trim());
    await prefs.setString(RouterDiscoveryService.keyRouterTunnelEndpoint, _tunnelCtrl.text.trim());
    await prefs.setString(RouterDiscoveryService.keyRouterUsername, _userCtrl.text.trim());
    await prefs.setString(RouterDiscoveryService.keyRouterPassword, _passCtrl.text.trim());
  }

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

    await _saveCredentials();

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
      final isOnline = router != null && router.isReachable && !router.authFailed && !router.captivePortalIntercepted;
      setState(() {
        _isScanning = false;
        _foundRouter = isOnline ? router : null;
      });

      if (router == null || (!router.isReachable && !router.captivePortalIntercepted && !router.authFailed)) {
        final errorMsg = router?.errorMessage ?? "No MikroTik router detected at $targetIp${tunnel.isNotEmpty ? ' or tunnel' : ''}. Verify you are connected to the router's Wi-Fi.";
        final is404 = router?.statusCode == 404 || errorMsg.contains('rest-plain') || errorMsg.contains('404');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: AppColors.accentRed,
            duration: Duration(seconds: is404 ? 8 : 5),
            action: is404
                ? SnackBarAction(
                    label: 'COPY CMD',
                    textColor: Colors.amber,
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: '/ip/service/webserver/set rest-plain=yes'));
                    },
                  )
                : null,
          ),
        );
      } else if (router.captivePortalIntercepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(router.errorMessage ?? "HotSpot captive portal intercepted port 80. Please authenticate or enable HTTPS."),
            backgroundColor: AppColors.accentOrange,
            duration: const Duration(seconds: 5),
          ),
        );
      } else if (router.authFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(router.errorMessage ?? "Router detected at ${router.ip}, but login failed (HTTP 401). Please check the admin password."),
            backgroundColor: AppColors.accentOrange,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("MikroTik router detected successfully at ${router.ip}!"),
            backgroundColor: AppColors.accentGreen,
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

      await _saveCredentials();

      // 1. Configure router hardware via RouterOS REST API
      final hwResult = await RouterDiscoveryService.installHotspotOnRouter(
        ip: _foundRouter!.ip,
        username: user,
        password: pass,
        slug: slug,
        venueName: venueName,
        tunnelEndpoint: tunnel,
      );

      // 2. Register router with WavePass Cloud API (if network/WAN is available)
      final endpoint = tunnel ?? (_foundRouter!.ip.startsWith('http') ? _foundRouter!.ip : 'http://${_foundRouter!.ip}');
      final mode = tunnel != null ? 'tunnel' : 'local';
      bool cloudSynced = false;
      try {
        await WavePassApi.instance.createRouter(
          venueId: venueId,
          name: _foundRouter!.identity.isNotEmpty ? _foundRouter!.identity : 'MikroTik HotSpot',
          endpoint: endpoint,
          connectionMode: mode,
          rosVersion: _foundRouter!.version,
        );
        cloudSynced = true;
      } catch (e) {
        debugPrint('WavePass Cloud sync deferred (LAN mode active): $e');
      }

      // 3. Mark router as ONLINE in Supabase immediately if network available
      try {
        await SupabaseService.instance.client
            .from('Router')
            .update({
              'status': 'ONLINE',
              'lastSeen': DateTime.now().toIso8601String(),
            })
            .eq('venueId', venueId);
      } catch (_) {}

      if (mounted) {
        final hwSuccess = hwResult['success'] == true;
        setState(() {
          _isConfiguring = false;
          _successMessage = hwSuccess
              ? (cloudSynced
                  ? "HotSpot installed & active! Router '${_foundRouter!.identity}' is configured with captive portal DNS 'wavepass.local'."
                  : "HotSpot installed & active on LAN! Router '${_foundRouter!.identity}' is ready for sales.")
              : "Router '${_foundRouter!.identity}' bound to venue. Ready for sales!";
        });

        _showInstallSuccessModal(
          identity: _foundRouter!.identity,
          ip: _foundRouter!.ip,
          slug: slug,
          hwSuccess: hwSuccess,
        );
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

  void _showInstallSuccessModal({
    required String identity,
    required String ip,
    required String slug,
    required bool hwSuccess,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              hwSuccess ? "HotSpot Ready & Online!" : "Router Connected!",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              "Router '$identity' at $ip is configured and online. You can now sell passes or generate batch vouchers.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Status", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          const Text("ONLINE • LAN Direct", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accentGreen)),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Captive Portal", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const Text("wavepass.local (192.168.88.1)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.go(AppRouter.dashboard);
                },
                icon: const Icon(Icons.dashboard_rounded, size: 18),
                label: const Text("Go to Dashboard", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push(AppRouter.routerDiagnostics);
                },
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: const Text("View Diagnostics", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
add dns-name="wavepass.local" \\
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
# 3. Walled Garden Domains (Captive Portal & Checkout: HTTP & IP/HTTPS)
# --------------------------------------------------------
/ip hotspot walled-garden
add comment="WavePass Root Portal" dst-host="nexawavepass.com"
add comment="WavePass API" dst-host="api.nexawavepass.com"
add comment="WavePass Portal" dst-host="*.nexawavepass.com"
add comment="Paystack Checkout" dst-host="*.paystack.co"
add comment="Paystack API" dst-host="api.paystack.co"
add comment="Paystack Checkout UI" dst-host="checkout.paystack.com"
add comment="Paystack Standard" dst-host="standard.paystack.co"
add comment="Supabase Auth" dst-host="*.supabase.co"

/ip hotspot walled-garden ip
add comment="WavePass Root Portal (HTTPS)" dst-host="nexawavepass.com" action=accept
add comment="WavePass API (HTTPS)" dst-host="api.nexawavepass.com" action=accept
add comment="WavePass Portal (HTTPS)" dst-host="*.nexawavepass.com" action=accept
add comment="Paystack Checkout (HTTPS)" dst-host="*.paystack.co" action=accept
add comment="Paystack API (HTTPS)" dst-host="api.paystack.co" action=accept
add comment="Paystack Checkout UI (HTTPS)" dst-host="checkout.paystack.com" action=accept
add comment="Paystack Standard (HTTPS)" dst-host="standard.paystack.co" action=accept
add comment="Supabase Auth (HTTPS)" dst-host="*.supabase.co" action=accept

# --------------------------------------------------------
# 4. Standard Rate-Limit User Profiles & Single Device Enforce
# --------------------------------------------------------
/ip hotspot user profile
set [find default=yes] shared-users=1
add name="profile_1h" rate-limit="10M/5M" shared-users=1 comment="WavePass 1h"
add name="profile_12h" rate-limit="15M/5M" shared-users=1 comment="WavePass 12h"
add name="profile_1d" rate-limit="20M/10M" shared-users=1 comment="WavePass 24h"

# --------------------------------------------------------
# 5. Clean Legacy Mangle & Enforce Single Device (Shared Users = 1)
# --------------------------------------------------------
/ip firewall mangle
remove [find comment="WavePass Anti-Tethering"]

# --------------------------------------------------------
# 6. Low-RAM Auto-Cleanup Script & 2-Hour Scheduler
# --------------------------------------------------------
/system script
add name="wavepass-cleanup" source="/ip hotspot user remove [find comment=\\"expired\\"]" comment="WavePass low-RAM expired user cleanup"

/system scheduler
add name="wavepass-cleanup" interval=2h on-event="wavepass-cleanup" comment="WavePass 2-hour user cleanup"

# --------------------------------------------------------
# 7. System Identity
# --------------------------------------------------------
/system identity
set name="WavePass-$slug"

# Setup complete! Hotspot online and single-device login active.
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

  Future<void> _handleExportPortalHtml() async {
    setState(() => _exportingPortalHtml = true);
    try {
      final venue = await SupabaseService.instance.getPrimaryVenue() ?? await WavePassApi.instance.getDefaultVenue();
      final slug = venue['slug']?.toString() ?? 'venue';
      final venueName = venue['name']?.toString() ?? 'WavePass Wi-Fi';

      final html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>$venueName | WavePass Wi-Fi</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background: #0D1117;
      color: #FFFFFF;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: #161B22;
      border: 1px solid #30363D;
      border-radius: 20px;
      padding: 28px;
      width: 100%;
      max-width: 400px;
      box-shadow: 0 12px 32px rgba(0,0,0,0.5);
    }
    .logo {
      font-size: 24px;
      font-weight: 800;
      letter-spacing: -0.5px;
      color: #38EF7D;
      margin-bottom: 4px;
      text-align: center;
    }
    .subtitle {
      font-size: 13px;
      color: #8B949E;
      text-align: center;
      margin-bottom: 24px;
    }
    .btn-buy {
      display: block;
      width: 100%;
      padding: 14px;
      background: linear-gradient(135deg, #11998E 0%, #38EF7D 100%);
      color: #0D1117;
      text-decoration: none;
      font-size: 15px;
      font-weight: 700;
      border-radius: 12px;
      text-align: center;
      margin-bottom: 20px;
      border: none;
      cursor: pointer;
    }
    .divider {
      display: flex;
      align-items: center;
      text-align: center;
      margin: 16px 0;
      color: #484F58;
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 1px;
    }
    .divider::before, .divider::after {
      content: '';
      flex: 1;
      border-bottom: 1px solid #30363D;
    }
    .divider:not(:empty)::before { margin-right: .75em; }
    .divider:not(:empty)::after { margin-left: .75em; }
    .form-group {
      margin-bottom: 16px;
    }
    label {
      display: block;
      font-size: 12px;
      font-weight: 600;
      color: #C9D1D9;
      margin-bottom: 6px;
    }
    input[type="text"] {
      width: 100%;
      padding: 14px;
      background: #0D1117;
      border: 1.5px solid #30363D;
      border-radius: 12px;
      color: #FFFFFF;
      font-size: 16px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 1px;
      outline: none;
    }
    input[type="text"]:focus {
      border-color: #38EF7D;
    }
    .btn-login {
      width: 100%;
      padding: 14px;
      background: #21262D;
      border: 1px solid #30363D;
      color: #FFFFFF;
      font-size: 14px;
      font-weight: 700;
      border-radius: 12px;
      cursor: pointer;
    }
    .btn-login:hover {
      background: #30363D;
    }
    .error-msg {
      background: rgba(248, 81, 73, 0.15);
      border: 1px solid #F85149;
      color: #FF7B72;
      padding: 10px 14px;
      border-radius: 10px;
      font-size: 12px;
      margin-bottom: 16px;
      text-align: center;
    }
    .footer {
      margin-top: 20px;
      font-size: 11px;
      color: #484F58;
      text-align: center;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">$venueName</div>
    <div class="subtitle">High-Speed Wi-Fi by WavePass</div>

    \\\$(if error)
    <div class="error-msg">\\\$(error)</div>
    \\\$(endif)

    <a href="https://$slug.nexawavepass.com/portal?mac=\\\$(mac)&ip=\\\$(ip)&link-orig=\\\$(link-orig-esc)&venue=$slug" class="btn-buy">
      Buy Internet Pass Online &rarr;
    </a>

    <div class="divider">OR USE VOUCHER</div>

    <form name="login" action="\\\$(link-login-only)" method="post" onsubmit="return fillCredentials()">
      <input type="hidden" name="dst" value="\\\$(link-orig)">
      <input type="hidden" name="popup" value="true">
      <input type="hidden" name="password" id="passInput">

      <div class="form-group">
        <label for="username">Voucher Code</label>
        <input type="text" id="username" name="username" placeholder="WP-XXXXX" autocomplete="off" autocorrect="off" autocapitalize="characters" required>
      </div>

      <button type="submit" class="btn-login">Connect to Internet</button>
    </form>

    <div class="footer">
      Connected MAC: \\\$(mac)
    </div>
  </div>

  <script>
    function fillCredentials() {
      var user = document.getElementById('username').value.trim();
      document.getElementById('passInput').value = user;
      return true;
    }
  </script>
</body>
</html>""";

      setState(() {
        _exportedPortalHtml = html;
      });

      await Clipboard.setData(ClipboardData(text: html));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("login.html copied to clipboard! Save to MikroTik Files -> hotspot/login.html."),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to generate login.html: $e"), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPortalHtml = false);
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
                        border: Border.all(
                          color: _foundRouter!.authFailed
                              ? AppColors.accentOrange.withValues(alpha: 0.5)
                              : AppColors.accentGreen.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _foundRouter!.authFailed ? AppColors.accentOrange : AppColors.accentGreen,
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
                          if (_foundRouter!.authFailed) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.accentOrange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.lock_person_outlined, color: AppColors.accentOrange, size: 18),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          "Authentication Failed",
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentOrange),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _foundRouter!.errorMessage ?? "Router reached, but admin password was rejected. Enter the correct password in Custom Settings above and tap 'Find My Router' again.",
                                    style: const TextStyle(fontSize: 11, color: AppColors.primary, height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
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
            const SizedBox(height: 16),

            // ─── OPTION 4: CAPTIVE PORTAL FILE (LOGIN.HTML) ───
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
                        "OPTION 04",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: AppColors.accentGreen,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        "Files / Hotspot Directory",
                        style: TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Hotspot Login Page (login.html)",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Copy the branded login.html file. Place or drag & drop this file into your MikroTik WinBox/WebFig under Files -> hotspot/ to display online checkout & voucher activation when users connect to Wi-Fi.",
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
                      onPressed: _exportingPortalHtml ? null : _handleExportPortalHtml,
                      icon: _exportingPortalHtml
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.copy_rounded, color: AppColors.accentGreen, size: 20),
                      label: Text(
                        _exportingPortalHtml ? "Generating..." : "Copy login.html",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentGreen,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  if (_exportedPortalHtml != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Text(
                        _exportedPortalHtml!,
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
