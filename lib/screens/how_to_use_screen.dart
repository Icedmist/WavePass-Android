import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class HowToUseScreen extends StatefulWidget {
  const HowToUseScreen({super.key});
  @override
  State<HowToUseScreen> createState() => _HState();
}

class _HState extends State<HowToUseScreen> {
  final _c = PageController();
  int _i = 0;
  final _steps = const [
    {'num': '01', 'title': 'Plug In Your Router', 'desc': 'Power the MikroTik and plug internet into Port 1 (WAN). One cable, done.'},
    {'num': '02', 'title': 'Connect Phone to Wi-Fi', 'desc': 'Join the open SSID (MikroTik) — no password needed for setup.'},
    {'num': '03', 'title': 'Auto-Find in 5 Seconds', 'desc': 'In Router Setup tap “Find My Router” — detects 192.168.88.1 and installs HotSpot.'},
    {'num': '04', 'title': 'Or Scan Barcode', 'desc': 'Still boxed? Scan the serial — router self-configures on boot via cloud.'},
    {'num': '05', 'title': 'Sell & Customize', 'desc': 'Pick duration (30m–72h) or per-GB cap, set NGN price, Mbps and devices. Guests pay or get WP-XXXX-XXXX.'},
  ];
  final _icons = [Icons.power_rounded, Icons.phone_iphone_rounded, Icons.radar_rounded, Icons.qr_code_scanner_rounded, Icons.tune_rounded];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(backgroundColor: AppColors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18), onPressed: () => Navigator.of(context).pop()), title: const Text('How to Use WavePass', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary))),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _c,
            onPageChanged: (v) => setState(() => _i = v),
            itemCount: _steps.length,
            itemBuilder: (c, idx) {
              final s = _steps[idx];
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.cardBorder)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.cardBorder)), child: Icon(_icons[idx], size: 28, color: AppColors.primary)),
                    const SizedBox(height: 24),
                    Text('${s['num']} / STEP', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'monospace', color: AppColors.accentGreen, letterSpacing: 0.8)),
                    const SizedBox(height: 10),
                    Text((s['title'] as String), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: -0.5)),
                    const SizedBox(height: 12),
                    Text((s['desc'] as String), style: const TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.5)),
                    const SizedBox(height: 20),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.cardBorder)), child: Text('Card ${idx + 1} of ${_steps.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary))),
                  ]),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: List.generate(_steps.length, (j) => AnimatedContainer(duration: const Duration(milliseconds: 260), margin: const EdgeInsets.only(right: 6), width: _i == j ? 20 : 6, height: 6, decoration: BoxDecoration(color: _i == j ? AppColors.primary : Colors.black12, borderRadius: BorderRadius.circular(4))))),
            SizedBox(height: 48, child: ElevatedButton(onPressed: () => _i == _steps.length - 1 ? Navigator.of(context).pop() : _c.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 24)), child: Text(_i == _steps.length - 1 ? 'Done' : 'Next →', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)))),
          ]),
        )
      ]),
    );
  }
}
