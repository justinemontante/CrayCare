import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../theme/app_colors.dart';

class AnalyticsLineChart extends StatefulWidget {
  final List<double> data;
  final Color color;
  final String unit;
  final List<String>? labels;
  final bool large;
  final double height;
  final int? selectedIndex;
  final ValueChanged<int?>? onSelectedIndexChanged;
  final double? thresholdMin;
  final double? thresholdMax;
  final bool isLive;

  const AnalyticsLineChart({
    super.key,
    required this.data,
    required this.color,
    required this.unit,
    this.labels,
    this.large = false,
    required this.height,
    this.selectedIndex,
    this.onSelectedIndexChanged,
    this.thresholdMin,
    this.thresholdMax,
    this.isLive = false,
  });

  @override
  State<AnalyticsLineChart> createState() => _AnalyticsLineChartState();
}

class _AnalyticsLineChartState extends State<AnalyticsLineChart> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _selectPoint(Offset localPosition) {
    final data = widget.data;
    if (data.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final width = renderBox.size.width;

    final yLabelW = widget.large ? 42.0 : 36.0;
    final padL = yLabelW;
    final padR = 12.0; // Consistent with painter
    final chartW = width - padL - padR;
    if (chartW <= 0) return;

    final stepX = data.length > 1 ? chartW / (data.length - 1) : 0.0;
    final index = ((localPosition.dx - padL) / stepX).round().clamp(
      0,
      data.length - 1,
    );

    widget.onSelectedIndexChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) return const SizedBox.shrink();

    final curIdx = widget.selectedIndex;
    final minVal = widget.data.reduce(min);
    final maxVal = widget.data.reduce(max);
    final range = (maxVal - minVal).abs() < 0.01 ? 1.0 : maxVal - minVal;

