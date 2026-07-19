import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/crayfish_detection_service.dart';
import '../models/crayfish_detection.dart';

/// Paints bounding boxes + labels for all detections from [CrayfishDetectionService]
/// on top of whatever widget it overlays.
///
/// Usage:
/// ```dart
/// Stack(
///   children: [
///     CameraPreview(controller),
///     const Positioned.fill(child: PredictionOverlay()),
///   ],
/// )
/// ```
class PredictionOverlay extends StatelessWidget {
  /// Minimum confidence to display a detection (default: 0.4).
  final double minConfidence;

  /// Whether to show the confidence percentage in the label (default: true).
  final bool showConfidence;

  const PredictionOverlay({
    super.key,
    this.minConfidence = 0.4,
    this.showConfidence = true,
  });

  @override
  Widget build(BuildContext context) {
    final service = context.watch<CrayfishDetectionService>();
    final detections = service.latestDetections
        .where((d) => d.confidence >= minConfidence)
        .toList();

    return CustomPaint(
      painter: _BoxPainter(
        detections: detections,
        showConfidence: showConfidence,
      ),
      child: const SizedBox.expand(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BoxPainter extends CustomPainter {
  final List<CrayfishDetection> detections;
  final bool showConfidence;

  const _BoxPainter({
    required this.detections,
    required this.showConfidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final color = _colorForLabel(d.label);

      final borderPaint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;

      final fillPaint = Paint()
        ..color = color.withOpacity(0.15)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromLTRB(
        d.left * size.width,
        d.top * size.height,
        d.right * size.width,
        d.bottom * size.height,
      );

      // Semi-transparent fill
      canvas.drawRect(rect, fillPaint);
      // Solid border
      canvas.drawRect(rect, borderPaint);
      // Corner brackets
      _drawCornerBrackets(canvas, rect, color);
      // Label pill
      _drawLabel(canvas, rect, d, color);
    }
  }

  Color _colorForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('female')) return const Color(0xFFFF4081); // Pink
    if (l.contains('male')) return const Color(0xFF2196F3);   // Blue
    return Colors.green;
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 20.0;

    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(len, 0), p);
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(0, len), p);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight.translate(-len, 0), p);
    canvas.drawLine(rect.topRight, rect.topRight.translate(0, len), p);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(len, 0), p);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(0, -len), p);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(-len, 0), p);
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(0, -len), p);
  }

  void _drawLabel(Canvas canvas, Rect rect, CrayfishDetection d, Color color) {
    final emoji = d.label.toLowerCase().contains('female') ? '♀' : '♂';
    final text = showConfidence
        ? ' $emoji ${_cap(d.label)} ${(d.confidence * 100).toStringAsFixed(0)}% '
        : ' $emoji ${_cap(d.label)} ';

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Position above box, fall back to below if not enough room
    double labelY = rect.top - tp.height - 4;
    if (labelY < 0) labelY = rect.bottom + 4;

    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.left, labelY, tp.width, tp.height),
      const Radius.circular(4),
    );

    canvas.drawRRect(labelRect, Paint()..color = color);
    tp.paint(canvas, Offset(rect.left, labelY));
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  @override
  bool shouldRepaint(covariant _BoxPainter old) {
    if (old.detections.length != detections.length) return true;
    for (int i = 0; i < detections.length; i++) {
      if (old.detections[i] != detections[i]) return true;
    }
    return false;
  }
}
