import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = [
    ('01 / WHAT WE COLLECT', 'Only what we need: device MAC/IP to bind your pass, Paystack-provided email for receipt (optional), and venue transaction metadata (plan, price, duration, voucher hash). We do not read browsing history, files, or app data. Card/bank numbers never touch our servers.'),
    ('02 / WHY WE USE IT', 'MAC/IP verifies you have an active pass (passwordless HotSpot). Email triggers Paystack receipts. Venue aggregates (revenue, ARPU, active sessions) are computed server-side from Payment/Order — not from personal profiles.'),
    ('03 / RETENTION', 'Sessions and audit logs roll after expiry. Fulfilled payments and voucher hashes are retained 90 days for reconciliation, then anonymized. Unredeemed vouchers expire in 7 days. You can request deletion via the venue or talk2icedmist@gmail.com.'),
    ('04 / SHARING', 'No sale or rental to advertisers. We share only with processors needed to operate: Paystack (payments, under their policy), Supabase Postgres (encrypted at rest), and the venue\'s MikroTik router (local HotSpot user, no cloud browsing logs).'),
    ('05 / SECURITY', 'All hops are HTTPS/TLS 1.2+ with HMAC-SHA512 webhook verification, server-locked pricing, atomic idempotent fulfilment, and voucher SHA-256 hashing. Router API uses least-privilege credentials and Walled Garden for Paystack/Supabase only.'),
    ('06 / COOKIES & TRACKING', 'Web portal uses only essential cookies for auth and MAC prefill (?mac=). No third-party ad trackers. Mobile app uses SharedPreferences for onboarding flag and Supabase session only.'),
    ('07 / YOUR RIGHTS', 'Access, correction, export, or deletion: email talk2icedmist@gmail.com with your venue and MAC. We respond within 30 days, subject to legal retention (e.g., payment audit).'),
    ('08 / CHILDREN', 'Not directed to children under 13. Venues must obtain guardian consent where required by local law before issuing passes to minors.'),
    ('09 / INTERNATIONAL', 'Data is hosted in EU-Central (Supabase) and processed in Nigeria (venues). Paystack transfers are NGN-only. By using WavePass, you consent to this processing.'),
    ('10 / CONTACT', 'Controller: Nexa Digital Nexus Point (techwithnexa.com) • DPO: talk2icedmist@gmail.com • Supabase project vvoenmdzavyzlisykhks. Updates posted here 30 days before effective date.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(backgroundColor: AppColors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18), onPressed: () => Navigator.of(context).pop()), title: const Text('Privacy Policy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PRIVACY AND TRUST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.accentRed)),
          const SizedBox(height: 6),
          const Text('What we collect, why, and your rights — plain language.', style: TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.4)),
          const SizedBox(height: 4),
          const Text('Last updated: Sep 3, 2026', style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textLight)),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.redTint, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CONTENTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textLight)),
            const SizedBox(height: 8),
            for (final s in _sections) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${s.$1}', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500))),
          ])),
          const SizedBox(height: 20),
          for (int i = 0; i < _sections.length; i++) ...[
            Text(_sections[i].$1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'monospace', letterSpacing: 0.8, color: AppColors.accentRed)),
            const SizedBox(height: 6),
            Text(_sections[i].$2, style: const TextStyle(fontSize: 13.5, color: Color(0xFF1A1A1A), height: 1.7)),
            if (i != _sections.length - 1) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0x0A000000))),
          ],
        ]),
      ),
    );
  }
}
