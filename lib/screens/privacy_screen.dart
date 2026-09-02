import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

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
          "Privacy Policy",
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
            _buildPrivacyCard("01 / DEVICE IDENTIFIERS", "We read your device MAC and IP address strictly to verify whether your phone has an active paid pass. We do not track your browsing history."),
            const SizedBox(height: 12),
            _buildPrivacyCard("02 / SECURE PAYMENTS", "Card and bank payments are processed directly by Paystack over encrypted TLS. We never store bank cards on our servers."),
            const SizedBox(height: 12),
            _buildPrivacyCard("03 / NO DATA SELLING", "We never sell or rent your personal information to third-party marketing companies."),
            const SizedBox(height: 12),
            _buildPrivacyCard("04 / SECURITY", "All communication between routers and the cloud uses encrypted HTTPS with signature verification."),
            const SizedBox(height: 12),
            _buildPrivacyCard("05 / SUPPORT CONTACT", "Questions? Contact Nexa Digital Nexus Point at talk2icedmist@gmail.com or techwithnexa.com."),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyCard(String tag, String body) {
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
              color: AppColors.accentRed,
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
