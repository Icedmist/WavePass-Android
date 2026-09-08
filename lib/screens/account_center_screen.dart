import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/router/app_router.dart';
import '../core/services/supabase_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/theme/app_theme.dart';

class AccountCenterScreen extends StatefulWidget {
  const AccountCenterScreen({super.key});

  @override
  State<AccountCenterScreen> createState() => _AccountCenterScreenState();
}

class _AccountCenterScreenState extends State<AccountCenterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  final _venueNameController = TextEditingController();
  final _venueSlugController = TextEditingController();

  // Real-time Subdomain / Slogan Availability
  Timer? _slugDebounce;
  bool _isCheckingSlug = false;
  bool? _isSlugAvailable;
  String? _slugStatusMessage;

  bool _loadingProfile = false;
  bool _savingProfile = false;
  bool _changingPassword = false;
  bool _savingVenue = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _slugDebounce?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _venueNameController.dispose();
    _venueSlugController.dispose();
    super.dispose();
  }

  void _onSlugChanged(String raw) {
    _slugDebounce?.cancel();
    final slug = raw.trim().toLowerCase();
    if (slug.isEmpty) {
      setState(() {
        _isCheckingSlug = false;
        _isSlugAvailable = null;
        _slugStatusMessage = null;
      });
      return;
    }
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      setState(() {
        _isCheckingSlug = false;
        _isSlugAvailable = false;
        _slugStatusMessage = 'Only lowercase letters, numbers, and hyphens allowed';
      });
      return;
    }
    setState(() {
      _isCheckingSlug = true;
      _slugStatusMessage = 'Checking availability...';
    });
    _slugDebounce = Timer(const Duration(milliseconds: 400), () async {
      final res = await VenueStateService.instance.checkSlugAvailability(slug);
      if (!mounted) return;
      setState(() {
        _isCheckingSlug = false;
        _isSlugAvailable = res['available'] == true;
        if (res['isCurrent'] == true) {
          _slugStatusMessage = 'Current venue subdomain';
        } else if (res['available'] == true) {
          _slugStatusMessage = 'Available: https://$slug.nexawavepass.com';
        } else {
          _slugStatusMessage = res['reason']?.toString() ?? 'Subdomain already taken';
        }
      });
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _loadingProfile = true);
    try {
      final user = SupabaseService.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('sb-user-email') ?? user?.email ?? 'talk2icedmist@gmail.com';
      _emailController.text = savedEmail;
      _nameController.text = user?.userMetadata?['name']?.toString() ?? 'Venue Owner';

      var venue = VenueStateService.instance.currentVenue;
      venue ??= await VenueStateService.instance.refreshVenue();

      if (mounted && venue != null) {
        _venueNameController.text = venue['name']?.toString() ?? 'WavePass Flagship';
        _venueSlugController.text = venue['slug']?.toString() ?? 'flagship';
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _handleUpdateProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showToast('Email address is required', isError: true);
      return;
    }

    setState(() => _savingProfile = true);
    try {
      await WavePassApi.instance.updateProfile(
        email: email,
        name: name,
        newEmail: email,
      );

      try {
        await SupabaseService.instance.client.auth.updateUser(
          UserAttributes(email: email, data: {'name': name}),
        );
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sb-user-email', email);

      if (mounted) {
        _showToast('Profile details updated successfully');
      }
    } catch (e) {
      if (mounted) _showToast('Failed to update profile: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _handleChangePassword() async {
    final current = _currentPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (current.isEmpty || newPass.isEmpty) {
      _showToast('Current and new passwords are required', isError: true);
      return;
    }
    if (newPass.length < 6) {
      _showToast('New password must be at least 6 characters', isError: true);
      return;
    }
    if (newPass != confirm) {
      _showToast('New passwords do not match', isError: true);
      return;
    }

    setState(() => _changingPassword = true);
    try {
      final email = _emailController.text.trim();
      final res = await WavePassApi.instance.changePassword(
        email: email,
        currentPassword: current,
        newPassword: newPass,
      );

      if (res['ok'] == false) {
        throw Exception(res['error'] ?? 'Incorrect current password');
      }

      try {
        await SupabaseService.instance.client.auth.updateUser(
          UserAttributes(password: newPass),
        );
      } catch (_) {}

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      if (mounted) {
        _showToast('Password changed successfully');
      }
    } catch (e) {
      if (mounted) _showToast('Failed to change password: $e', isError: true);
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _handleUpdateVenue() async {
    final name = _venueNameController.text.trim();
    final slug = _venueSlugController.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-');

    if (name.isEmpty || slug.isEmpty) {
      _showToast('Venue name and subdomain slug are required', isError: true);
      return;
    }

    if (_isSlugAvailable == false) {
      _showToast(_slugStatusMessage ?? 'Subdomain is not available. Please choose another.', isError: true);
      return;
    }

    setState(() => _savingVenue = true);
    try {
      await VenueStateService.instance.updateVenue(name: name, slug: slug);

      if (mounted) {
        _showToast('Venue details & subdomain updated');
      }
    } catch (e) {
      if (mounted) _showToast('Failed to update venue: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingVenue = false);
    }
  }

  Future<void> _handleDeleteAccount() async {
    final passwordCtrl = TextEditingController();
    bool obscureDelPass = true;
    String? deleteErr;
    bool deleting = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: AppColors.accentRed, size: 24),
              SizedBox(width: 8),
              Text('Delete Account', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.primary)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Are you sure? This will permanently delete your operator credentials and revoke venue access. This action cannot be undone.',
                  style: TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.4),
                ),
                const SizedBox(height: 16),
                const Text(
                  'CONFIRM YOUR PASSWORD',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: passwordCtrl,
                  obscureText: obscureDelPass,
                  decoration: InputDecoration(
                    hintText: '••••••••••••',
                    suffixIcon: IconButton(
                      icon: Icon(obscureDelPass ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: AppColors.textLight),
                      onPressed: () => setDialogState(() => obscureDelPass = !obscDelPass(obscureDelPass)),
                    ),
                  ),
                ),
                if (deleteErr != null) ...[
                  const SizedBox(height: 10),
                  Text(deleteErr!, style: const TextStyle(fontSize: 12, color: AppColors.accentRedDark, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              onPressed: deleting
                  ? null
                  : () async {
                      final p = passwordCtrl.text.trim();
                      if (p.isEmpty) {
                        setDialogState(() => deleteErr = 'Password is required to delete account.');
                        return;
                      }
                      setDialogState(() {
                        deleting = true;
                        deleteErr = null;
                      });
                      try {
                        final res = await WavePassApi.instance.deleteAccount(
                          email: _emailController.text.trim(),
                          password: p,
                        );
                        if (res['ok'] == false) {
                          throw Exception(res['error'] ?? 'Incorrect password');
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (err) {
                        setDialogState(() {
                          deleting = false;
                          deleteErr = err.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
              child: deleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _signOutUser();
      if (mounted) {
        _showToast('Account deleted successfully');
        context.go(AppRouter.login);
      }
    }
  }

  bool obscDelPass(bool val) => !val;

  Future<void> _signOutUser() async {
    try {
      await SupabaseService.instance.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sb-user-email');
    await prefs.remove('admin_token');
  }

  Future<void> _handleSignOut() async {
    await _signOutUser();
    if (mounted) {
      context.go(AppRouter.login);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.accentRed : AppColors.accentGreen,
        behavior: SnackBarBehavior.floating,
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
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.dashboard),
        ),
        title: const Text(
          'Account Center',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
        ),
        actions: [
          TextButton.icon(
            onPressed: _handleSignOut,
            icon: const Icon(Icons.logout_rounded, color: AppColors.accentRed, size: 16),
            label: const Text('Sign Out', style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ],
      ),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                // Header Banner
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(24)),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset('assets/images/logo.png', width: 44, height: 44, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _emailController.text.isNotEmpty ? _emailController.text : 'Venue Owner',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_venueNameController.text} • Role: Owner',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                              child: const Text('ONLINE • VERIFIED', style: TextStyle(color: AppColors.accentGreen, fontSize: 9, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION 1: PROFILE DETAILS
                _cardSection(
                  title: 'USER DETAILS',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _inputLabel('FULL NAME'),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(hintText: 'e.g. Jane Doe'),
                      ),
                      const SizedBox(height: 12),
                      _inputLabel('EMAIL ADDRESS'),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(hintText: 'admin@venue.com'),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _savingProfile ? null : _handleUpdateProfile,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          child: _savingProfile
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save Profile Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // SECTION 2: CHANGE PASSWORD WITH EYE TOGGLERS
                _cardSection(
                  title: 'SECURITY: CHANGE PASSWORD',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _inputLabel('CURRENT PASSWORD'),
                      TextField(
                        controller: _currentPasswordController,
                        obscureText: _obscureCurrent,
                        decoration: InputDecoration(
                          hintText: 'Enter current password',
                          suffixIcon: IconButton(
                            icon: Icon(_obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textLight, size: 18),
                            onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _inputLabel('NEW PASSWORD'),
                      TextField(
                        controller: _newPasswordController,
                        obscureText: _obscureNew,
                        decoration: InputDecoration(
                          hintText: 'Minimum 6 characters',
                          suffixIcon: IconButton(
                            icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textLight, size: 18),
                            onPressed: () => setState(() => _obscureNew = !_obscureNew),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _inputLabel('CONFIRM NEW PASSWORD'),
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          hintText: 'Re-enter new password',
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textLight, size: 18),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _changingPassword ? null : _handleChangePassword,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          child: _changingPassword
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Update Password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // SECTION 3: VENUE NAME & SUBDOMAIN SLUG
                _cardSection(
                  title: 'VENUE & SUBDOMAIN SETTINGS',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _inputLabel('VENUE DISPLAY NAME'),
                      TextField(
                        controller: _venueNameController,
                        decoration: const InputDecoration(hintText: 'e.g. Central City Café'),
                      ),
                      const SizedBox(height: 12),
                      _inputLabel('SUBDOMAIN SLUG / SLOGAN (STORES ON-NETWORK)'),
                      TextField(
                        controller: _venueSlugController,
                        onChanged: _onSlugChanged,
                        decoration: const InputDecoration(
                          hintText: 'e.g. central-cafe',
                          helperText: 'Store URL: {slug}.nexawavepass.com',
                        ),
                      ),
                      if (_isCheckingSlug || _slugStatusMessage != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: _isCheckingSlug
                                ? Colors.grey.withValues(alpha: 0.08)
                                : _isSlugAvailable == true
                                    ? AppColors.accentGreen.withValues(alpha: 0.08)
                                    : AppColors.accentRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isCheckingSlug
                                  ? Colors.grey.withValues(alpha: 0.25)
                                  : _isSlugAvailable == true
                                      ? AppColors.accentGreen.withValues(alpha: 0.35)
                                      : AppColors.accentRed.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (_isCheckingSlug)
                                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary))
                              else if (_isSlugAvailable == true)
                                const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.accentGreen)
                              else
                                const Icon(Icons.cancel_rounded, size: 14, color: AppColors.accentRed),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _slugStatusMessage ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _isCheckingSlug
                                        ? AppColors.textMuted
                                        : _isSlugAvailable == true
                                            ? AppColors.accentGreen
                                            : AppColors.accentRed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _savingVenue ? null : _handleUpdateVenue,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          child: _savingVenue
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save Venue Settings', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // SECTION 4: QUICK HUBS & LEGAL
                _section('VENUE HUBS', [
                  _row(context, 'Venue Wallet & Payouts', Icons.account_balance_wallet_rounded, () => context.push(AppRouter.wallet)),
                  _row(context, 'Notifications', Icons.notifications_rounded, () => context.push(AppRouter.notifications)),
                  _row(context, 'How to Use & Onboarding Guide', Icons.help_outline_rounded, () => context.push(AppRouter.howToUse)),
                ]),
                const SizedBox(height: 8),

                _section('LEGAL & POLICIES', [
                  _row(context, 'Terms of Use', Icons.gavel_rounded, () => context.push(AppRouter.terms)),
                  _row(context, 'Privacy Policy', Icons.privacy_tip_rounded, () => context.push(AppRouter.privacy)),
                ]),
                const SizedBox(height: 16),

                // SECTION 5: DANGER ZONE (DELETE ACCOUNT)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.redTint,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.delete_forever_rounded, color: AppColors.accentRed, size: 20),
                          SizedBox(width: 8),
                          Text('Danger Zone', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.accentRedDark)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Permanently delete your account. Requires entering your password to confirm.',
                        style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: _handleDeleteAccount,
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.accentRed, size: 18),
                          label: const Text('Delete Account', style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.w800, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.accentRed, width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // SECTION 6: SIGN OUT
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _handleSignOut,
                    icon: const Icon(Icons.logout_rounded, color: AppColors.accentRed, size: 18),
                    label: const Text('Sign Out of WavePass', style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.w800, fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.accentRed.withValues(alpha: 0.4), width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const Center(
                  child: Text(
                    'Built by Nexa Digital Nexus Point • techwithnexa.com',
                    style: TextStyle(fontSize: 11, color: AppColors.textLight),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _inputLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
        ),
      );

  Widget _cardSection({required String title, required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.containerBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textLight)),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  Widget _section(String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textLight)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.containerBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(children: rows),
          ),
        ],
      );

  Widget _row(BuildContext c, String label, IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textLight),
            ],
          ),
        ),
      );
}

