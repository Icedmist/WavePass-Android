import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/theme/app_theme.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final TextEditingController _manualController = TextEditingController();
  bool _isProcessing = false;

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        setState(() {
          _isProcessing = true;
        });
        _handleSuccessfulScan(barcode.rawValue!);
        break;
      }
    }
  }

  void _handleSuccessfulScan(String serial) async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: AppColors.accentGreen, size: 24),
            SizedBox(width: 8),
            Text("Router Identified", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Serial Number Scanned:", style: TextStyle(fontSize: 12, color: AppColors.textLight)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                serial,
                style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'monospace', fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "When you plug this router into your internet cable, it will automatically connect to WavePass.",
              style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text("Done"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Scan Box Barcode",
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // Camera scanner window
          Expanded(
            flex: 3,
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                // Viewfinder Target Frame
                Container(
                  width: 250,
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.accentRed, width: 2.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                Positioned(
                  bottom: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "Fit the barcode inside the box",
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom card: Manual entry fallback
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Or Type Serial Number",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      hintText: "e.g. 9F8A0B1C2D3E",
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      final text = _manualController.text.trim();
                      if (text.isNotEmpty) {
                        _handleSuccessfulScan(text);
                      }
                    },
                    child: const Text("Register Router"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
