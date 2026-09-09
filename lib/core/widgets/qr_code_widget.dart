import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// A lightweight, pure Flutter QR code rendering widget powered by package:barcode.
class QrCodeWidget extends StatelessWidget {
  final String data;
  final double size;
  final Color color;
  final Color backgroundColor;

  const QrCodeWidget({
    super.key,
    required this.data,
    this.size = 140,
    this.color = Colors.black,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: _QrCodePainter(data, color: color),
      ),
    );
  }
}

class _QrCodePainter extends CustomPainter {
  final String data;
  final Color color;

  _QrCodePainter(this.data, {required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()..color = color;
    try {
      final barcode = Barcode.qrCode();
      for (final element in barcode.make(data, width: size.width, height: size.height)) {
        if (element is BarcodeBar && element.black) {
          canvas.drawRect(
            Rect.fromLTWH(element.left, element.top, element.width, element.height),
            paint,
          );
        }
      }
    } catch (_) {}
  }

  @override
  bool shouldRepaint(covariant _QrCodePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}
