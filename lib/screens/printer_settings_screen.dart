import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_theme.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  bool _autoPrint = true;
  bool _isScanning = false;
  bool _isTesting = false;
  int _paperWidthMm = 58;

  List<Printer> _printers = [];
  Printer? _selectedPrinter;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndPrinters();
  }

  Future<void> _loadSettingsAndPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoPrint = prefs.getBool('wavepass_auto_print_receipts') ?? true;
      _paperWidthMm = prefs.getInt('wavepass_printer_paper_width') ?? 58;
    });

    await _scanPrinters();
  }

  Future<void> _scanPrinters() async {
    setState(() => _isScanning = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('wavepass_selected_printer_url');

      final printers = await Printing.listPrinters();

      Printer? matched;
      if (savedUrl != null && printers.isNotEmpty) {
        matched = printers.firstWhere(
          (p) => p.url == savedUrl,
          orElse: () => printers.first,
        );
      } else if (printers.isNotEmpty) {
        matched = printers.first;
      }

      if (mounted) {
        setState(() {
          _printers = printers;
          _selectedPrinter = matched;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning printers: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _selectPrinter(Printer printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wavepass_selected_printer_url', printer.url);
    await prefs.setString('wavepass_selected_printer_name', printer.name);
    setState(() => _selectedPrinter = printer);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected printer: ${printer.name}'),
          backgroundColor: AppColors.accentGreen,
        ),
      );
    }
  }

  Future<void> _toggleAutoPrint(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wavepass_auto_print_receipts', val);
    setState(() => _autoPrint = val);
  }

  Future<void> _setPaperWidth(int width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wavepass_printer_paper_width', width);
    setState(() => _paperWidthMm = width);
  }

  Future<void> _handleTestPrint() async {
    setState(() => _isTesting = true);
    try {
      final format = _paperWidthMm == 80 ? PdfPageFormat.roll80 : PdfPageFormat.roll57;
      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(10),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                'WAVEPASS TEST RECEIPT',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Hardware Feed Check', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 6),
              pw.Text('PRINTER STATUS: OK', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('Model: ${_selectedPrinter?.name ?? "System Print Spooler"}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Paper: ${_paperWidthMm}mm Thermal Roll', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                child: pw.Text('SAMPLE PASS: WP-8821-4409', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5),
              pw.Text(DateTime.now().toLocal().toString().split('.')[0], style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 12),
              pw.Text('- - - - - - - - - - - - - - - -', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
      );

      final bytes = await doc.save();

      if (_selectedPrinter != null) {
        await Printing.directPrintPdf(
          printer: _selectedPrinter!,
          onLayout: (_) async => bytes,
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          format: format,
          name: 'WavePass_Test_Receipt',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Test receipt sent to printer!"),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Print error: $e"),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Thermal Printer Setup",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
          ),
        ),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: 'Scan for Printers',
            onPressed: _isScanning ? null : _scanPrinters,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Connect a portable 58mm or 80mm Bluetooth / Wi-Fi thermal POS printer to print paper guest passes instantly.",
              style: TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.4),
            ),
            const SizedBox(height: 20),

            // Connected / Selected Printer Card
            if (_selectedPrinter != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.containerBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.cardBorder),
                                ),
                                child: const Icon(Icons.print_rounded, color: AppColors.primary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedPrinter!.name,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${_paperWidthMm}mm Thermal • ${_selectedPrinter!.url.contains('bluetooth') ? 'Bluetooth' : 'Network/System'}",
                                      style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accentGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "ACTIVE",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.accentGreen,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _isTesting ? null : _handleTestPrint,
                        icon: _isTesting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.receipt_long_rounded, size: 18),
                        label: Text(_isTesting ? "Printing Test Receipt..." : "Test Print Receipt Feed"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.containerBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.print_disabled_rounded, size: 40, color: AppColors.textLight),
                    const SizedBox(height: 10),
                    const Text(
                      "No Printer Selected",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Pair your Bluetooth thermal printer in Android Bluetooth settings, then select it below.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _isScanning ? null : _scanPrinters,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text("Scan for Devices"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Paper Width Selector
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Paper Roll Size",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                      SizedBox(height: 2),
                      Text("Standard portable POS roll width", style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                    ],
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 58, label: Text("58mm")),
                      ButtonSegment(value: 80, label: Text("80mm")),
                    ],
                    selected: {_paperWidthMm},
                    onSelectionChanged: (set) => _setPaperWidth(set.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Toggle Card: Auto Print
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Always Print Automatically",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Print a ticket immediately whenever a cash pass is sold.",
                          style: TextStyle(fontSize: 11, color: AppColors.textLight),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _autoPrint,
                    activeTrackColor: AppColors.accentGreen,
                    onChanged: _toggleAutoPrint,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Available / Discovered Printers List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "DISCOVERED PRINTERS",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.8),
                ),
                Text(
                  "${_printers.length} found",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textLight),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_printers.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.containerBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textLight),
                        SizedBox(width: 8),
                        Text("Pairing Instructions", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      "1. Power on your Bluetooth thermal printer.\n2. Open your device's Android Settings → Bluetooth.\n3. Search and pair your printer (common default PIN: 0000 or 1234).\n4. Return here and tap the refresh button at the top right.",
                      style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.5),
                    ),
                  ],
                ),
              )
            else
              ..._printers.map((p) {
                final isSelected = _selectedPrinter?.url == p.url;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.white : AppColors.containerBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? AppColors.primary : AppColors.cardBorder, width: isSelected ? 1.5 : 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.bluetooth_connected_rounded,
                              color: isSelected ? AppColors.accentGreen : AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    p.model ?? p.url,
                                    style: const TextStyle(fontSize: 10, color: AppColors.textLight),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.accentGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            "SELECTED",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.accentGreen),
                          ),
                        )
                      else
                        OutlinedButton(
                          onPressed: () => _selectPrinter(p),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: const Size(64, 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text("Select", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
