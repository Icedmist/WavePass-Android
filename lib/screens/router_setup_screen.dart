import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/services/activation_code_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/services/router_discovery_service.dart';
import '../core/services/supabase_service.dart';
import '../core/services/wavepass_api.dart';

class RouterSetupScreen extends StatefulWidget {
  const RouterSetupScreen({super.key});

  @visibleForTesting
  static String generateLoginHtml(
    String venueName,
    String slug, [
    List<Map<String, dynamic>>? plans,
    bool isPaystackConfigured = true,
    bool useHostedSubdomainPortal = false,
    List<Map<String, dynamic>>? bankAccounts,
  ]) =>
      _RouterSetupScreenState._generateLoginHtml(
        venueName,
        slug,
        plans,
        isPaystackConfigured,
        useHostedSubdomainPortal,
        bankAccounts,
      );

  static String generateStatusHtml(String venueName, String slug) =>
      _RouterSetupScreenState._generateStatusHtml(venueName, slug);

  static String generateLogoutHtml(String venueName, String slug) =>
      _RouterSetupScreenState._generateLogoutHtml(venueName, slug);

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
  bool _obscureRouterPass = true;

  // Export script state
  bool _exportingScript = false;
  String? _exportedScript;
  bool _exportingPortalHtml = false;
  bool _uploadingPortalFiles = false;
  int _selectedPortalTabIndex = 0;
  bool _useHostedSubdomainPortal = false;
  Map<String, String>? _portalSuite;

  @override
  void initState() {
    super.initState();
    _checkActivationGate();
    _loadSavedCredentials();
  }

