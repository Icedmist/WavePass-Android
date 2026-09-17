import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/router/app_router.dart';
import '../core/services/activation_code_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/router_discovery_service.dart';
import '../core/services/supabase_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/theme/app_theme.dart';

class VenueActivationScreen extends StatefulWidget {
  const VenueActivationScreen({super.key});

  @override
  State<VenueActivationScreen> createState() => _VenueActivationScreenState();
}

class _VenueActivationScreenState extends State<VenueActivationScreen> {
  final _codeCtrl = TextEditingController();
  final _reqNameCtrl = TextEditingController();
  final _reqEmailCtrl = TextEditingController();
  final _reqPhoneCtrl = TextEditingController();
  final _reqVenueCtrl = TextEditingController();
  final _reqMsgCtrl = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _expiryNotice;
  bool _isRequesting = false;
  String? _requestMessage;
  bool _requestSent = false;

  @override
  void initState() {
    super.initState();
    _forwardIfActivated();
    _prefillEmail();
  }

  Future<void> _prefillEmail() async {
    final email = await _currentEmail();
    if (email.isNotEmpty && mounted) {
      setState(() => _reqEmailCtrl.text = email);
    }
  }

  /// Already licensed (e.g. bounced here by the router guard on cold start
  /// before re-verification)? Skip ahead to the dashboard.
  Future<void> _forwardIfActivated() async {
    final lastExpired = await ActivationCodeService.instance.getLastExpired();
    final ok = await ActivationCodeService.instance.isAccountActivated();
    if (!mounted) return;
    if (ok) {
      context.go(AppRouter.dashboard);
      return;
    }
    if (lastExpired != null) {
      setState(() => _expiryNotice = 'Your previous activation expired on $lastExpired. Redeem a new monthly code to resume all activity.');
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _reqNameCtrl.dispose();
    _reqEmailCtrl.dispose();
    _reqPhoneCtrl.dispose();
    _reqVenueCtrl.dispose();
    _reqMsgCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleActivate() async {
    final rawCode = _codeCtrl.text.trim().toUpperCase();
    if (rawCode.isEmpty) {
      setState(() => _errorMessage = "Please enter your activation code.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ActivationCodeService.instance.redeemActivationCode(code: rawCode);

    if (!mounted) return;

    if (res['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? "Venue activated successfully!"),
          backgroundColor: AppColors.accentGreen,
          duration: const Duration(seconds: 3),
        ),
      );
      // Prompt user to enable device notifications for customer transfer approvals & sales
      await AppNotifier.promptEnableNotifications(context);
      if (!mounted) return;
      // Navigate to Router Setup or Dashboard
      context.go(AppRouter.routerSetup);
    } else {
      setState(() {
        _errorMessage = res['error']?.toString() ?? "Invalid or unauthorized activation code.";
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRequestCode() async {
    final inputEmail = _reqEmailCtrl.text.trim();
    final savedEmail = inputEmail.isNotEmpty ? inputEmail : await _currentEmail();
    if (savedEmail.isEmpty || !savedEmail.contains('@')) {
      setState(() {
        _requestSent = false;
        _requestMessage = "Please enter a valid email address.";
      });
      return;
    }
    setState(() {
      _isRequesting = true;
      _requestMessage = null;
    });
    try {
      final res = await ActivationCodeService.instance.requestActivationCode(
        email: savedEmail,
        name: _reqNameCtrl.text.trim(),
        phone: _reqPhoneCtrl.text.trim(),
        venueName: _reqVenueCtrl.text.trim(),
        message: _reqMsgCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _requestSent = res['ok'] == true;
        _requestMessage = res['ok'] == true
            ? res['message']?.toString() ?? 'Request sent.'
            : res['error']?.toString() ?? 'Failed to send request.';
      });
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  Future<String> _currentEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('sb-user-email');
      if (saved != null && saved.trim().isNotEmpty) return saved.trim();
      final supabaseEmail = SupabaseService.instance.currentUser?.email;
      if (supabaseEmail != null && supabaseEmail.trim().isNotEmpty) return supabaseEmail.trim();
    } catch (_) {}
    return '';
  }

  Future<void> _contactAdmin() async {
    await Clipboard.setData(const ClipboardData(text: 'talk2icedmist@gmail.com'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Admin email (talk2icedmist@gmail.com) copied to clipboard."),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Future<bool> _showLogoutConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Log Out"),
            content: const Text(
              "Are you sure you want to log out and switch accounts?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                key: const Key('venue_activation_confirm_logout_button'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text("Log Out", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _handleLogout({bool prompt = true}) async {
    if (prompt) {
      final confirmed = await _showLogoutConfirmDialog();
      if (!confirmed || !mounted) return;
    }

    try {
      await SupabaseService.instance.signOut();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sb-user-email');
      await prefs.remove('admin_token');
      await prefs.remove('wavepass_voucher_history_v1');
      await prefs.remove(RouterDiscoveryService.keyRouterLocalIp);
      await prefs.remove(RouterDiscoveryService.keyRouterTunnelEndpoint);
      await prefs.remove(RouterDiscoveryService.keyRouterUsername);
      await prefs.remove(RouterDiscoveryService.keyRouterPassword);
    } catch (_) {}

    try {
      await VenueStateService.instance.clearVenue();
    } catch (_) {}

    try {
      await ActivationCodeService.instance.clearCache();
    } catch (_) {}

    if (mounted) {
      context.go(AppRouter.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          await _handleLogout(prompt: true);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
            onPressed: () async {
              if (context.canPop()) {
                context.pop();
              } else {
                await _handleLogout(prompt: true);
              }
            },
          ),
          title: const Text(
            "Venue Activation",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          actions: [
            TextButton.icon(
              key: const Key('venue_activation_logout_button'),
              onPressed: () => _handleLogout(prompt: true),
              icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.accentRed),
              label: const Text(
                "Log Out",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentRed,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Lock / Shield Icon Badge
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3), width: 2),
                    ),
                    child: const Icon(Icons.vpn_key_rounded, size: 36, color: AppColors.accentGreen),
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  "Activation Code Required",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "All new WavePass accounts require an authorized activation code before configuring a venue. Each code is strictly limited to one venue.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textLight,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),

                if (_expiryNotice != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_off_rounded, color: Color(0xFFD97706), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _expiryNotice!,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Activation Card Form
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.containerBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "ENTER ACTIVATION CODE",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),

                      TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          letterSpacing: 2.0,
                          color: AppColors.primary,
                        ),
                        decoration: InputDecoration(
                          hintText: "WP-ACT-XXXX-XXXX",
                          hintStyle: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: AppColors.textLight.withValues(alpha: 0.5),
                            letterSpacing: 1.5,
                          ),
                          filled: true,
                          fillColor: AppColors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.cardBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.accentGreen, width: 2),
                          ),
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.accentRed.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.accentRed, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(fontSize: 12, color: AppColors.accentRed, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleActivate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  "Activate Venue",
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Request a code from the system admin
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Don't have an activation code?",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Send a request with your details — the system admin will grant you a code or direct access.",
                        style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reqNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(hintText: "Your name", isDense: true, border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _reqEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(hintText: "Email address *", isDense: true, border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _reqPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(hintText: "Phone number", isDense: true, border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _reqVenueCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(hintText: "Venue name", isDense: true, border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _reqMsgCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(hintText: "Message for the admin (optional)", isDense: true, border: OutlineInputBorder()),
                      ),
                      if (_requestMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _requestMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _requestSent ? AppColors.accentGreen : AppColors.accentRed,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: _requestSent
                            ? const Text(
                                "✓ Request received — you will be notified once the admin reviews it.",
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentGreen),
                              )
                            : OutlinedButton.icon(
                                onPressed: _isRequesting ? null : _handleRequestCode,
                                icon: _isRequesting
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.send_rounded, size: 16, color: AppColors.primary),
                                label: Text(
                                  _isRequesting ? "Sending..." : "Request Code from System Admin",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: _contactAdmin,
                          child: const Text(
                            "Copy admin email instead",
                            style: TextStyle(fontSize: 11, color: AppColors.textLight),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: TextButton.icon(
                    key: const Key('venue_activation_bottom_logout_button'),
                    onPressed: () => _handleLogout(prompt: true),
                    icon: const Icon(Icons.logout_rounded, size: 16, color: AppColors.textLight),
                    label: const Text(
                      "Wrong account? Log out and sign in differently",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textLight,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
