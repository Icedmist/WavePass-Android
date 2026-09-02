import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  final List<Map<String, String>> _steps = const [
    {
      'num': '01',
      'title': 'Plug In Your Router',
      'desc': 'Connect your MikroTik router to power and plug your internet cable into Port 1 (WAN).',
    },
    {
      'num': '02',
      'title': 'Connect Phone to Router Wi-Fi',
      'desc': 'On your smartphone, connect to the default open Wi-Fi network (such as MikroTik).',
    },
    {
      'num': '03',
      'title': 'Auto-Find on Wi-Fi (Approach 1)',
      'desc': 'In the WavePass app, open Router Setup and tap "Find My Router". The app detects 192.168.88.1 and installs HotSpot in 5 seconds.',
    },
    {
      'num': '04',
      'title': 'Or Scan Box Barcode (Approach 2)',
      'desc': 'If the router is still in the packaging, tap "Scan Box Barcode" to read the serial. The router will configure itself upon boot.',
    },
    {
      'num': '05',
      'title': 'Sell Passes or Let Guests Pay',
      'desc': 'Guests scan table QR codes to pay with card or transfer, or cashiers issue 8-letter vouchers with Bluetooth receipts.',
    },
  ];

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
          "How to Use WavePass",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: _steps.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final step = _steps[index];

          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.containerBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step['num']!,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    color: AppColors.accentRed,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step['title']!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step['desc']!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textLight,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
