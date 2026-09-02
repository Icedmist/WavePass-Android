import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.primary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Terms of Use",
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
            _buildTermCard("01 / ACCEPTANCE", "By connecting to WavePass Wi-Fi or buying passes, you agree to these terms."),
            const SizedBox(height: 12),
            _buildTermCard("02 / ACCESS PASSES", "Time counts continuously once activated. Payments are processed securely via Paystack or venue cashiers."),
            const SizedBox(height: 12),
            _buildTermCard("03 / FAIR USE", "You agree not to use venue Wi-Fi for unlawful hacking, spamming, or attacking other devices."),
            const SizedBox(height: 12),
            _buildTermCard("04 / SERVICE", "Internet speed depends on venue upstream ISP fiber connection and electrical power."),
            const SizedBox(height: 12),
            _buildTermCard("05 / OWNERSHIP", "WavePass is built and owned by Nexa Digital - Nexus Point (techwithnexa.com)."),
          ],
        ),
      ),
    );
  }

  Widget _buildTermCard(String tag, String body) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.containerBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tag,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
              color: AppColors.accentGreen,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(fontSize: 13, color: AppColors.primary, height: 1.4, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
