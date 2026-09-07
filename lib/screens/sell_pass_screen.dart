import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/plan_configurator.dart';

class SellPassScreen extends StatefulWidget {
  const SellPassScreen({super.key});

  @override
  State<SellPassScreen> createState() => _SellPassScreenState();
}

class _SellPassScreenState extends State<SellPassScreen> {
  int _selectedPlanIndex = 0;
  bool _isGenerating = false;
  String? _generatedCode;
  bool _isPrinting = false;

  final List<Map<String, dynamic>> _plans = [
    {'title': '1 Hour Quick Pass', 'price': '₦200', 'duration': '1 Hour', 'subtitle': 'Great for coffee & quick meetings', 'data': 'Unlimited', 'speed': '10 Mbps', 'devices': '1 device'},
    {'title': '12 Hour Work Pass', 'price': '₦800', 'duration': '12 Hours', 'subtitle': 'Full workday internet access', 'data': '10 GB cap', 'speed': '20 Mbps', 'devices': '1 device'},
    {'title': '24 Hour All-Day', 'price': '₦1,500', 'duration': '24 Hours', 'subtitle': 'Uninterrupted overnight access', 'data': 'Unlimited', 'speed': '20 Mbps', 'devices': '2 devices'},
  ];

  String _randomCode() {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final random = Random();
    final part1 = String.fromCharCodes(Iterable.generate(4, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
    final part2 = String.fromCharCodes(Iterable.generate(4, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
    return "WP-$part1-$part2";
  }

  Widget _miniChip(String text, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: AppColors.textLight), const SizedBox(width: 4), Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary))]),
      );

  void _handleGenerate() async {
    setState(() {
      _isGenerating = true;
    });

    await Future.delayed(const Duration(milliseconds: 600));

    setState(() {
      _isGenerating = false;
      _generatedCode = _randomCode();
    });
  }

  void _handlePrint() async {
    setState(() {
      _isPrinting = true;
    });

    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() {
      _isPrinting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Receipt printed successfully on Bluetooth printer."),
        backgroundColor: AppColors.accentGreen,
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text("Sell a Cash Pass", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        actions: [
          IconButton(icon: const Icon(Icons.tune_rounded, color: AppColors.primary), tooltip: 'Customize plan', onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const PlanConfiguratorSheet())),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_generatedCode == null) ...[
              const Text(
                "Select a plan for the customer paying with cash:",
                style: TextStyle(fontSize: 13, color: AppColors.textLight),
              ),
              const SizedBox(height: 16),

              // Plan Cards List
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _plans.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final plan = _plans[index];
                  final isSelected = _selectedPlanIndex == index;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPlanIndex = index;
                      });
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.containerBg : AppColors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.cardBorder,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? AppColors.primary : AppColors.textLight,
                                width: 2,
                              ),
                              color: isSelected ? AppColors.primary : Colors.transparent,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 14, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  plan['title'],
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(plan['subtitle'], style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                                const SizedBox(height: 8),
                                Wrap(spacing: 6, runSpacing: 6, children: [
                                  _miniChip(plan['duration'], Icons.schedule_rounded),
                                  _miniChip(plan['data'], Icons.storage_rounded),
                                  _miniChip(plan['speed'], Icons.speed_rounded),
                                  _miniChip(plan['devices'], Icons.devices_rounded),
                                ]),
                              ],
                            ),
                          ),
                          Column(children: [
                            FittedBox(fit: BoxFit.scaleDown, child: Text(plan['price'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary))),
                            IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary), onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => PlanConfiguratorSheet(existing: {'name': plan['title'], 'priceMinor': int.tryParse(plan['price'].toString().replaceAll(RegExp(r'[^0-9]'), '')) != null ? int.parse(plan['price'].toString().replaceAll(RegExp(r'[^0-9]'), '')) * 100 : 20000, 'durationSeconds': plan['duration'] == '1 Hour' ? 3600 : plan['duration'] == '12 Hours' ? 43200 : 86400, 'dataLimitBytes': plan['data'] == 'Unlimited' ? null : (double.tryParse(plan['data'].toString().split(' ').first) ?? 0) * 1024 * 1024 * 1024, 'rateLimit': plan['speed'], 'simultaneousDevices': int.tryParse(plan['devices'].toString().split(' ').first) ?? 1})), tooltip: 'Edit plan'),
                          ]),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isGenerating ? null : _handleGenerate,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
                  child: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text("Generate Pass Code"),
                ),
              ),
            ] else ...[
              // ─── RECEIPT VOUCHER CARD ───
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.containerBg,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.wifi, color: AppColors.primary, size: 36),
                    const SizedBox(height: 12),
                    const Text(
                      "WavePass Wi-Fi Access",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_plans[_selectedPlanIndex]['title'], style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
                    const SizedBox(height: 8),
                    Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                      _miniChip(_plans[_selectedPlanIndex]['duration'], Icons.schedule_rounded),
                      _miniChip(_plans[_selectedPlanIndex]['data'], Icons.storage_rounded),
                      _miniChip(_plans[_selectedPlanIndex]['speed'], Icons.speed_rounded),
                    ]),
                    const SizedBox(height: 16),
                    // Data exhaustion ring — shows cap for staff at a glance
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.cardBorder)),
                      child: Row(children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Stack(alignment: Alignment.center, children: [
                            CircularProgressIndicator(value: _plans[_selectedPlanIndex]['data'] == 'Unlimited' ? 1 : 0, strokeWidth: 3, backgroundColor: AppColors.containerBg, valueColor: AlwaysStoppedAnimation<Color>(_plans[_selectedPlanIndex]['data'] == 'Unlimited' ? AppColors.accentGreen : AppColors.primary)),
                            Icon(_plans[_selectedPlanIndex]['data'] == 'Unlimited' ? Icons.all_inclusive_rounded : Icons.storage_rounded, size: 14, color: AppColors.primary),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_plans[_selectedPlanIndex]['data'] == 'Unlimited' ? 'Unlimited data' : '${_plans[_selectedPlanIndex]['data']} • 0% used', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                          const Text('Fresh voucher — 100% available', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                        ])),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.accentGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentGreen, letterSpacing: 0.5))),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // Big 8-letter code container
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "CUSTOMER VOUCHER CODE",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textLight,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _generatedCode!,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              color: AppColors.accentRed,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      "Customer connects to venue Wi-Fi and enters this code on their phone screen to unlock internet.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action 1: Print Thermal Receipt
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isPrinting ? null : _handlePrint,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  icon: const Icon(Icons.print, size: 20),
                  label: _isPrinting
                      ? const Text("Printing receipt...")
                      : const Text("Print Bluetooth Receipt"),
                ),
              ),
              const SizedBox(height: 12),

              // Action 2: Sell Another Pass
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _generatedCode = null;
                    });
                  },
                  child: const Text("Sell Another Pass"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