    return LayoutBuilder(
      builder: (context, constraints) {
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            PanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(),
              (instance) {
                instance.onStart =
                    (details) => _selectPoint(details.localPosition);
                instance.onUpdate =
                    (details) => _selectPoint(details.localPosition);
              },
            ),
          },
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _LineChartPainter(
                      widget.data,
                      minVal,
                      range,
                      widget.color,
                      labels: widget.labels,
                      unit: widget.unit,
                      showAxis: true,
                      large: widget.large,
                      selectedIndex: curIdx,
                      thresholdMin: widget.thresholdMin,
                      thresholdMax: widget.thresholdMax,
                      isLive: widget.isLive,
                      pulseValue: widget.isLive ? _pulseController.value : 0.0,
                    ),
                    size: Size(constraints.maxWidth, widget.height),
                  );
                },
              ),
              if (curIdx != null && curIdx < widget.data.length)
                Positioned(
                  top: 3,
                  left: _tooltipLeft(constraints.maxWidth),
                  child: _buildTooltip(curIdx),
                ),
            ],
          ),
        );
      },
    );
  }

  double _tooltipLeft(double totalWidth) {
    final curIdx = widget.selectedIndex;
    if (curIdx == null) return 8;
    final data = widget.data;
    final yLabelW = widget.large ? 42.0 : 36.0;
    final padL = yLabelW;
    final padR = 12.0; // Consistent with painter
    final chartW = totalWidth - padL - padR;
    if (chartW <= 0 || data.length <= 1) return 8;
    final stepX = chartW / (data.length - 1);
    final x = padL + curIdx * stepX;
    const tooltipW = 100;
    if (x + tooltipW > totalWidth - padR) return totalWidth - tooltipW - padR;
    if (x - tooltipW / 2 < padL) return padL;
    return x - tooltipW / 2;
  }

  Widget _buildTooltip(int index) {
    final val = widget.data[index];
    final label = (widget.labels != null && index < widget.labels!.length)
        ? widget.labels![index]
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B3C49),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: ${val.toStringAsFixed(1)} ${widget.unit}',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final double minVal;
  final double range;
  final Color color;
  final List<String>? labels;
  final String unit;
  final bool showAxis;
  final bool large;
  final int? selectedIndex;
  final double? thresholdMin;
  final double? thresholdMax;
  final bool isLive;
  final double pulseValue;

  _LineChartPainter(
    this.data,
    this.minVal,
    this.range,
    this.color, {
    this.labels,
    this.unit = '',
    this.showAxis = false,
    this.large = false,
    this.selectedIndex,
    this.thresholdMin,
    this.thresholdMax,
    this.isLive = false,
    this.pulseValue = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final yLabelW = large ? 42.0 : 36.0;
    final padL = showAxis ? yLabelW : 4.0;
    final padR = 12.0; // Increased padding to ensure the last dot/pulse isn't clipped
    final padT = 8.0;
    final padB = showAxis ? (large ? 44.0 : 34.0) : 4.0;

    final chartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;
    if (chartW <= 0 || chartH <= 0) return;

    final maxVal = minVal + range;
    final textStyle = TextStyle(
      color: AppColors.darkWith(0.53),
      fontSize: large ? 8 : 7,
      fontWeight: FontWeight.w500,
    );

    // Y-axis grid lines + labels
    if (showAxis) {
      final gridPaint = Paint()
        ..color = AppColors.darkWith(0.05)
        ..strokeWidth = 1;

      final tickCount = 5;
      for (int i = 0; i <= tickCount; i++) {
        final y = padT + (chartH * i / tickCount);
        canvas.drawLine(
          Offset(padL, y),
          Offset(size.width - padR, y),
          gridPaint,
        );

        final val = maxVal - (range * i / tickCount);
        final label = val.toStringAsFixed(val.abs() >= 10 ? 0 : 1);
        final tp = TextPainter(
          text: TextSpan(
            text: i == tickCount ? '$label $unit' : label,
            style: textStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: yLabelW - 4);
        tp.paint(canvas, Offset(padL - yLabelW + 2, y - tp.height / 2));
      }
    }

    // X-axis labels (slanted)
    if (showAxis && labels != null && labels!.isNotEmpty) {
      final xLabels = _getXLabels();
      for (final xl in xLabels) {
        final x = padL + (chartW * xl.index / (data.length - 1));
        final tp = TextPainter(
          text: TextSpan(text: xl.text, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelW = tp.width;
        canvas.save();
        canvas.translate(x, size.height - padB + 14);
        canvas.rotate(-0.55);
        tp.paint(canvas, Offset(-labelW / 2, 0));
        canvas.restore();
      }
    }

    // Line paint
    final paintLine = Paint()
      ..color = color
      ..strokeWidth = large ? 2.5 : 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Fill paint
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(padL, padT, chartW, chartH));

    final stepX = data.length > 1 ? chartW / (data.length - 1) : 0.0;
    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = padL + i * stepX;
      final y = padT + chartH - ((data[i] - minVal) / range) * chartH;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, padT + chartH);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(padL + (data.length - 1) * stepX, padT + chartH);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paintLine);

    // Dots
    final dotPaint = Paint()..color = color;
    final dotBorder = Paint()..color = Colors.white;
    final dotStep = 1;

    for (int i = 0; i < data.length; i += dotStep) {
      final x = padL + i * stepX;
      final y = padT + chartH - ((data[i] - minVal) / range) * chartH;
      canvas.drawCircle(Offset(x, y), 3, dotBorder);
      canvas.drawCircle(Offset(x, y), 2, dotPaint);
    }

    // Selected point highlight & vertical line
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < data.length) {
      final sx = padL + selectedIndex! * stepX;
      final sy =
          padT + chartH - ((data[selectedIndex!] - minVal) / range) * chartH;
      // Vertical line
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(sx, padT), Offset(sx, padT + chartH), linePaint);
      // Selected point dot (web style)
      canvas.drawCircle(Offset(sx, sy), 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(sx, sy),
        5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // Live pulsing dot
    if (isLive && data.isNotEmpty) {
      final lastIdx = data.length - 1;
      final lx = padL + lastIdx * stepX;
      final ly = padT + chartH - ((data[lastIdx] - minVal) / range) * chartH;

      final pulsePaint = Paint()
        ..color = color.withValues(alpha: 0.3 * (1 - pulseValue))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(lx, ly), 4 + 10 * pulseValue, pulsePaint);
    }
  }

  List<_XLabel> _getXLabels() {
    if (labels == null || labels!.isEmpty) return [];
    final count = data.length;
    if (count <= 1) return [_XLabel(labels![0], 0)];
    if (count <= 6) {
      return List.generate(count, (i) => _XLabel(labels![i], i));
    }
    final step = count > 48 ? count ~/ 7 : (count ~/ 6).clamp(1, count - 1);
    return [
      0,
      step,
      step * 2,
      step * 3,
      step * 4,
      step * 5,
      count - 1,
    ].where((i) => i < count).map((i) => _XLabel(labels![i], i)).toList();
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.large != large ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.thresholdMin != thresholdMin ||
      oldDelegate.thresholdMax != thresholdMax ||
      oldDelegate.pulseValue != pulseValue;
}

class _XLabel {
  final String text;
  final int index;
  const _XLabel(this.text, this.index);
}