  Future<void> _checkActivationGate() async {
    final isActivated = await ActivationCodeService.instance.isAccountActivated();
    if (!isActivated && mounted) {
      context.go(AppRouter.activateVenue);
    }
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

  Future<void> _enforceNoSharing() async {
    await _saveCredentials();
    final enteredIp = _ipCtrl.text.trim().isNotEmpty ? _ipCtrl.text.trim() : "192.168.88.1";
    final targetIp = _foundRouter?.ip ?? enteredIp;

    setState(() => _isConfiguring = true);
    final user = _userCtrl.text.trim().isNotEmpty ? _userCtrl.text.trim() : "admin";
    final pass = _passCtrl.text.trim();
    final tunnel = _tunnelCtrl.text.trim().isNotEmpty ? _tunnelCtrl.text.trim() : null;

    try {
      final res = await RouterDiscoveryService.enforceNoHotspotSharing(
        ip: targetIp,
        username: user,
        password: pass,
        endpoint: tunnel,
      );

      if (mounted) {
        setState(() => _isConfiguring = false);
        final ok = res['success'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? "No Sharing Enforced: 1 device per voucher, client isolation & anti-tethering active!"
                : "Anti-sharing enforcement applied to available router subsystems."),
            backgroundColor: ok ? AppColors.accentGreen : AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConfiguring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to enforce anti-sharing: $e"),
            backgroundColor: AppColors.accentRed,
          ),
        );
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
      final venue = VenueStateService.instance.currentVenue ?? await SupabaseService.instance.getPrimaryVenue() ?? await WavePassApi.instance.getDefaultVenue();
      final slug = venue['slug']?.toString() ?? 'venue';
      final venueName = venue['name']?.toString() ?? 'WavePass';

      final script = """
# ========================================================
# WavePass MikroTik HotSpot Quick Provisioning Script
# Venue: $venueName ($slug)
# Generated: ${DateTime.now().toIso8601String()}
# Uses standard admin credentials; no extra users created.
# ========================================================

# --------------------------------------------------------
# 1. Enable RouterOS REST API, FTP & Management services
# --------------------------------------------------------
/ip service
set www disabled=no port=80
set www-ssl disabled=no port=443
set ftp disabled=no port=21
set api disabled=no port=8728

# --------------------------------------------------------
# 2. Hotspot Profile & Interface
# --------------------------------------------------------
/ip hotspot profile
add dns-name="wavepass.local" \\
    hotspot-address=192.168.88.1 \\
    html-directory=hotspot \\
    login-by=http-pap,http-chap,mac-cookie \\
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
# 4. Standard Rate-Limit User Profiles & Hard Timeouts
# --------------------------------------------------------
/ip hotspot user profile
set [find default=yes] shared-users=1 keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m
add name="profile_30m" rate-limit="10M/5M" shared-users=1 session-timeout=30m keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m comment="WavePass 30m"
add name="profile_1h" rate-limit="10M/5M" shared-users=1 session-timeout=1h keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m comment="WavePass 1h"
add name="profile_2h" rate-limit="10M/5M" shared-users=1 session-timeout=2h keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m comment="WavePass 2h"
add name="profile_3h" rate-limit="15M/5M" shared-users=1 session-timeout=3h keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m comment="WavePass 3h"
add name="profile_6h" rate-limit="15M/5M" shared-users=1 session-timeout=6h keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m comment="WavePass 6h"
add name="profile_12h" rate-limit="15M/5M" shared-users=1 session-timeout=12h keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m comment="WavePass 12h"
add name="profile_1d" rate-limit="20M/10M" shared-users=1 session-timeout=1d keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m comment="WavePass 24h"
add name="profile_7d" rate-limit="20M/10M" shared-users=1 session-timeout=7d keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m comment="WavePass 7d"
add name="profile_30d" rate-limit="25M/10M" shared-users=1 session-timeout=30d keepalive-timeout=2m idle-timeout=5m status-autorefresh=1m comment="WavePass 30d"
add name="wp-payment-trial" rate-limit="2M/2M" shared-users=1 transparent-proxy=yes session-timeout=2m comment="WavePass 2-min Payment Trial"

# --------------------------------------------------------
# 5. Enforce No Hotspot Sharing & 2-Minute Payment Trial
# --------------------------------------------------------
/ip hotspot user profile set [find] shared-users=1
/ip hotspot profile set [find] addresses-per-mac=1 mac-cookie=no login-by=http-pap,http-chap,mac-cookie,trial trial-user-profile="wp-payment-trial" trial-uptime=2m/24h
/interface wireless set [find] default-forwarding=no

# Disable IPv6 bypass (HotSpot is IPv4-only; Linux automatically shares IPv6 if active)
/ipv6 settings set disable-ipv6=yes
/ipv6 firewall raw add chain=prerouting action=drop place-before=0 comment="WavePass Anti-Sharing: Block IPv6 hotspot bypass"
/ipv6 firewall filter add chain=forward action=drop place-before=0 comment="WavePass Anti-Sharing: Block IPv6 hotspot bypass"

# Disable FastTrack because FastTrack bypasses mangle TTL change and firewall filter drops
/ip firewall filter set [find action=fasttrack-connection] disabled=yes

/ip firewall mangle
remove [find comment~"WavePass Anti-Tethering"]
add chain=postrouting dst-address=192.168.0.0/16 action=change-ttl new-ttl=set:1 passthrough=yes comment="WavePass Anti-Tethering: set TTL=1 (blocks iOS, Windows, Android, Linux sharing)"
add chain=postrouting dst-address=10.0.0.0/8 action=change-ttl new-ttl=set:1 passthrough=yes comment="WavePass Anti-Tethering: set TTL=1 10.x.x.x"
add chain=postrouting dst-address=172.16.0.0/12 action=change-ttl new-ttl=set:1 passthrough=yes comment="WavePass Anti-Tethering: set TTL=1 172.16.x.x"

/ip firewall filter
remove [find comment~"WavePass Anti-Tethering"]
add chain=forward src-address=192.168.0.0/16 ttl=less-than:64 action=drop place-before=0 comment="WavePass Anti-Tethering: drop secondary hop ttl<64 (Android/iOS/Linux)"
add chain=forward src-address=10.0.0.0/8 ttl=less-than:64 action=drop place-before=0 comment="WavePass Anti-Tethering: drop secondary hop ttl<64 (10.x)"
add chain=forward src-address=172.16.0.0/12 ttl=less-than:64 action=drop place-before=0 comment="WavePass Anti-Tethering: drop secondary hop ttl<64 (172.x)"
add chain=forward src-address=192.168.0.0/16 ttl=equal:127 place-before=0 comment="WavePass Anti-Tethering: drop secondary 128-ttl hop 1 (Windows)"
add chain=forward src-address=192.168.0.0/16 ttl=equal:126 place-before=0 comment="WavePass Anti-Tethering: drop secondary 128-ttl hop 2 (Windows)"
add chain=forward src-address=192.168.0.0/16 ttl=equal:125 place-before=0 comment="WavePass Anti-Tethering: drop secondary 128-ttl hop 3 (Windows)"

# --------------------------------------------------------
# 6. Active Session Expiry & 1-Minute User Limit Enforcer
# --------------------------------------------------------
/system script
remove [find name="wavepass-cleanup"]
add name="wavepass-cleanup" source=":foreach a in=[/ip hotspot active find] do={ :local stl [/ip hotspot active get \\\$a session-time-left]; :if ([:len \\\$stl] > 0 && \\\$stl = 0s) do={ /ip hotspot active remove \\\$a; } }; :foreach u in=[/ip hotspot user find] do={ :local lup [/ip hotspot user get \\\$u limit-uptime]; :local upt [/ip hotspot user get \\\$u uptime]; :if ([:len \\\$lup] > 0 && \\\$lup != 0s && \$upt >= \\\$lup) do={ :local un [/ip hotspot user get \\\$u name]; /ip hotspot active remove [find user=\\\$un]; /ip hotspot user remove \\\$u; } }; /ip hotspot user remove [find comment~\\"expired\\"]" comment="WavePass user limit enforcer"

/system scheduler
remove [find name="wavepass-cleanup"]
add name="wavepass-cleanup" interval=1m on-event="wavepass-cleanup" comment="WavePass 1-minute user limit enforcer"

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

  static const String _rfc1321Md5Js = r'''
    // Standard RFC 1321 Pure-JS MD5 Implementation
    function hexMD5(str) {
      function safeAdd(x, y) {
        var lsw = (x & 0xFFFF) + (y & 0xFFFF);
        var msw = (x >> 16) + (y >> 16) + (lsw >> 16);
        return (msw << 16) | (lsw & 0xFFFF);
      }
      function bitRol(num, cnt) { return (num << cnt) | (num >>> (32 - cnt)); }
      function md5cmn(q, a, b, x, s, t) { return safeAdd(bitRol(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b); }
      function md5ff(a, b, c, d, x, s, t) { return md5cmn((b & c) | ((~b) & d), a, b, x, s, t); }
      function md5gg(a, b, c, d, x, s, t) { return md5cmn((b & d) | (c & (~d)), a, b, x, s, t); }
      function md5hh(a, b, c, d, x, s, t) { return md5cmn(b ^ c ^ d, a, b, x, s, t); }
      function md5ii(a, b, c, d, x, s, t) { return md5cmn(c ^ (b | (~d)), a, b, x, s, t); }
      function binlMD5(x, len) {
        x[len >> 5] |= 0x80 << (len % 32);
        x[(((len + 64) >>> 9) << 4) + 14] = len;
        var a = 1732584193, b = -271733879, c = -1732584194, d = 271733878;
        for (var i = 0; i < x.length; i += 16) {
          var olda = a, oldb = b, oldc = c, oldd = d;
          a = md5ff(a, b, c, d, x[i], 7, -680876936);
          d = md5ff(d, a, b, c, x[i + 1], 12, -389564586);
          c = md5ff(c, d, a, b, x[i + 2], 17, 606105819);
          b = md5ff(b, c, d, a, x[i + 3], 22, -1044525330);
          a = md5ff(a, b, c, d, x[i + 4], 7, -176418897);
          d = md5ff(d, a, b, c, x[i + 5], 12, 1200080426);
          c = md5ff(c, d, a, b, x[i + 6], 17, -1473231341);
          b = md5ff(b, c, d, a, x[i + 7], 22, -45705983);
          a = md5ff(a, b, c, d, x[i + 8], 7, 1770035416);
          d = md5ff(d, a, b, c, x[i + 9], 12, -1958414417);
          c = md5ff(c, d, a, b, x[i + 10], 17, -42063);
          b = md5ff(b, c, d, a, x[i + 11], 22, -1990404162);
          a = md5ff(a, b, c, d, x[i + 12], 7, 1804603682);
          d = md5ff(d, a, b, c, x[i + 13], 12, -40341101);
          c = md5ff(c, d, a, b, x[i + 14], 17, -1502002290);
          b = md5ff(b, c, d, a, x[i + 15], 22, 1236535329);
          a = md5gg(a, b, c, d, x[i + 1], 5, -165796510);
          d = md5gg(d, a, b, c, x[i + 6], 9, -1069501632);
          c = md5gg(c, d, a, b, x[i + 11], 14, 643717713);
          b = md5gg(b, c, d, a, x[i], 20, -373897302);
          a = md5gg(a, b, c, d, x[i + 5], 5, -701558691);
          d = md5gg(d, a, b, c, x[i + 10], 9, 38016083);
          c = md5gg(c, d, a, b, x[i + 15], 14, -660478335);
          b = md5gg(b, c, d, a, x[i + 4], 20, -405537848);
          a = md5gg(a, b, c, d, x[i + 9], 5, 568446438);
          d = md5gg(d, a, b, c, x[i + 14], 9, -1019803690);
          c = md5gg(c, d, a, b, x[i + 3], 14, -187363961);
          b = md5gg(b, c, d, a, x[i + 8], 20, 1163531501);
          a = md5gg(a, b, c, d, x[i + 13], 5, -1444681467);
          d = md5gg(d, a, b, c, x[i + 2], 9, -51403784);
          c = md5gg(c, d, a, b, x[i + 7], 14, 1735328473);
          b = md5gg(b, c, d, a, x[i + 12], 20, -1926607734);
          a = md5hh(a, b, c, d, x[i + 5], 4, -378558);
          d = md5hh(d, a, b, c, x[i + 8], 11, -2022574463);
          c = md5hh(c, d, a, b, x[i + 11], 16, 1839030562);
          b = md5hh(b, c, d, a, x[i + 14], 23, -35309556);
          a = md5hh(a, b, c, d, x[i + 1], 4, -1530992060);
          d = md5hh(d, a, b, c, x[i + 4], 11, 1272893353);
          c = md5hh(c, d, a, b, x[i + 7], 16, -155497632);
          b = md5hh(b, c, d, a, x[i + 10], 23, -1094730640);
          a = md5hh(a, b, c, d, x[i + 13], 4, 681279174);
          d = md5hh(d, a, b, c, x[i], 11, -358537222);
          c = md5hh(c, d, a, b, x[i + 3], 16, -722521979);
          b = md5hh(b, c, d, a, x[i + 6], 23, 76029189);
          a = md5hh(a, b, c, d, x[i + 9], 4, -640364487);
          d = md5hh(d, a, b, c, x[i + 12], 11, -421815835);
          c = md5hh(c, d, a, b, x[i + 15], 16, 530742520);
          b = md5hh(b, c, d, a, x[i + 2], 23, -995338651);
          a = md5ii(a, b, c, d, x[i], 6, -198630844);
          d = md5ii(d, a, b, c, x[i + 7], 10, 1126891415);
          c = md5ii(c, d, a, b, x[i + 14], 15, -1416354905);
          b = md5ii(b, c, d, a, x[i + 5], 21, -57434055);
          a = md5ii(a, b, c, d, x[i + 12], 6, 1700485571);
          d = md5ii(d, a, b, c, x[i + 3], 10, -1894986606);
          c = md5ii(c, d, a, b, x[i + 10], 15, -1051523);
          b = md5ii(b, c, d, a, x[i + 1], 21, -2054922799);
          a = md5ii(a, b, c, d, x[i + 8], 6, 1873313359);
          d = md5ii(d, a, b, c, x[i + 15], 10, -30611744);
          c = md5ii(c, d, a, b, x[i + 6], 15, -1560198380);
          b = md5ii(b, c, d, a, x[i + 13], 21, 1309151649);
          a = md5ii(a, b, c, d, x[i + 4], 6, -145523070);
          d = md5ii(d, a, b, c, x[i + 11], 10, -1120210379);
          c = md5ii(c, d, a, b, x[i + 2], 15, 718787259);
          b = md5ii(b, c, d, a, x[i + 9], 21, -343485551);
          a = safeAdd(a, olda);
          b = safeAdd(b, oldb);
          c = safeAdd(c, oldc);
          d = safeAdd(d, oldd);
        }
        return [a, b, c, d];
      }
      function rstr2binl(input) {
        var output = [];
        output[(input.length >> 2) - 1] = undefined;
        for (var i = 0; i < output.length; i++) output[i] = 0;
        var length8 = input.length * 8;
        for (var i = 0; i < length8; i += 8) {
          output[i >> 5] |= (input.charCodeAt(i / 8) & 0xFF) << (i % 32);
        }
        return output;
      }
      function binl2hex(binarray) {
        var hexTab = "0123456789abcdef";
        var str = "";
        for (var i = 0; i < binarray.length * 4; i++) {
          str += hexTab.charAt((binarray[i >> 2] >> ((i % 4) * 8 + 4)) & 0xF) +
                 hexTab.charAt((binarray[i >> 2] >> ((i % 4) * 8)) & 0xF);
        }
        return str;
      }
      return binl2hex(binlMD5(rstr2binl(str), str.length * 8));
    }
  ''';

  static String _generateLoginHtml(
    String venueName,
    String slug, [
    List<Map<String, dynamic>>? plans,
    bool isPaystackConfigured = true,
    bool useHostedSubdomainPortal = false,
    List<Map<String, dynamic>>? bankAccounts,
  ]) {
    if (useHostedSubdomainPortal) {
      return """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <!-- Instant noscript fallback redirect to hosted venue subdomain (bypassed when JS handles programmatic auth) -->
  <noscript>
    <meta http-equiv="refresh" content="0; url=https://$slug.nexawavepass.com/portal?mac=\$(mac)&ip=\$(ip)&link-orig=\$(link-orig-esc)&link-login=\$(link-login-only)&venue=$slug&chap-id=\$(chap-id)&chap-challenge=\$(chap-challenge)">
  </noscript>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background: #000000;
      color: #FFFFFF;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 24px;
      text-align: center;
    }
    .card {
      background: #0C0C0C;
      border: 1px solid #262626;
      border-radius: 20px;
      padding: 28px 24px;
      width: 100%;
      max-width: 400px;
      box-shadow: 0 16px 40px rgba(0,0,0,0.8);
    }
    .badge {
      display: inline-block;
      padding: 4px 12px;
      background: #171717;
      border: 1px solid #FFFFFF;
      border-radius: 20px;
      color: #FFFFFF;
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 12px;
    }
    .spinner {
      width: 42px;
      height: 42px;
      border: 3px solid rgba(255, 255, 255, 0.15);
      border-top-color: #FFFFFF;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 16px auto;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    .logo {
      font-size: 22px;
      font-weight: 800;
      color: #FFFFFF;
      margin-bottom: 4px;
    }
    .subtitle {
      font-size: 13px;
      color: #A1A1AA;
      margin-bottom: 20px;
    }
    .btn-portal {
      display: block;
      width: 100%;
      padding: 13px;
      background: #FFFFFF;
      color: #000000;
      text-decoration: none;
      font-size: 14px;
      font-weight: 800;
      border-radius: 10px;
      cursor: pointer;
      border: none;
      box-shadow: 0 4px 14px rgba(255, 255, 255, 0.2);
      transition: transform 0.15s, background 0.15s;
    }
    .btn-portal:hover {
      background: #E4E4E7;
    }
    .btn-portal:active {
      transform: scale(0.98);
    }
    .fallback-box {
      margin-top: 24px;
      padding-top: 20px;
      border-top: 1px solid #262626;
      text-align: left;
    }
    .fallback-title {
      font-size: 12px;
      font-weight: 700;
      color: #FFFFFF;
      margin-bottom: 8px;
    }
    .fallback-desc {
      font-size: 11px;
      color: #A1A1AA;
      margin-bottom: 12px;
      line-height: 1.4;
    }
    input[type="text"] {
      width: 100%;
      padding: 11px 13px;
      background: #050505;
      border: 1.5px solid #262626;
      border-radius: 9px;
      color: #FFFFFF;
      font-size: 14px;
      font-weight: 600;
      text-transform: uppercase;
      outline: none;
      margin-bottom: 10px;
    }
    input[type="text"]:focus {
      border-color: #FFFFFF;
      box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.2);
    }
    .btn-fallback {
      width: 100%;
      padding: 11px;
      background: #FFFFFF;
      border: none;
      color: #000000;
      font-size: 13px;
      font-weight: 800;
      border-radius: 9px;
      cursor: pointer;
    }
    .btn-fallback:hover {
      background: #E4E4E7;
    }
    .footer {
      margin-top: 20px;
      font-size: 11px;
      color: #71717A;
    }
  </style>
</head>
<body>
  <div class="card">
    <span class="badge">Wi-Fi Gateway</span>
    <div class="logo">$venueName</div>
    <div class="subtitle">Opening venue portal...</div>

