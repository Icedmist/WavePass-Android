import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/services/supabase_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SState();
}

class _SState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _err;

  Future<void> _signup() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _err = 'Fill all required fields.');
      return;
    }
    if (_pass.text != _confirm.text) {
      setState(() => _err = 'Passwords do not match.');
      return;
    }
    setState(() { _loading = true; _err = null; });
    final email = _email.text.trim();
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _err = 'Enter a valid email address.');
      return;
    }
    if (_pass.text.length < 6) {
      setState(() => _err = 'Password must be at least 6 characters.');
      return;
    }
    try {
      final res = await SupabaseService.instance.client.auth.signUp(email: email, password: _pass.text, data: {'name': _name.text.trim(), 'phone': _phone.text.trim()});
      if (res.user != null) {
        // Handle email confirmation required: session may be null until user confirms
        if (res.session == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check your email to confirm your account, then sign in.')));
        }
        if (!mounted) return;
        context.go(AppRouter.onboarding);
      } else {
        setState(() => _err = res.session == null ? 'Check email to confirm, then sign in.' : 'Sign up failed. Try again.');
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('already registered') || msg.contains('already exists')) {
        setState(() => _err = 'Account already exists — try Sign In.');
      } else if (msg.contains('network') || msg.contains('Failed host')) {
        setState(() => _err = 'Network error — check internet and try again.');
      } else {
        setState(() => _err = 'Sign up failed: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _name.dispose(); _email.dispose(); _phone.dispose(); _pass.dispose(); _confirm.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(backgroundColor: AppColors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18), onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.login)), title: const Text('Create Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary))),
      body: SafeArea(
        child: LayoutBuilder(builder: (c, cons) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: cons.maxHeight - 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/images/logo.png', width: 44, height: 44, fit: BoxFit.cover)),
                  const SizedBox(width: 12),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('WavePass', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primary)),
                    Text('Venue Manager App', style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                  ])
                ]),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(28), border: Border.all(color: AppColors.cardBorder)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Join WavePass', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary)),
                    const SizedBox(height: 6),
                    const Text('Onboarding shows on first launch and after sign up.', style: TextStyle(fontSize: 13, color: AppColors.textLight)),
                    const SizedBox(height: 16),
                    _field('FULL NAME', _name, 'John Doe'),
                    _field('EMAIL ADDRESS', _email, 'admin@venue.com', type: TextInputType.emailAddress),
                    _field('PHONE (OPTIONAL)', _phone, '+234...', type: TextInputType.phone),
                    _field('PASSWORD', _pass, '••••••••', obscure: true),
                    _field('CONFIRM PASSWORD', _confirm, '••••••••', obscure: true),
                    if (_err != null) ...[
                      const SizedBox(height: 12),
                      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.redTint, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.3))), child: Text(_err!, style: const TextStyle(fontSize: 12, color: AppColors.accentRedDark, fontWeight: FontWeight.w600))),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(height: 52, child: ElevatedButton(onPressed: _loading ? null : _signup, child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)))),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('Already have account? ', style: TextStyle(fontSize: 13, color: AppColors.textLight)),
                      GestureDetector(onTap: () => context.go(AppRouter.login), child: const Text('Sign In', style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w800))),
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint, {TextInputType? type, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        TextField(controller: c, keyboardType: type, obscureText: obscure, decoration: InputDecoration(hintText: hint)),
      ]),
    );
  }
}
