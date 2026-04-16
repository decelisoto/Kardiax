// lib/widgets/ecg_painter.dart

import 'package:flutter/material.dart';

class EcgPainter extends CustomPainter {
  final List<double> samples; // normalised 0.0 – 1.0
  final bool isArrhythmia;
  final Color waveColor;

  const EcgPainter({
    required this.samples,
    required this.isArrhythmia,
    this.waveColor = const Color(0xFF00C853),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    // ── Grid ──
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;

    // Major grid — 5 rows, 10 cols
    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (int i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Minor grid — subdivide 5x per major cell
    final minorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 0.3;

    for (int i = 0; i < 25; i++) {
      final y = size.height * i / 25;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorPaint);
    }
    for (int i = 0; i < 50; i++) {
      final x = size.width * i / 50;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorPaint);
    }

    // ── Waveform ──
    final wavePaint = Paint()
      ..color = isArrhythmia ? const Color(0xFFFF3131) : waveColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Glow layer (thicker, more transparent) — gives the ECG a subtle glow
    final glowPaint = Paint()
      ..color = (isArrhythmia ? const Color(0xFFFF3131) : waveColor)
          .withValues(alpha: 0.15)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = Path();
    final glowPath = Path();
    final step = size.width / (samples.length - 1);

    // Vertical padding so waveform never clips at top/bottom
    const vPad = 0.15;

    for (int i = 0; i < samples.length; i++) {
      final x = i * step;
      final normalised = samples[i].clamp(0.0, 1.0);
      // Flip Y + apply vertical padding
      final y = size.height * (1.0 - vPad - normalised * (1.0 - vPad * 2));

      if (i == 0) {
        path.moveTo(x, y);
        glowPath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        glowPath.lineTo(x, y);
      }
    }

    canvas.drawPath(glowPath, glowPaint);
    canvas.drawPath(path, wavePaint);

    // ── Scan line (leading edge indicator) ──
    if (samples.isNotEmpty) {
      final lastX = (samples.length - 1) * step;
      final lastY =
          size.height *
          (1.0 - vPad - samples.last.clamp(0.0, 1.0) * (1.0 - vPad * 2));

      final dotPaint = Paint()
        ..color = isArrhythmia ? const Color(0xFFFF3131) : waveColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(lastX, lastY), 3.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(EcgPainter old) =>
      old.samples != samples || old.isArrhythmia != isArrhythmia;
}