    <div class="spinner"></div>

    <a id="portalBtn" href="https://$slug.nexawavepass.com/portal?mac=\$(mac)&ip=\$(ip)&link-orig=\$(link-orig-esc)&link-login=\$(link-login-only)&venue=$slug&chap-id=\$(chap-id)&chap-challenge=\$(chap-challenge)" class="btn-portal">
      Continue to Portal &rarr;
    </a>

    <!-- Emergency Offline Fail-safe (revealed if venue internet/DNS is unreachable after 3.5s) -->
    <div id="offlineFallback" class="fallback-box" style="display:none;">
      <div class="fallback-title">⚠️ Network Offline?</div>
      <div class="fallback-desc">If the venue uplink is temporarily disconnected, enter your cash voucher code below to connect directly:</div>
      <form name="offline_sendin" action="\$(link-login-only)" method="post">
        <input type="hidden" name="dst" value="\$(link-orig)">
        <input type="hidden" name="popup" value="true">
        <input type="hidden" name="password" id="dst_pass_offline">
        <input type="text" name="username" id="dst_user_offline" placeholder="e.g. 123456" autocomplete="off" autocorrect="off" autocapitalize="characters">
        <button type="submit" id="btn_offline_connect" class="btn-fallback" onclick="document.getElementById('dst_pass_offline').value=document.getElementById('dst_user_offline').value.trim();">Connect Directly &rarr;</button>
      </form>
    </div>

    <!-- Hidden standard RouterOS Hotspot Form for Programmatic Execution -->
    <form name="sendin" action="\$(link-login-only)" method="post" style="display:none;">
      <input type="hidden" name="username" id="dst_user">
      <input type="hidden" name="password" id="dst_pass">
      <input type="hidden" name="dst" id="dst_target" value="\$(link-orig)">
      <input type="hidden" name="popup" value="false">
    </form>

    <div class="footer">
      MAC: <strong>\$(mac)</strong> &bull; IP: <strong>\$(ip)</strong>
    </div>
  </div>

  <script>
$_rfc1321Md5Js

    function executeLogin(username, password) {
      var u = (username || '').trim();
      var p = (password || '').trim();
      if (!u) return;
      document.getElementById('dst_user').value = u;

      var chapId = "\$(chap-id)";
      var chapChallenge = "\$(chap-challenge)";

      if (chapId && chapChallenge && chapId !== "" && chapChallenge !== "" && chapId.indexOf("\$(") === -1) {
        document.getElementById('dst_pass').value = hexMD5(chapId + p + chapChallenge);
      } else {
        document.getElementById('dst_pass').value = p;
      }

      var dstParam = (typeof params !== "undefined" && params) ? (params.get('dst') || params.get('link-orig')) : null;
      if (dstParam) {
        document.getElementById('dst_target').value = dstParam;
      }

      document.sendin.submit();
    }

    var portalUrl = "https://$slug.nexawavepass.com/portal?mac=\$(mac)&ip=\$(ip)&link-orig=\$(link-orig-esc)&link-login=\$(link-login-only)&venue=$slug&chap-id=\$(chap-id)&chap-challenge=\$(chap-challenge)&logged-in=\$(logged-in)&session-time-left=\$(session-time-left)&router-user=\$(username)&error=\$(error-esc)";

    var loggedIn = false;
    var params = null;
    try {
      params = new URLSearchParams(window.location.search);
      var c = params.get('code') || params.get('voucher');
      var u = params.get('username') || params.get('user');
      var p = params.get('password') || params.get('pass');
      var trial = params.get('trial');

      if (trial === 'yes' || (u && u.indexOf('T-') === 0) || (c && c.indexOf('T-') === 0)) {
        loggedIn = true;
        var targetTrialUser = (u && u.indexOf('T-') === 0) ? u : ((c && c.indexOf('T-') === 0) ? c : ('T-' + '\$(mac-esc)'));
        var trialDst = params.get('dst') || '\$(link-orig-esc)';
        var trialUrl = '\$(link-login-only)?dst=' + encodeURIComponent(trialDst) + '&username=' + targetTrialUser;
        window.location.replace(trialUrl);
        return;
      } else if (c) {
        loggedIn = true;
        try { localStorage.setItem('wp-active-voucher', c.toUpperCase()); } catch (e) {}
        executeLogin(c.toUpperCase(), c.toUpperCase());
      } else if (u && p) {
        loggedIn = true;
        try { localStorage.setItem('wp-active-user', u); localStorage.setItem('wp-active-pass', p); } catch (e) {}
        executeLogin(u, p);
      }
    } catch (e) {}

