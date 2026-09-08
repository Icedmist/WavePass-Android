import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';
import '../core/services/supabase_service.dart';
import '../core/services/wavepass_api.dart';
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

  List<Map<String, dynamic>> _plans = [];
  bool _loadingPlans = true;
  String? _venueId;
  String? _venueName;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _loadingPlans = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      var vid = prefs.getString('venueId');
      var vname = prefs.getString('venueName');

      Map<String, dynamic>? venue;
      if (vid != null) {
        try {
          venue = await WavePassApi.instance.getVenueBySubdomain(vid);
        } catch (_) {}
      }
      try {
        venue ??= await WavePassApi.instance.getDefaultVenue();
      } catch (_) {}
      venue ??= await SupabaseService.instance.getPrimaryVenue();

      if (venue != null) {
        _venueId = venue['id']?.toString() ?? vid;
        _venueName = venue['name']?.toString() ?? vname ?? 'WavePass Venue';

        List<dynamic>? rawPlans = venue['plans'];
        if (rawPlans == null || rawPlans.isEmpty) {
          try {
            rawPlans = await SupabaseService.instance.getActivePlans(_venueId!);
          } catch (_) {}
        }
        if (rawPlans != null && rawPlans.isNotEmpty) {
          setState(() {
            _plans = rawPlans!.map((p) {
              final priceMinor = (p['priceMinor'] as num?)?.toInt() ?? 0;
              final durationSec = (p['durationSeconds'] as num?)?.toInt() ?? 3600;
              final durationStr = durationSec < 3600
                  ? '${durationSec ~/ 60} Mins'
                  : durationSec < 86400
                      ? '${durationSec ~/ 3600} Hours'
                      : '${durationSec ~/ 86400} Days';
              final dataLimit = p['dataLimitBytes'];
              final dataStr = dataLimit == null
                  ? 'Unlimited'
                  : '${((dataLimit as num) / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
              return {
                'id': p['id']?.toString() ?? '',
                'title': p['name']?.toString() ?? 'Pass',
                'price': '₦${priceMinor ~/ 100}',
                'priceMinor': priceMinor,
                'duration': durationStr,
                'durationSeconds': durationSec,
                'subtitle': p['description']?.toString() ?? 'Custom plan',
                'data': dataStr,
                'speed': p['rateLimit']?.toString() ?? '10 Mbps',
                'devices': '${p['simultaneousDevices'] ?? 1} device',
              };
            }).toList();
            if (_selectedPlanIndex >= _plans.length) {
              _selectedPlanIndex = 0;
            }
          });
          return;
        }
      }
      setState(() => _plans = []);
    } catch (e) {
      debugPrint('Error loading plans: $e');
      setState(() => _plans = []);
    } finally {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

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
    if (_plans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one pricing plan first.')),
      );
      return;
    }
    if (_selectedPlanIndex >= _plans.length) {
      _selectedPlanIndex = 0;
    }

    setState(() {
      _isGenerating = true;
    });

    final selectedPlan = _plans[_selectedPlanIndex];
    final planId = selectedPlan['id'] as String?;
    String? code;

    try {
      if (_venueId != null && planId != null && planId.isNotEmpty) {
        final res = await http.post(
          Uri.parse('${ApiConstants.cloudBaseUrl}/api/v1/vouchers/batches'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'venueId': _venueId,
            'planId': planId,
            'quantity': 1,
          }),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body);
          final list = (data is List ? data : data['codes'] ?? data) as List;
          if (list.isNotEmpty) {
            final first = list.first;
            code = first is String ? first : first['code']?.toString();
          }
        }
      }
    } catch (e) {
      debugPrint('Cloud voucher generation error: $e');
    }

    // Safe fallback if offline or backend network issue
    code ??= _randomCode();

    if (!mounted) return;
    setState(() {
      _isGenerating = false;
      _generatedCode = code;
    });

    // Auto-print receipt if enabled in printer settings
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('wavepass_auto_print_receipts') ?? true) {
        _handlePrint();
      }
    } catch (_) {}
  }

  void _handlePrint() async {
    if (_generatedCode == null || _plans.isEmpty) return;
    final selectedPlan = (_selectedPlanIndex < _plans.length) ? _plans[_selectedPlanIndex] : _plans.first;
    setState(() => _isPrinting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final width = prefs.getInt('wavepass_printer_paper_width') ?? 58;
      final format = width == 80 ? PdfPageFormat.roll80 : PdfPageFormat.roll57;

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(10),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text('WAVEPASS WI-FI', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(_venueName ?? 'Guest Access', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              pw.Text('PASSCODE:', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 2),
              pw.Text(_generatedCode!, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
              pw.SizedBox(height: 6),
              pw.Text('Plan: ${selectedPlan['title']}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('Duration: ${selectedPlan['duration']} • Data: ${selectedPlan['data']}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Price: ${selectedPlan['price']}', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              pw.Text('Connect to Wi-Fi and enter code on captive portal.', style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
              pw.Text(DateTime.now().toString().split('.')[0], style: const pw.TextStyle(fontSize: 7)),
            ],
          ),
        ),
      );

      final savedUrl = prefs.getString('wavepass_selected_printer_url');
      if (savedUrl != null) {
        final printers = await Printing.listPrinters();
        final matched = printers.where((p) => p.url == savedUrl).firstOrNull;
        if (matched != null) {
          final bytes = await doc.save();
          await Printing.directPrintPdf(printer: matched, onLayout: (_) async => bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Receipt printed to ${matched.name}"), backgroundColor: AppColors.accentGreen),
            );
          }
          return;
        }
      }

      await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Pass_$_generatedCode');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Receipt print job sent to printer spooler."),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Print error: $e"), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text("Sell a Cash Pass", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppColors.primary),
            tooltip: 'Customize plan',
            onPressed: () async {
              final ok = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PlanConfiguratorSheet(),
              );
              if (ok == true) _loadPlans();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset + 88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_generatedCode == null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      "Select a plan for customer paying cash:",
                      style: TextStyle(fontSize: 13, color: AppColors.textLight),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const PlanConfiguratorSheet(),
                      );
                      if (ok == true) _loadPlans();
                    },
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Plan', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loadingPlans)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_plans.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.containerBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 32, color: AppColors.textLight),
                      const SizedBox(height: 8),
                      const Text('No pricing plans found', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      const SizedBox(height: 4),
                      const Text('Add your first pass manually — duration or per-GB.', style: TextStyle(fontSize: 11, color: AppColors.textLight), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final ok = await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const PlanConfiguratorSheet(),
                          );
                          if (ok == true) _loadPlans();
                        },
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Create First Plan'),
                      ),
                    ],
                  ),
                )
              else
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
                        padding: const EdgeInsets.all(18),
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
                            const SizedBox(width: 14),
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
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    plan['price'],
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                                  onPressed: () => showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => PlanConfiguratorSheet(existing: {
                                      'id': plan['id'],
                                      'name': plan['title'],
                                      'priceMinor': plan['priceMinor'] ?? 20000,
                                      'durationSeconds': plan['durationSeconds'] ?? 3600,
                                      'dataLimitBytes': plan['data'] == 'Unlimited' ? null : 1024 * 1024 * 1024,
                                      'rateLimit': plan['speed'],
                                      'simultaneousDevices': 1,
                                    }),
                                  ),
                                  tooltip: 'Edit plan',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: (_isGenerating || _plans.isEmpty) ? null : _handleGenerate,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
                  child: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(_plans.isEmpty ? "Add a Plan to Sell" : "Generate Pass Code"),
                ),
              ),
            ] else ...[
              // ─── RECEIPT VOUCHER CARD ───
              Builder(
                builder: (context) {
                  final plan = (_plans.isNotEmpty && _selectedPlanIndex < _plans.length)
                      ? _plans[_selectedPlanIndex]
                      : {'title': 'Wi-Fi Pass', 'duration': '1 Hour', 'data': 'Unlimited', 'speed': '10 Mbps'};
                  final isUnlimited = plan['data'] == 'Unlimited';

                  return Container(
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
                        Text(plan['title'], style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
                        const SizedBox(height: 8),
                        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                          _miniChip(plan['duration'], Icons.schedule_rounded),
                          _miniChip(plan['data'], Icons.storage_rounded),
                          _miniChip(plan['speed'], Icons.speed_rounded),
                        ]),
                        const SizedBox(height: 16),
                        // Data exhaustion ring
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.cardBorder)),
                          child: Row(children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: Stack(alignment: Alignment.center, children: [
                                CircularProgressIndicator(
                                  value: isUnlimited ? 1 : 0,
                                  strokeWidth: 3,
                                  backgroundColor: AppColors.containerBg,
                                  valueColor: AlwaysStoppedAnimation<Color>(isUnlimited ? AppColors.accentGreen : AppColors.primary),
                                ),
                                Icon(isUnlimited ? Icons.all_inclusive_rounded : Icons.storage_rounded, size: 14, color: AppColors.primary),
                              ]),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(isUnlimited ? 'Unlimited data' : '${plan['data']} • 0% used', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                              const Text('Fresh voucher — 100% available', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                            ])),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.accentGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentGreen, letterSpacing: 0.5))),
                          ]),
                        ),
                        const SizedBox(height: 20),

                        // Big code container
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
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _generatedCode!,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'monospace',
                                    color: AppColors.accentRed,
                                    letterSpacing: 1.5,
                                  ),
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
                  );
                },
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
