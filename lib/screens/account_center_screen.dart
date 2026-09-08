import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountCenterScreen extends StatelessWidget {
  const AccountCenterScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.instance.currentUser;
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(backgroundColor: AppColors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18), onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.dashboard)), title: const Text('Account Center', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), children: [
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(24)), child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/images/logo.png', width: 44, height: 44, fit: BoxFit.cover)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user?.email ?? 'Venue Owner', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            const Text('Venue Owner • WavePass Flagship', style: TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: const Text('ONLINE', style: TextStyle(color: AppColors.accentGreen, fontSize: 10, fontWeight: FontWeight.w800, fontFamily: 'monospace'))),
          ])),
        ])),
        const SizedBox(height: 16),
        _section('VENUE', [
          _row(context, 'Venue Wallet', Icons.account_balance_wallet_rounded, () => context.push(AppRouter.wallet)),
          _row(context, 'Notifications', Icons.notifications_rounded, () => context.push(AppRouter.notifications)),
          _row(context, 'How to Use', Icons.help_outline_rounded, () => context.push(AppRouter.howToUse)),
        ]),
        _section('LEGAL', [
          _row(context, 'Terms of Use', Icons.gavel_rounded, () => context.push(AppRouter.terms)),
          _row(context, 'Privacy Policy', Icons.privacy_tip_rounded, () => context.push(AppRouter.privacy)),
        ]),
        _section('SESSION', [
          _row(context, 'Sign Out', Icons.logout_rounded, () async {
            await SupabaseService.instance.signOut();
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('sb-user-email');
            await prefs.remove('admin_token');
            if (context.mounted) context.go(AppRouter.login);
          }, danger: true),
        ]),
        const SizedBox(height: 12),
        const Center(child: Text('Built by Nexa Digital Nexus Point • techwithnexa.com', style: TextStyle(fontSize: 11, color: AppColors.textLight))),
      ]),
    );
  }

  Widget _section(String title, List<Widget> rows) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 8), child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textLight))),
        Container(decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.cardBorder)), child: Column(children: rows)),
      ]);

  Widget _row(BuildContext c, String label, IconData icon, VoidCallback onTap, {bool danger = false}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: danger ? AppColors.redTint : AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.cardBorder)), child: Icon(icon, size: 18, color: danger ? AppColors.accentRed : AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: danger ? AppColors.accentRed : AppColors.primary))),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textLight),
          ]),
        ),
      );
}