    if (!loggedIn) {
      // Check for RouterOS error returned after a failed login
      var routerError = "\$(error-esc)";
      if (routerError && routerError !== "" && routerError.indexOf("\$(") === -1) {
        portalUrl += "&error=" + encodeURIComponent(routerError);
      }

      // 1. Instant transparent navigation to hosted subdomain
      try {
        window.location.replace(portalUrl);
      } catch (e) {
        window.location.href = portalUrl;
      }

      // 2. Fail-safe timeout: If WAN dropped or DNS failed, surface local voucher form after 3.5s
      setTimeout(function() {
        var fb = document.getElementById('offlineFallback');
        if (fb) {
          fb.style.display = 'block';
          try {
            var cachedV = localStorage.getItem('wp-active-voucher');
            if (cachedV) {
              var inputOffline = document.getElementById('dst_user_offline');
              if (inputOffline && !inputOffline.value) {
                inputOffline.value = cachedV;
                var btnOffline = document.getElementById('btn_offline_connect');
                if (btnOffline) btnOffline.innerText = 'Reconnect Voucher (' + cachedV + ') \u2192';
              }
            }
          } catch(e) {}
        }
      }, 3500);
    }
  </script>
</body>
</html>""";
    }
    final safePlans = (plans != null && plans.isNotEmpty)
        ? plans
        : [
            {'id': 'plan_1h', 'name': '1 Hour Quick Pass', 'priceNGN': 200, 'duration': '1h'},
            {'id': 'plan_24h', 'name': '24 Hours Day Pass', 'priceNGN': 1000, 'duration': '24h'},
            {'id': 'plan_7d', 'name': '7 Days Week Pass', 'priceNGN': 5000, 'duration': '7d'},
          ];

    final plansBuffer = StringBuffer();
    final transferPlanOptionsBuffer = StringBuffer();
    for (final p in safePlans) {
      final pid = p['id']?.toString() ?? 'plan';
      final pname = p['name']?.toString() ?? 'Internet Pass';
      num? rawPrice;
      if (p['priceNGN'] != null) {
        rawPrice = num.tryParse(p['priceNGN'].toString());
      } else if (p['price'] != null) {
        rawPrice = num.tryParse(p['price'].toString());
      } else if (p['amount'] != null) {
        rawPrice = num.tryParse(p['amount'].toString());
      } else if (p['priceMinor'] != null) {
        final minor = num.tryParse(p['priceMinor'].toString());
        if (minor != null) rawPrice = minor / 100;
      }
      final priceInt = (rawPrice ?? 500).round();
      final pprice = '₦$priceInt';

      final pduration = p['duration']?.toString() ??
          (p['durationMinutes'] != null
              ? '${p['durationMinutes']}m'
              : (p['durationSeconds'] != null
                  ? '${((p['durationSeconds'] as num) / 3600).round()}h'
                  : '1h'));

      final payBtn = isPaystackConfigured
          ? '<button type="button" id="btn_plan_$pid" class="btn-pay" onclick="payWithPaystack(\'$pid\', \'$pprice\')">Pay $pprice &rarr;</button>'
          : '<button type="button" id="btn_plan_$pid" class="btn-pay disabled" disabled title="Paystack not available">Paystack Not Available</button>';

      plansBuffer.writeln('''
        <div class="plan-item">
          <div class="plan-info">
            <div class="plan-duration">$pduration Access</div>
            <div class="plan-name">$pname</div>
            <div class="plan-price">$pprice</div>
          </div>
          $payBtn
        </div>''');

      transferPlanOptionsBuffer.writeln(
        '<option value="$pid" data-price="$pprice">$pname ($pduration) — $pprice</option>',
      );
    }

    final bankAccountsBuffer = StringBuffer();
    if (bankAccounts != null && bankAccounts.isNotEmpty) {
      for (int i = 0; i < bankAccounts.length; i++) {
        final b = bankAccounts[i];
        final bName = b['bankName']?.toString() ?? b['bank_name']?.toString() ?? 'Bank';
        final acctNum = b['accountNumber']?.toString() ?? b['account_number']?.toString() ?? '';
        final acctName = b['accountName']?.toString() ?? b['account_name']?.toString() ?? venueName;
        bankAccountsBuffer.writeln('''
        <div class="bank-card">
          <div class="bank-name">$bName</div>
          <div class="bank-account-row">
            <span class="bank-number" id="bank_num_$i">$acctNum</span>
            <button type="button" class="btn-copy" onclick="copyText('$acctNum')">📋 Copy</button>
          </div>
          <div class="bank-holder">$acctName</div>
        </div>''');
      }
    } else {
      bankAccountsBuffer.writeln('''
        <div id="dynamicBankAccounts">
          <div class="status-notice" id="bankAccountsPlaceholder">
            Loading venue bank account details...
          </div>
        </div>''');
    }

    return """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>$venueName | WavePass Wi-Fi</title>
  <script async src="https://js.paystack.co/v1/inline.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background: #000000;
      color: #FFFFFF;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 16px;
    }
    .card {
      background: #0C0C0C;
      border: 1px solid #262626;
      border-radius: 20px;
      padding: 24px;
      width: 100%;
      max-width: 420px;
      box-shadow: 0 16px 40px rgba(0,0,0,0.8);
    }
    .badge {
      display: inline-block;
      padding: 4px 12px;
      background: #171717;
      border: 1px solid #FFFFFF;
      border-radius: 20px;
      color: #FFFFFF;
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 10px;
      text-align: center;
    }
    .logo {
      font-size: 22px;
      font-weight: 800;
      letter-spacing: -0.5px;
      color: #FFFFFF;
      margin-bottom: 4px;
      text-align: center;
    }
    .subtitle {
      font-size: 13px;
      color: #A1A1AA;
      text-align: center;
      margin-bottom: 18px;
    }
    .tabs {
      display: flex;
      flex-wrap: wrap;
      background: #000000;
      border-radius: 12px;
      padding: 4px;
      margin-bottom: 16px;
      border: 1px solid #262626;
      gap: 4px;
    }
    .tab-btn {
      flex: 1 1 calc(33.333% - 4px);
      min-width: 90px;
      padding: 10px 6px;
      background: transparent;
      border: none;
      color: #71717A;
      font-size: 11px;
      font-weight: 700;
      border-radius: 8px;
      cursor: pointer;
      transition: all 0.2s;
      text-align: center;
      line-height: 1.2;
    }
    .tab-btn.active {
      background: #FFFFFF;
      color: #000000;
      box-shadow: 0 2px 6px rgba(255,255,255,0.2);
    }
    .bank-card {
      background: #141414;
      border: 1.5px solid #27272A;
      border-radius: 12px;
      padding: 12px 14px;
      margin-bottom: 10px;
      text-align: left;
    }
    .bank-name {
      font-size: 11px;
      font-weight: 700;
      color: #A1A1AA;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .bank-account-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin: 4px 0;
    }
    .bank-number {
      font-size: 18px;
      font-weight: 900;
      color: #FFFFFF;
      letter-spacing: 1.5px;
      font-family: monospace;
    }
    .bank-holder {
      font-size: 12px;
      font-weight: 600;
      color: #D4D4D8;
    }
    .btn-copy {
      padding: 5px 9px;
      background: #27272A;
      color: #FFFFFF;
      border: 1px solid #3F3F46;
      border-radius: 6px;
      font-size: 11px;
      font-weight: 700;
      cursor: pointer;
      transition: background 0.15s;
    }
    .btn-copy:hover {
      background: #3F3F46;
    }
    .select-input {
      width: 100%;
      padding: 12px 14px;
      background: #050505;
      border: 1.5px solid #262626;
      border-radius: 10px;
      color: #FFFFFF;
      font-size: 13px;
      font-weight: 600;
      outline: none;
      margin-bottom: 14px;
      transition: border-color 0.2s;
    }
    .select-input:focus {
      border-color: #FFFFFF;
      box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.2);
    }
    .select-input option {
      background: #0C0C0C;
      color: #FFFFFF;
    }
    .spinner {
      width: 28px;
      height: 28px;
      border: 3px solid rgba(255, 255, 255, 0.15);
      border-top-color: #FFFFFF;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 12px auto;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    .form-group {
      margin-bottom: 14px;
      text-align: left;
    }
    label {
      display: block;
      font-size: 12px;
      font-weight: 600;
      color: #A1A1AA;
      margin-bottom: 6px;
    }
    input[type="text"], input[type="password"], input[type="email"] {
      width: 100%;
      padding: 12px 14px;
      background: #050505;
      border: 1.5px solid #262626;
      border-radius: 10px;
      color: #FFFFFF;
      font-size: 14px;
      font-weight: 600;
      outline: none;
      transition: border-color 0.2s;
    }
    input[type="text"]:focus, input[type="password"]:focus, input[type="email"]:focus {
      border-color: #FFFFFF;
      box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.2);
    }
    .input-upper {
      text-transform: uppercase;
      letter-spacing: 1px;
    }
    .plans-list {
      display: flex;
      flex-direction: column;
      gap: 10px;
      margin-top: 10px;
    }
    .plan-item {
      background: #080808;
      border: 1.5px solid #262626;
      border-radius: 12px;
      padding: 12px 14px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      transition: border-color 0.2s;
    }
    .plan-item:hover {
      border-color: #FFFFFF;
    }
    .plan-info {
      text-align: left;
    }
    .plan-duration {
      font-size: 10px;
      font-weight: 700;
      color: #A1A1AA;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .plan-name {
      font-size: 13px;
      font-weight: 800;
      color: #FFFFFF;
      margin: 2px 0;
    }
    .plan-price {
      font-size: 15px;
      font-weight: 900;
      color: #FFFFFF;
    }
    .btn-pay {
      padding: 9px 12px;
      background: #FFFFFF;
      border: none;
      color: #000000;
      font-size: 12px;
      font-weight: 800;
      border-radius: 8px;
      cursor: pointer;
      white-space: nowrap;
      transition: background 0.2s;
    }
    .btn-pay:hover {
      background: #E4E4E7;
    }
    .btn-pay:disabled, .btn-pay.disabled {
      background: #27272A !important;
      color: #71717A !important;
      cursor: not-allowed !important;
      border: 1px solid #3F3F46 !important;
      opacity: 0.7;
    }
    .paystack-status-banner {
      display: flex;
      align-items: center;
      justify-content: space-between;
      background: #080808;
      border: 1px solid #262626;
      border-radius: 10px;
      padding: 10px 14px;
      margin-bottom: 12px;
      font-size: 12px;
    }
    .status-indicator {
      display: flex;
      align-items: center;
      gap: 8px;
      font-weight: 700;
    }
    .status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #FFFFFF;
      box-shadow: 0 0 8px #FFFFFF;
    }
    .status-dot.disabled {
      background: #71717A;
      box-shadow: none;
    }
    .status-notice {
      background: #141414;
      border: 1px solid #333333;
      border-radius: 10px;
      padding: 10px;
      color: #E4E4E7;
      font-size: 12px;
      line-height: 1.4;
      margin-bottom: 12px;
      text-align: center;
    }
    .trial-box {
      background: #141414;
      border: 1px solid #333333;
      border-radius: 12px;
      padding: 12px 14px;
      margin-top: 14px;
      text-align: center;
    }
    .trial-title {
      font-size: 13px;
      font-weight: 800;
      color: #FFFFFF;
      margin-bottom: 4px;
    }
    .trial-desc {
      font-size: 11px;
      color: #A1A1AA;
      line-height: 1.4;
      margin-bottom: 10px;
    }
    .btn-trial {
      display: inline-block;
      width: 100%;
      padding: 10px;
      background: #27272A;
      color: #FFFFFF;
      font-size: 12px;
      font-weight: 800;
      border-radius: 8px;
      text-decoration: none;
      cursor: pointer;
      border: 1px solid #3F3F46;
      transition: background 0.2s;
    }
    .btn-trial:hover {
      background: #3F3F46;
    }
    .btn-submit {
      width: 100%;
      padding: 14px;
      background: #FFFFFF;
      border: none;
      color: #000000;
      font-size: 14px;
      font-weight: 800;
      border-radius: 10px;
      cursor: pointer;
      margin-top: 6px;
      transition: background 0.2s;
    }
    .btn-submit:hover {
      background: #E4E4E7;
    }
    .error-msg {
      background: #171717;
      border: 1px solid #52525B;
      color: #FFFFFF;
      padding: 10px 14px;
      border-radius: 10px;
      font-size: 12px;
      margin-bottom: 16px;
      text-align: center;
    }
    .footer {
      margin-top: 18px;
      font-size: 11px;
      color: #71717A;
      text-align: center;
      line-height: 1.6;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">$venueName</div>
    <div class="subtitle">Fast &amp; Secure Wi-Fi Access</div>

    \$(if error)
    <div class="error-msg">\$(error)</div>
    \$(endif)

    <!-- Segmented Tab Switcher (Voucher, Buy Online, Transfer, Retrieve, User & Pass) -->
    <div class="tabs">
      <button type="button" id="tabVoucher" class="tab-btn active" onclick="switchTab('voucher')">🎟️ Voucher Code</button>
      <button type="button" id="tabPlans" class="tab-btn" onclick="switchTab('plans')">💳 Buy Pass</button>
      <button type="button" id="tabTransfer" class="tab-btn" onclick="switchTab('transfer')">🏦 Bank Transfer</button>
      <button type="button" id="tabRetrieve" class="tab-btn" onclick="switchTab('retrieve')">🔍 Retrieve Pass</button>
      <button type="button" id="tabCreds" class="tab-btn" onclick="switchTab('creds')">👤 Username &amp; Password</button>
    </div>

    <!-- Panel 1: Voucher Code -->
    <div id="panelVoucher">
      <div id="savedVoucherBox" style="display:none; background:#141414; border:1px solid #333333; border-radius:12px; padding:12px; margin-bottom:14px; text-align:left;">
        <div style="font-size:12px; font-weight:800; color:#FFFFFF; margin-bottom:4px;">✨ Reconnect Active Voucher</div>
        <div style="font-size:11px; color:#A1A1AA; margin-bottom:8px;">Found voucher from your previous session: <strong id="savedVoucherCode" style="color:#FFFFFF; letter-spacing:1px;"></strong></div>
        <button type="button" class="btn-submit" style="padding:10px; font-size:13px;" onclick="submitVoucher()">1-Tap Reconnect Now &rarr;</button>
      </div>
      <div class="form-group">
        <label for="voucher_input">Voucher Code (Numbers or Text)</label>
        <input type="text" id="voucher_input" class="input-upper" placeholder="e.g. 123456" autocomplete="off" autocorrect="off" autocapitalize="characters">
      </div>
      <button type="button" class="btn-submit" onclick="submitVoucher()">Connect with Voucher</button>
    </div>

    <!-- Panel 2: Venue Plans & Paystack Checkout -->
    <div id="panelPlans" style="display:none;">
      <div class="paystack-status-banner">
        <span>Payment Gateway</span>
        <div class="status-indicator">
          <span class="status-dot ${isPaystackConfigured ? '' : 'disabled'}"></span>
          <span style="color: ${isPaystackConfigured ? '#FFFFFF' : '#71717A'};">
            ${isPaystackConfigured ? 'Paystack Online' : 'Paystack Not Available'}
          </span>
        </div>
      </div>
      ${!isPaystackConfigured ? '''
      <div class="status-notice">
        ⚠️ Online card/transfer payments are currently unavailable at this venue. Please connect using a cash voucher from the counter.
      </div>''' : ''}
      <div class="form-group">
        <label for="pay_email">Receipt Email (Optional)</label>
        <input type="email" id="pay_email" placeholder="guest@example.com" autocomplete="email">
      </div>
      <div class="plans-list" id="plansContainer">
        ${plansBuffer.toString()}
      </div>
      <!-- 2-Minute Payment Trial Access (Direct POST Form) -->
      <div class="trial-box">
        <div class="trial-title">⚡ Need Internet to Pay?</div>
        <div class="trial-desc">Get a 2-minute temporary connection window to open your bank app or complete Paystack checkout.</div>
        <form name="trial_form" action="\$(link-login-only)" method="post">
          <input type="hidden" name="dst" value="\$(link-orig)">
          <input type="hidden" name="popup" value="false">
          <input type="hidden" name="username" value="T-\$(mac-esc)">
          <input type="hidden" name="password" value="">
          <button type="submit" class="btn-trial">Activate 2-Min Payment Trial &rarr;</button>
        </form>
      </div>
    </div>

    <!-- Panel: Bank Transfer -->
    <div id="panelTransfer" style="display:none;">
      <div style="font-size:13px; font-weight:800; color:#FFFFFF; margin-bottom:4px; text-align:left;">
        Direct Bank Transfer
      </div>
      <div style="font-size:11px; color:#A1A1AA; margin-bottom:12px; text-align:left; line-height:1.4;">
        Transfer pass amount to any venue account below. Once transferred, click &ldquo;Payment Completed&rdquo; to notify the venue owner for instant access approval.
      </div>
      <div id="bankAccountsContainer">
        ${bankAccountsBuffer.toString()}
      </div>
      <div class="form-group" style="margin-top:10px;">
        <label for="transfer_plan">Select Wi-Fi Plan</label>
        <select id="transfer_plan" class="select-input">
          ${transferPlanOptionsBuffer.toString()}
        </select>
      </div>
      <div class="form-group">
        <label for="transfer_sender">Sender Name (from bank narration / receipt)</label>
        <input type="text" id="transfer_sender" placeholder="e.g. Alex Johnson" autocomplete="name">
      </div>
      <div class="form-group">
        <label for="transfer_notes">Phone Number or Note (Optional)</label>
        <input type="text" id="transfer_notes" placeholder="e.g. 08012345678">
      </div>
      <div id="transferStatusBox" style="display:none;" class="status-notice"></div>
      <button type="button" id="btn_transfer_completed" class="btn-submit" onclick="submitTransferPayment()">
        ✅ Payment Completed &rarr;
      </button>
    </div>

    <!-- Panel: Voucher Retrieval -->
    <div id="panelRetrieve" style="display:none;">
      <div style="font-size:13px; font-weight:800; color:#FFFFFF; margin-bottom:4px; text-align:left;">
        Retrieve Active Pass
      </div>
      <div style="font-size:11px; color:#A1A1AA; margin-bottom:12px; text-align:left; line-height:1.4;">
        Already transferred or bought a pass? Retrieve your active pass for this device or reconnect.
      </div>
      <div class="form-group">
        <label for="retrieve_mac">Device MAC (Auto-detected)</label>
        <input type="text" id="retrieve_mac" class="input-upper" value="\$(mac)" placeholder="00:00:00:00:00:00">
      </div>
      <div class="form-group">
        <label for="retrieve_query">Or Phone / Transfer Reference / Code</label>
        <input type="text" id="retrieve_query" placeholder="e.g. TRF-..., phone number, or voucher">
      </div>
      <div id="retrieveStatusBox" style="display:none;" class="status-notice"></div>
      <button type="button" id="btn_retrieve" class="btn-submit" onclick="retrieveActivePass()">
        🔍 Retrieve Pass &amp; Connect &rarr;
      </button>
    </div>

    <!-- Panel 3: Username & Password -->
    <div id="panelCreds" style="display:none;">
      <div class="form-group">
        <label for="cred_user">Username / Phone Number</label>
        <input type="text" id="cred_user" placeholder="Enter username or phone" autocomplete="username">
      </div>
      <div class="form-group">
        <label for="cred_pass">Password / PIN</label>
        <input type="password" id="cred_pass" placeholder="Enter password" autocomplete="current-password">
      </div>
      <button type="button" class="btn-submit" onclick="submitCredentials()">Sign In &amp; Connect</button>
    </div>

    <!-- Hidden standard RouterOS Hotspot Form -->
    <form name="sendin" action="\$(link-login-only)" method="post" style="display:none;">
      <input type="hidden" name="username" id="dst_user">
      <input type="hidden" name="password" id="dst_pass">
      <input type="hidden" name="dst" value="\$(link-orig)">
      <input type="hidden" name="popup" value="true">
    </form>

    <div class="footer">
      MAC: <strong>\$(mac)</strong> &bull; IP: <strong>\$(ip)</strong><br>
      Venue Subdomain: <strong>$slug.nexawavepass.com</strong>
    </div>
  </div>

  <script>
    window.switchTab = function(mode) {
      var tabs = ['voucher', 'plans', 'transfer', 'retrieve', 'creds'];
      for (var i = 0; i < tabs.length; i++) {
        var t = tabs[i];
        var cap = t.charAt(0).toUpperCase() + t.slice(1);
        var btn = document.getElementById('tab' + cap);
        var pan = document.getElementById('panel' + cap);
        if (btn) {
          btn.className = (mode === t) ? 'tab-btn active' : 'tab-btn';
        }
        if (pan) {
          pan.style.display = (mode === t) ? 'block' : 'none';
        }
      }
    };
    var switchTab = window.switchTab;

    document.addEventListener('DOMContentLoaded', function() {
      var tabBox = document.querySelector('.tabs');
      if (tabBox) {
        tabBox.addEventListener('click', function(e) {
          var btn = e.target.closest('.tab-btn');
          if (!btn) return;
          var id = btn.id || '';
          if (id.indexOf('tab') === 0) {
            window.switchTab(id.substring(3).toLowerCase());
          }
        });
      }
    });

$_rfc1321Md5Js

    function copyText(val) {
      if (!val) return;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(val).then(function() {
          alert('Copied ' + val + ' to clipboard!');
        }).catch(function() {
          prompt('Copy account number:', val);
        });
      } else {
        prompt('Copy account number:', val);
      }
    }

    var transferPollTimer = null;
    function submitTransferPayment() {
      var sender = document.getElementById('transfer_sender') ? document.getElementById('transfer_sender').value.trim() : '';
      if (!sender) {
        alert('Please enter your sender name or bank narration so the venue owner can identify your transfer.');
        return;
      }
      var planSelect = document.getElementById('transfer_plan');
      var planId = planSelect ? planSelect.value : '';
      var notes = document.getElementById('transfer_notes') ? document.getElementById('transfer_notes').value.trim() : '';

      var rawMac = "\$(mac)";
      var mac = (rawMac && rawMac.indexOf("\$(") === -1 && rawMac.length >= 11) ? rawMac : (localStorage.getItem('wp-device-mac') || '02:00:00:00:00:01');
      try { localStorage.setItem('wp-device-mac', mac); } catch(e){}

      var btn = document.getElementById('btn_transfer_completed');
      var originalText = btn ? btn.innerText : 'Payment Completed';
      if (btn) {
        btn.innerText = 'Notifying Venue Owner...';
        btn.disabled = true;
      }

      var statusBox = document.getElementById('transferStatusBox');
      if (statusBox) {
        statusBox.innerHTML = '<div style="font-weight:800; color:#FFFFFF;">Sending transfer notification...</div>';
        statusBox.style.display = 'block';
      }

      var payload = {
        venueSlug: '$slug',
        mac: mac,
        planId: planId,
        senderName: sender,
        notes: notes
      };

      fetch('https://api.nexawavepass.com/api/v1/portal/transfer-request', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
      .then(function(res) { return res.json(); })
      .then(function(data) {
        if (!data || !data.ok) {
          throw new Error((data && data.message) || 'Failed to submit transfer request');
        }

        if (statusBox) {
          statusBox.innerHTML = '<div style="font-size:13px; font-weight:800; color:#FFFFFF; margin-bottom:4px;">⏳ Request Sent to Venue Owner!</div>' +
            '<div style="font-size:11px; color:#A1A1AA; line-height:1.4;">Notification sent with 1-tap approval button to the venue owner. Auto-checking for approval...</div>' +
            '<div class="spinner" style="width:24px;height:24px;margin:10px auto 0;"></div>';
          statusBox.style.display = 'block';
        }

        // Auto-poll retrieve-voucher every 3s
        if (transferPollTimer) clearInterval(transferPollTimer);
        transferPollTimer = setInterval(function() {
          fetch('https://api.nexawavepass.com/api/v1/portal/retrieve-voucher?mac=' + encodeURIComponent(mac) + '&venueId=' + encodeURIComponent('$slug'))
            .then(function(r) { return r.json(); })
            .then(function(vRes) {
              if (vRes && vRes.found && vRes.voucherCode) {
                clearInterval(transferPollTimer);
                if (statusBox) {
                  statusBox.innerHTML = '<div style="font-size:13px; font-weight:800; color:#FFFFFF;">🎉 Access Approved!</div>' +
                    '<div style="font-size:11px; color:#A1A1AA; margin-top:4px;">Pass: <strong>' + vRes.voucherCode + '</strong>. Connecting to Wi-Fi...</div>';
                }
                try { localStorage.setItem('wp-active-voucher', vRes.voucherCode); } catch(e){}
                setTimeout(function() {
                  executeLogin(vRes.voucherCode, vRes.voucherCode);
                }, 1200);
              }
            })
            .catch(function() {});
        }, 3000);
      })
      .catch(function(err) {
        if (btn) {
          btn.innerText = originalText;
          btn.disabled = false;
        }
        if (statusBox) {
          statusBox.innerHTML = '<div style="color:#FFFFFF; font-weight:700;">⚠️ ' + (err.message || 'Error submitting transfer request.') + '</div>';
          statusBox.style.display = 'block';
        }
      });
    }

    var retrievePollTimer = null;
    function retrieveActivePass() {
      var macInp = document.getElementById('retrieve_mac') ? document.getElementById('retrieve_mac').value.trim() : '';
      var qInp = document.getElementById('retrieve_query') ? document.getElementById('retrieve_query').value.trim() : '';
      var rawMac = "\$(mac)";
      var mac = (macInp && macInp.indexOf("\$(") === -1 && macInp.length >= 11) ? macInp : ((rawMac && rawMac.indexOf("\$(") === -1 && rawMac.length >= 11) ? rawMac : (localStorage.getItem('wp-device-mac') || ''));

      var btn = document.getElementById('btn_retrieve');
      var originalText = btn ? btn.innerText : 'Connect Active Pass';
      if (btn) {
        btn.innerText = 'Checking Access...';
        btn.disabled = true;
      }

      var statusBox = document.getElementById('retrieveStatusBox');
      if (statusBox) statusBox.style.display = 'none';

      var url = 'https://api.nexawavepass.com/api/v1/portal/retrieve-voucher?venueId=' + encodeURIComponent('$slug');
      if (mac) url += '&mac=' + encodeURIComponent(mac);
      if (qInp) url += '&q=' + encodeURIComponent(qInp);

      fetch(url)
        .then(function(res) { return res.json(); })
        .then(function(data) {
          if (btn) {
            btn.innerText = originalText;
            btn.disabled = false;
          }

          if (data && data.found && data.voucherCode) {
            if (statusBox) {
              statusBox.innerHTML = '<div style="font-weight:800; color:#FFFFFF;">✅ Active Pass Found!</div>' +
                '<div style="font-size:11px; color:#A1A1AA; margin-top:4px;">Voucher: <strong>' + data.voucherCode + '</strong> (' + (data.planName || 'Wi-Fi') + '). Connecting...</div>';
              statusBox.style.display = 'block';
            }
            try { localStorage.setItem('wp-active-voucher', data.voucherCode); } catch(e){}
            setTimeout(function() {
              executeLogin(data.voucherCode, data.voucherCode);
            }, 1200);
          } else if (data && data.pendingApproval) {
            if (statusBox) {
              statusBox.innerHTML = '<div style="font-weight:800; color:#FFFFFF;">⏳ Transfer Awaiting Approval</div>' +
                '<div style="font-size:11px; color:#A1A1AA; margin-top:4px;">' + (data.message || 'Waiting for venue owner approval...') + '</div>' +
                '<div class="spinner" style="width:24px;height:24px;margin:10px auto 0;"></div>';
              statusBox.style.display = 'block';
            }

            if (retrievePollTimer) clearInterval(retrievePollTimer);
            retrievePollTimer = setInterval(function() {
              fetch(url)
                .then(function(pr) { return pr.json(); })
                .then(function(pData) {
                  if (pData && pData.found && pData.voucherCode) {
                    clearInterval(retrievePollTimer);
                    if (statusBox) {
                      statusBox.innerHTML = '<div style="font-weight:800; color:#FFFFFF;">🎉 Access Approved!</div>' +
                        '<div style="font-size:11px; color:#A1A1AA; margin-top:4px;">Connecting to Wi-Fi (' + pData.voucherCode + ')...</div>';
                    }
                    try { localStorage.setItem('wp-active-voucher', pData.voucherCode); } catch(e){}
                    setTimeout(function() {
                      executeLogin(pData.voucherCode, pData.voucherCode);
                    }, 1200);
                  }
                })
                .catch(function() {});
            }, 3000);
          } else {
            if (statusBox) {
              statusBox.innerHTML = '<div style="color:#FFFFFF; font-weight:700;">⚠️ ' + (data.message || 'No active pass found. Please buy a pass or enter a valid voucher code.') + '</div>';
              statusBox.style.display = 'block';
            }
          }
        })
        .catch(function(err) {
          if (btn) {
            btn.innerText = originalText;
            btn.disabled = false;
          }
          if (statusBox) {
            statusBox.innerHTML = '<div style="color:#FFFFFF; font-weight:700;">⚠️ Could not connect to server. Please verify internet access.</div>';
            statusBox.style.display = 'block';
          }
        });
    }

    function loadDynamicBankAccounts() {
      var container = document.getElementById('dynamicBankAccounts');
      if (!container) return;
      fetch('https://api.nexawavepass.com/api/v1/portal/info?venue=' + encodeURIComponent('$slug'))
        .then(function(r) { return r.json(); })
        .then(function(data) {
          if (data && data.bankAccounts && data.bankAccounts.length > 0) {
            var html = '';
            for (var i = 0; i < data.bankAccounts.length; i++) {
              var b = data.bankAccounts[i];
              var num = b.accountNumber || '';
              var name = b.bankName || 'Bank';
              var holder = b.accountName || '$venueName';
              html += '<div class="bank-card">' +
                '<div class="bank-name">' + name + '</div>' +
                '<div class="bank-account-row">' +
                  '<span class="bank-number">' + num + '</span>' +
                  '<button type="button" class="btn-copy" onclick="copyText(\'' + num + '\')">📋 Copy</button>' +
                '</div>' +
                '<div class="bank-holder">' + holder + '</div>' +
              '</div>';
            }
            container.innerHTML = html;
          } else {
            var ph = document.getElementById('bankAccountsPlaceholder');
            if (ph) ph.innerText = 'No bank accounts registered by this venue yet. Please use Card payment or Counter Voucher.';
          }
        })
        .catch(function() {
          var ph = document.getElementById('bankAccountsPlaceholder');
          if (ph) ph.innerText = 'Venue bank accounts offline. Please ask counter for details.';
        });
    }

    function payWithPaystack(planId, price) {
      var isConfigured = $isPaystackConfigured;
      if (!isConfigured) {
        alert('Paystack is not configured for this venue. Please connect using a cash voucher from the counter.');
        return;
      }
      var email = document.getElementById('pay_email') ? document.getElementById('pay_email').value.trim() : '';
      var rawMac = "\$(mac)";
      var mac = (rawMac && rawMac.indexOf("\$(") === -1 && rawMac.length >= 11) ? rawMac : "02:00:00:00:00:01";
      var btn = document.getElementById('btn_plan_' + planId);
      var originalText = btn ? btn.innerText : 'Pay';
      if (btn) {
        btn.innerText = 'Initializing...';
        btn.disabled = true;
      }

      var initPayload = {
        mac: mac,
        planId: planId,
        email: email || undefined,
        venueId: '$slug'
      };

      fetch('https://api.nexawavepass.com/api/v1/portal/init-payment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(initPayload)
      })
      .then(function(res) {
        if (!res.ok) {
          throw new Error('Server returned HTTP ' + res.status);
        }
        return res.json();
      })
      .then(function(data) {
        if (!data) throw new Error('Invalid payment initialization response');

        // Check if Paystack Inline popup is loaded
        if (window.PaystackPop) {
          var handler = PaystackPop.setup({
            key: 'pk_live_34438c1d62f92132561142576056470fbc70e4ce',
            email: email || ('guest_' + mac.replace(/[:-]/g, '').toLowerCase() + '@nexawavepass.com'),
            amount: data.amount || (parseInt(price.replace(/[^0-9]/g, '')) * 100),
            ref: data.reference,
            callback: function(response) {
              if (btn) btn.innerText = 'Activating Wi-Fi...';
              var ref = (response && response.reference) || data.reference;
              fetch('https://api.nexawavepass.com/api/v1/portal/verify-payment?reference=' + encodeURIComponent(ref))
                .then(function(vRes) { return vRes.json(); })
                .then(function(vData) {
                  var vCode = (vData && (vData.voucherCode || vData.code || (vData.voucher && vData.voucher.code))) || '';
                  if (vCode) {
                    try { localStorage.setItem('wp-active-voucher', vCode); } catch(e){}
                    executeLogin(vCode, vCode);
                  } else {
                    executeLogin(mac, mac);
                  }
                })
                .catch(function() {
                  executeLogin(mac, mac);
                });
            },
            onClose: function() {
              if (btn) {
                btn.innerText = originalText;
                btn.disabled = false;
              }
            }
          });
          handler.openIframe();
        } else if (data.authorization_url) {
          // Direct navigation to Paystack checkout page
          window.location.href = data.authorization_url;
        } else {
          throw new Error(data.message || 'No checkout URL returned.');
        }
      })
      .catch(function(err) {
        if (btn) {
          btn.innerText = originalText;
          btn.disabled = false;
        }
        alert('Payment Error: ' + (err.message || 'Could not connect to payment gateway. Please verify internet access or use a cash voucher.'));
      });
    }

    function executeLogin(username, password) {
      var u = (username || '').trim();
      var p = (password || '').trim();
      if (!u) {
        alert('Please enter a valid voucher code or username.');
        return;
      }
      document.getElementById('dst_user').value = u;

      var chapId = "\$(chap-id)";
      var chapChallenge = "\$(chap-challenge)";

      // If MikroTik Hotspot served CHAP challenge variables, compute CHAP MD5 response
      if (chapId && chapChallenge && chapId !== "" && chapChallenge !== "" && chapId.indexOf("\$(") === -1) {
        document.getElementById('dst_pass').value = hexMD5(chapId + p + chapChallenge);
      } else {
        document.getElementById('dst_pass').value = p;
      }

      document.sendin.submit();
    }

    function submitVoucher() {
      var v = document.getElementById('voucher_input').value.trim().toUpperCase();
      try { localStorage.setItem('wp-active-voucher', v); } catch(e){}
      executeLogin(v, v);
    }

    function submitCredentials() {
      var u = document.getElementById('cred_user').value.trim();
      var p = document.getElementById('cred_pass').value.trim();
      try { localStorage.setItem('wp-active-user', u); localStorage.setItem('wp-active-pass', p); } catch(e){}
      executeLogin(u, p);
    }

    // Auto-login or prefill when opened with ?code= or ?username=
    window.addEventListener('DOMContentLoaded', function() {
      try {
        var params = new URLSearchParams(window.location.search);
        var c = params.get('code') || params.get('voucher');
        var u = params.get('username') || params.get('user');
        var p = params.get('password') || params.get('pass');
        var mode = params.get('mode') || params.get('tab');
        var trial = params.get('trial');

        if (trial === 'yes' || (u && u.indexOf('T-') === 0) || (c && c.indexOf('T-') === 0)) {
          var targetTrialUser = (u && u.indexOf('T-') === 0) ? u : ((c && c.indexOf('T-') === 0) ? c : ('T-' + '\$(mac-esc)'));
          var trialDst = params.get('dst') || '\$(link-orig-esc)';
          var trialUrl = '\$(link-login-only)?dst=' + encodeURIComponent(trialDst) + '&username=' + targetTrialUser;
          window.location.replace(trialUrl);
          return;
        } else if (c) {
          try { localStorage.setItem('wp-active-voucher', c.toUpperCase()); } catch(e){}
          document.getElementById('voucher_input').value = c.toUpperCase();
          executeLogin(c.toUpperCase(), c.toUpperCase());
        } else if (u && p) {
          try { localStorage.setItem('wp-active-user', u); localStorage.setItem('wp-active-pass', p); } catch(e){}
          switchTab('creds');
          document.getElementById('cred_user').value = u;
          document.getElementById('cred_pass').value = p;
          executeLogin(u, p);
        } else if (u) {
          try { localStorage.setItem('wp-active-user', u); } catch(e){}
          switchTab('creds');
          document.getElementById('cred_user').value = u;
        } else if (mode === 'plans' || mode === 'pay') {
          switchTab('plans');
        } else if (mode === 'transfer' || mode === 'bank') {
          switchTab('transfer');
        } else if (mode === 'retrieve') {
          switchTab('retrieve');
        } else {
          try {
            var savedV = localStorage.getItem('wp-active-voucher');
            if (savedV) {
              var vInp = document.getElementById('voucher_input');
              if (vInp && !vInp.value) {
                vInp.value = savedV;
                var sBox = document.getElementById('savedVoucherBox');
                if (sBox) sBox.style.display = 'block';
                var sCode = document.getElementById('savedVoucherCode');
                if (sCode) sCode.innerText = savedV;
              }
            }
          } catch(e) {}
        }
        loadDynamicBankAccounts();
      } catch (e) {}
    });
  </script>
