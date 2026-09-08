import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _sections = [
    ('01 / ACCEPTANCE', 'By creating an account, connecting to any WavePass-enabled Wi-Fi, or purchasing a pass (online or cash), you agree to these Terms and our Privacy Policy. If you disagree, do not use the service.'),
    ('02 / PLANS & OWNERSHIP', 'All pass prices, durations and data caps are configured by the venue and displayed before payment. WavePass is built and owned by Nexa Digital Nexus Point (techwithnexa.com) — venues operate as authorized resellers, not owners of the platform.'),
    ('03 / PAYMENTS & REFUNDS', 'Online payments settle via the venue\'s Dedicated Virtual Account under the single Nexa Paystack key and are instantly verified. Cash passes are non-refundable once the code is generated or redeemed. Metered time starts on first login and runs continuously (elapsed). For failed activations, contact the venue within 30 minutes for a reissue.'),
    ('04 / FAIR USE & LIMITS', 'Do not abuse the network: no hacking, spamming, torrenting that degrades shared bandwidth, or reselling access beyond your pass. Each plan lists simultaneous devices (default 1) and optional GB cap or Mbps throttle — exceeding the cap pauses access until renewal. Venues may auto-block abusive MACs.'),
    ('05 / UPTIME & SLA', 'Service runs on venue ISP fiber + power. We target 99.9% portal availability and self-heal router sessions via reconciliation, but do not guarantee ISP speed, power, or force-majeure uptime. Upstream failures do not entitle refunds beyond venue discretion.'),
    ('06 / VOUCHERS & EXPIRY', '8-char codes (WP-XXXX-XXXX) are single-use, bound on redemption to the first device MAC/IP. Unredeemed vouchers expire per plan policy (default 7 days). Expired/REVOKED/CONSUMED codes are rejected on the RouterOS HotSpot — keep your receipt.'),
    ('07 / SUSPENSION', 'We may suspend or terminate accounts or sessions for Terms violation, fraud, or abuse, with notice where feasible. Venue owners may also locally disconnect devices from the Active Devices screen.'),
    ('08 / LIABILITY', 'To the extent permitted by law, WavePass/Nexa liability is limited to the amount you paid for the active pass. We are not liable for indirect loss, loss of data, or third-party content accessed over the Wi-Fi.'),
    ('09 / CHANGES', 'We may update these Terms with 30 days notice in-app and on /terms. Continued use after the effective date constitutes acceptance. Material pricing changes do not affect already-paid passes.'),
    ('10 / CONTACT', 'Questions: support@nexawavepass.com • https://techwithnexa.com • In-app: Admin → Help. Governing law: Federal Republic of Nigeria.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(backgroundColor: AppColors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18), onPressed: () => Navigator.of(context).pop()), title: const Text('Terms of Use', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('LEGAL TERMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.accentGreen)),
          const SizedBox(height: 6),
          const Text('Simple terms for venues and guests.', style: TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.4)),
          const SizedBox(height: 4),
          const Text('Last updated: Sep 3, 2026 • Effective for all venues', style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textLight)),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CONTENTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textLight)),
            const SizedBox(height: 8),
            for (final s in _sections) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${s.$1} — ${s.$1.split('/').last.trim()}', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500))),
          ])),
          const SizedBox(height: 20),
          for (int i = 0; i < _sections.length; i++) ...[
            Text(_sections[i].$1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'monospace', letterSpacing: 0.8, color: AppColors.accentGreen)),
            const SizedBox(height: 6),
            Text(_sections[i].$2, style: const TextStyle(fontSize: 13.5, color: Color(0xFF1A1A1A), height: 1.7, fontWeight: FontWeight.w400)),
            if (i != _sections.length - 1) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0x0A000000))),
          ],
        ]),
      ),
    );
  }
}