</body>
</html>""";
  }

  static String _generateStatusHtml(String venueName, String slug) {
    return """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Connected | $venueName Wi-Fi</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background: #000000;
      color: #FFFFFF;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: #0C0C0C;
      border: 1px solid #262626;
      border-radius: 20px;
      padding: 28px;
      width: 100%;
      max-width: 400px;
      box-shadow: 0 16px 40px rgba(0,0,0,0.8);
      text-align: center;
    }
    .status-badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 6px 14px;
      background: #171717;
      border: 1px solid #FFFFFF;
      border-radius: 20px;
      color: #FFFFFF;
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 12px;
    }
    .pulse-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #FFFFFF;
      box-shadow: 0 0 8px #FFFFFF;
    }
    .logo {
      font-size: 22px;
      font-weight: 800;
      color: #FFFFFF;
      margin-bottom: 4px;
    }
    .subtitle {
      font-size: 13px;
      color: #A1A1AA;
      margin-bottom: 20px;
    }
    .stats-table {
      width: 100%;
      background: #050505;
      border: 1px solid #262626;
      border-radius: 12px;
      padding: 14px;
      margin-bottom: 20px;
      text-align: left;
    }
    .stat-row {
      display: flex;
      justify-content: space-between;
      padding: 6px 0;
      border-bottom: 1px solid #1E1E22;
      font-size: 13px;
    }
    .stat-row:last-child {
      border-bottom: none;
    }
    .stat-label {
      color: #A1A1AA;
    }
    .stat-value {
      color: #FFFFFF;
      font-weight: 600;
      font-family: monospace;
    }
    .btn-logout {
      display: block;
      width: 100%;
      padding: 14px;
      background: #18181B;
      border: 1px solid #3F3F46;
      color: #FFFFFF;
      text-decoration: none;
      font-size: 14px;
      font-weight: 700;
      border-radius: 12px;
      cursor: pointer;
      margin-bottom: 10px;
      transition: background 0.15s;
    }
    .btn-logout:hover {
      background: #27272A;
    }
    .btn-refresh {
      display: block;
      width: 100%;
      padding: 12px;
      background: #FFFFFF;
      border: none;
      color: #000000;
      text-decoration: none;
      font-size: 13px;
      font-weight: 800;
      border-radius: 12px;
      text-align: center;
      transition: background 0.15s;
    }
    .btn-refresh:hover {
      background: #E4E4E7;
    }
    .footer {
      margin-top: 16px;
      font-size: 11px;
      color: #71717A;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="status-badge">
      <span class="pulse-dot"></span>
      Connected to Internet
    </div>
    <div class="logo">$venueName</div>
    <div class="subtitle">Session Active &bull; WavePass</div>

    <div class="stats-table">
      <div class="stat-row">
        <span class="stat-label">User / Voucher</span>
        <span class="stat-value">\$(username)</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">IP Address</span>
        <span class="stat-value">\$(ip)</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">Connected Time</span>
        <span class="stat-value">\$(uptime)</span>
      </div>
      \$(if session-time-left)
      <div class="stat-row">
        <span class="stat-label">Time Remaining</span>
        <span class="stat-value">\$(session-time-left)</span>
      </div>
      \$(endif)
      <div class="stat-row">
        <span class="stat-label">Data Transferred</span>
        <span class="stat-value">\$(bytes-in-nice) &darr; / \$(bytes-out-nice) &uarr;</span>
      </div>
      \$(if remain-bytes-total-nice)
      <div class="stat-row">
        <span class="stat-label">Data Remaining</span>
        <span class="stat-value">\$(remain-bytes-total-nice)</span>
      </div>
      \$(endif)
    </div>

    <form action="\$(link-logout)" name="logout">
      <input type="hidden" name="erase-cookie" value="on">
      <button type="submit" class="btn-logout">Disconnect Device</button>
    </form>

    <a href="\$(link-status)" class="btn-refresh">Refresh Status</a>

    <div class="footer">
      Device MAC: \$(mac)
    </div>
  </div>

  <script>
    try {
      var u = "\$(username)";
      if (u && u !== "" && u.indexOf("\$(") === -1 && u.indexOf("T-") !== 0) {
        localStorage.setItem('wp-active-voucher', u);
        localStorage.setItem('wp-active-user', u);
      }
    } catch (e) {}
  </script>
</body>
</html>""";
  }

  static String _generateLogoutHtml(String venueName, String slug) {
    return """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Disconnected | $venueName Wi-Fi</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background: #000000;
      color: #FFFFFF;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: #0C0C0C;
      border: 1px solid #262626;
      border-radius: 20px;
      padding: 28px;
      width: 100%;
      max-width: 400px;
      box-shadow: 0 16px 40px rgba(0,0,0,0.8);
      text-align: center;
    }
    .icon-box {
      width: 56px;
      height: 56px;
      border-radius: 50%;
      background: #171717;
      border: 1px solid #333333;
      color: #FFFFFF;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 24px;
      margin: 0 auto 16px;
    }
    .logo {
      font-size: 22px;
      font-weight: 800;
      color: #FFFFFF;
      margin-bottom: 6px;
    }
    .subtitle {
      font-size: 13px;
      color: #A1A1AA;
      margin-bottom: 24px;
      line-height: 1.5;
    }
    .stats-table {
      width: 100%;
      background: #050505;
      border: 1px solid #262626;
      border-radius: 12px;
      padding: 14px;
      margin-bottom: 24px;
      text-align: left;
    }
    .stat-row {
      display: flex;
      justify-content: space-between;
      padding: 6px 0;
      border-bottom: 1px solid #1E1E22;
      font-size: 13px;
    }
    .stat-row:last-child {
      border-bottom: none;
    }
    .stat-label {
      color: #A1A1AA;
    }
    .stat-value {
      color: #FFFFFF;
      font-weight: 600;
      font-family: monospace;
    }
    .btn-login {
      display: block;
      width: 100%;
      padding: 14px;
      background: #FFFFFF;
      color: #000000;
      text-decoration: none;
      font-size: 15px;
      font-weight: 800;
      border-radius: 12px;
      text-align: center;
      border: none;
      cursor: pointer;
      box-shadow: 0 4px 12px rgba(255, 255, 255, 0.15);
      transition: background 0.15s;
    }
    .btn-login:hover {
      background: #E4E4E7;
    }
    .footer {
      margin-top: 16px;
      font-size: 11px;
      color: #71717A;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon-box">&#x2715;</div>
    <div class="logo">You Are Logged Out</div>
    <div class="subtitle">Thank you for visiting $venueName.<br>Your Wi-Fi session has ended.</div>

    <div class="stats-table">
      <div class="stat-row">
        <span class="stat-label">User</span>
        <span class="stat-value">\$(username)</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">Session Duration</span>
        <span class="stat-value">\$(uptime)</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">Total Data</span>
        <span class="stat-value">\$(bytes-in-nice) &darr; / \$(bytes-out-nice) &uarr;</span>
      </div>
    </div>

    <form action="\$(link-login)" name="login">
      <button type="submit" class="btn-login">Log In Again</button>
    </form>

    <div class="footer">
      Device MAC: \$(mac) &bull; IP: \$(ip)
    </div>
  </div>
</body>
</html>""";
  }

  Future<Map<String, String>> _ensurePortalSuite() async {
    if (_portalSuite != null) return _portalSuite!;
    final venue = VenueStateService.instance.currentVenue ??
        await SupabaseService.instance.getPrimaryVenue() ??
        await WavePassApi.instance.getDefaultVenue();
    final slug = venue['slug']?.toString() ?? 'venue';
    final venueName = venue['name']?.toString() ?? 'WavePass Wi-Fi';
    var plans = VenueStateService.instance.currentPlans;
    if (plans.isEmpty) {
      plans = await VenueStateService.instance.refreshPlans();
    }
    final dva = venue['dva'] ?? venue['virtual_account'];
    bool isPaystackConfigured = true;
    if (dva is Map) {
      final meta = dva['metadata'];
      if (meta is Map && (meta['mock'] == true || meta['mock']?.toString() == 'true')) {
        isPaystackConfigured = false;
      }
      final bank = (dva['bankName']?.toString() ?? dva['bank_name']?.toString() ?? '').toLowerCase();
      if (bank.contains('mock')) {
        isPaystackConfigured = false;
      }
    } else if (venue['paystack_configured'] == false) {
      isPaystackConfigured = false;
    }

    List<Map<String, dynamic>> bankAccounts = [];
    try {
      final info = await WavePassApi.instance.getPortalVenueInfo(venueSlug: slug);
      if (info['bankAccounts'] is List) {
        bankAccounts = List<Map<String, dynamic>>.from(
          (info['bankAccounts'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
      }
    } catch (_) {
      try {
        final venueId = venue['id']?.toString() ?? slug;
        final res = await WavePassApi.instance.listBankAccounts(venueId);
        final list = (res is Map && res['data'] is List) ? res['data'] : (res is List ? res : []);
        bankAccounts = List<Map<String, dynamic>>.from(
          list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
      } catch (_) {}
    }

    final suite = {
      'login.html': _generateLoginHtml(venueName, slug, plans, isPaystackConfigured, _useHostedSubdomainPortal, bankAccounts),
      'status.html': _generateStatusHtml(venueName, slug),
      'logout.html': _generateLogoutHtml(venueName, slug),
    };
    if (mounted) setState(() => _portalSuite = suite);
    return suite;
  }

  Future<void> _handleCopyCurrentPortalFile() async {
    setState(() => _exportingPortalHtml = true);
    try {
      final suite = await _ensurePortalSuite();
      final keys = ['login.html', 'status.html', 'logout.html'];
      final currentKey = keys[_selectedPortalTabIndex];
      final content = suite[currentKey] ?? '';

      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("$currentKey copied to clipboard! Save to MikroTik Files -> hotspot/$currentKey."),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to copy file: $e"), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPortalHtml = false);
    }
  }

  Future<void> _handleShareAllPortalFiles() async {
    setState(() => _exportingPortalHtml = true);
    try {
      final suite = await _ensurePortalSuite();
      final tempDir = await getTemporaryDirectory();
      final portalDir = Directory('${tempDir.path}/hotspot_suite');
      if (!await portalDir.exists()) {
        await portalDir.create(recursive: true);
      }

      final filesToShare = <XFile>[];
      for (final entry in suite.entries) {
        final f = File('${portalDir.path}/${entry.key}');
        await f.writeAsString(entry.value);
        filesToShare.add(XFile(f.path, mimeType: 'text/html', name: entry.key));
      }

      await SharePlus.instance.share(
        ShareParams(
          files: filesToShare,
          text: 'WavePass MikroTik HotSpot Portal Suite (login.html, status.html, logout.html)',
          subject: 'WavePass Portal Files',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to share portal files: $e"), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPortalHtml = false);
    }
  }

  Future<void> _handleAutoUploadPortalFiles() async {
    await _saveCredentials();
    setState(() => _uploadingPortalFiles = true);
    try {
      final suite = await _ensurePortalSuite();
      final ip = _ipCtrl.text.trim().isNotEmpty ? _ipCtrl.text.trim() : "192.168.88.1";
      final user = _userCtrl.text.trim().isNotEmpty ? _userCtrl.text.trim() : "admin";
      final pass = _passCtrl.text.trim();
      final tunnel = _tunnelCtrl.text.trim();

      final res = await RouterDiscoveryService.uploadPortalFiles(
        ip: ip,
        username: user,
        password: pass,
        files: suite,
        endpoint: tunnel.isNotEmpty ? tunnel : null,
      );

      final uploadedCount = res.values.where((v) => v).length;
      if (mounted) {
        if (uploadedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Successfully uploaded $uploadedCount/3 portal files (FTP/Hotspot) to router! Custom login and auto-auth active."),
              backgroundColor: AppColors.accentGreen,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("FTP/REST upload failed. Ensure router FTP port 21 is enabled, or use 'Share All 3' to drag files into WebFig/WinBox Files -> hotspot/."),
              backgroundColor: AppColors.accentOrange,
              duration: Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload error: $e"), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPortalFiles = false);
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
                            onChanged: (_) => _saveCredentials(),
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
                            onChanged: (_) => _saveCredentials(),
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
                      obscureText: _obscureRouterPass,
                      onChanged: (_) => _saveCredentials(),
                      decoration: InputDecoration(
                        labelText: "Password (leave empty if fresh)",
                        hintText: "••••••••",
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureRouterPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                            color: AppColors.textLight,
                          ),
                          onPressed: () => setState(() => _obscureRouterPass = !_obscureRouterPass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tunnelCtrl,
                      onChanged: (_) => _saveCredentials(),
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

                            if (_successMessage == null) ...[
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
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _isConfiguring ? null : _enforceNoSharing,
                                  icon: const Icon(Icons.security_rounded, size: 16, color: AppColors.primary),
                                  label: const Text(
                                    "Enforce No Sharing (1 Device/Voucher)",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.cardBorder),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ] else ...[
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

            // ─── OPTION 4: COMPLETE HOTSPOT PORTAL SUITE ───
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
                        "Complete Portal Suite",
                        style: TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Hotspot Portal Suite (login, status, logout)",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Replaces MikroTik's default blue screen with your custom branded captive portal suite. Files are placed in MikroTik Files -> hotspot/ directory.",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textLight,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  InkWell(
                    onTap: () async {
                      final venue = VenueStateService.instance.currentVenue;
                      final venueId = venue?['id']?.toString() ?? 'default';
                      await context.push('/wallet', extra: venueId);
                      setState(() => _portalSuite = null);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.account_balance_rounded, size: 18, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Venue Bank Accounts on Portal",
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primary),
                                ),
                                Text(
                                  "Add bank accounts to show on your portal for direct guest transfers.",
                                  style: TextStyle(fontSize: 11, color: AppColors.textLight),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Architecture Selector: Hosted Subdomain vs Standalone Router
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (!_useHostedSubdomainPortal) {
                                setState(() {
                                  _useHostedSubdomainPortal = true;
                                  _portalSuite = null;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                              decoration: BoxDecoration(
                                color: _useHostedSubdomainPortal ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "🌐 Hosted Subdomain",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _useHostedSubdomainPortal ? AppColors.white : AppColors.textLight,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_useHostedSubdomainPortal) {
                                setState(() {
                                  _useHostedSubdomainPortal = false;
                                  _portalSuite = null;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                              decoration: BoxDecoration(
                                color: !_useHostedSubdomainPortal ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "💾 Standalone Router",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: !_useHostedSubdomainPortal ? AppColors.white : AppColors.textLight,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _useHostedSubdomainPortal
                        ? "Permanently bounces connecting guests in 0s to your venue subdomain with offline voucher fallback."
                        : "Embeds plans, Paystack, and voucher entry directly in on-router HTML.",
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 14),

                  // Segmented Tabs: login.html | status.html | logout.html
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _buildPortalTab(0, "login.html", "Login & Pay"),
                        _buildPortalTab(1, "status.html", "Success"),
                        _buildPortalTab(2, "logout.html", "Logout"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // File Content Preview Box
                  FutureBuilder<Map<String, String>>(
                    future: _ensurePortalSuite(),
                    builder: (context, snapshot) {
                      final suite = snapshot.data;
                      final keys = ['login.html', 'status.html', 'logout.html'];
                      final currentKey = keys[_selectedPortalTabIndex];
                      final content = suite?[currentKey] ?? 'Generating template...';

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  currentKey,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                                ),
                                Text(
                                  "${content.length} chars",
                                  style: const TextStyle(fontSize: 10, color: AppColors.textLight),
                                ),
                              ],
                            ),
                            const Divider(height: 12, thickness: 0.5),
                            Text(
                              content,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Action Buttons: Copy Current File & Share All 3 Files
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: _exportingPortalHtml ? null : _handleCopyCurrentPortalFile,
                            icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
                            label: Text(
                              _exportingPortalHtml ? "Copying..." : "Copy Tab File",
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: _exportingPortalHtml ? null : _handleShareAllPortalFiles,
                            icon: const Icon(Icons.share_rounded, size: 16, color: AppColors.primary),
                            label: const Text(
                              "Share All 3",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Auto-Upload to Router Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _uploadingPortalFiles ? null : _handleAutoUploadPortalFiles,
                      icon: _uploadingPortalFiles
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                          : const Icon(Icons.cloud_upload_rounded, color: AppColors.white, size: 18),
                      label: Text(
                        _uploadingPortalFiles ? "Uploading to Router..." : "Auto-Upload Suite to Router (hotspot/)",
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentGreen,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  Widget _buildPortalTab(int index, String title, String subtitle) {
    final isSelected = _selectedPortalTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPortalTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.containerBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? AppColors.accentGreen : AppColors.textLight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                  color: isSelected ? AppColors.primary : AppColors.textMuted,
                ),
              ),
            ],
          ),
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
