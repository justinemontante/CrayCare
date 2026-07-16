import 'dart:math';
import 'package:flutter/material.dart';
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
  final int decimalPlaces;

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
    this.decimalPlaces = 1,
  });

  @override
  State<AnalyticsLineChart> createState() => _AnalyticsLineChartState();
}

class _AnalyticsLineChartState extends State<AnalyticsLineChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  double _scrollOffset = 0.0;
  double _visibleWidth = 0.0;

  static const double _minPointSpacing = 12.0;

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

  @override
  void didUpdateWidget(covariant AnalyticsLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _scrollToIndex(widget.selectedIndex!));
      });
    }
  }

  double _yLabelW() => widget.large ? 36.0 : 32.0;

  double _virtualWidth() {
    final data = widget.data;
    if (data.length <= 1) return _visibleWidth;
    final padL = _yLabelW();
    final chartW = _visibleWidth - padL;
    if (chartW <= 0) return _visibleWidth;
    final naturalSpacing = chartW / (data.length - 1);
    if (naturalSpacing >= _minPointSpacing) return _visibleWidth;
    return padL + (data.length - 1) * _minPointSpacing;
  }

  bool get _isScrollable => _virtualWidth() > _visibleWidth + 0.5;

  void _clampScroll() {
    final maxScroll = max(0.0, _virtualWidth() - _visibleWidth);
    _scrollOffset = _scrollOffset.clamp(0.0, maxScroll);
  }

  void _scrollToIndex(int index) {
    if (!_isScrollable || _visibleWidth <= 0) return;
    final padL = _yLabelW();
    final vw = _virtualWidth();
    final chartW = vw - padL;
    if (chartW <= 0) return;
    final stepX =
        widget.data.length > 1 ? chartW / (widget.data.length - 1) : 0.0;
    final pointX = padL + index * stepX;
    final maxScroll = max(0.0, vw - _visibleWidth);
    _scrollOffset = (pointX - _visibleWidth / 2).clamp(0.0, maxScroll);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _scrollOffset -= details.delta.dx;
      _clampScroll();
    });
  }

  void _onTapUp(TapUpDetails details) {
    final data = widget.data;
    if (data.isEmpty) return;
    final padL = _yLabelW();
    final vw = _virtualWidth();
    final chartW = vw - padL;
    if (chartW <= 0) return;
    final stepX = data.length > 1 ? chartW / (data.length - 1) : 0.0;
    final virtualDx = details.localPosition.dx + _scrollOffset;
    final index =
        ((virtualDx - padL) / stepX).round().clamp(0, data.length - 1);
    widget.onSelectedIndexChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) return const SizedBox.shrink();
    final validData = widget.data.where((v) => !v.isNaN).toList();
    if (validData.isEmpty) return const SizedBox.shrink();

    final curIdx = widget.selectedIndex;

    double originalMin = validData.reduce(min);
    double originalMax = validData.reduce(max);
    double minVal;
    double maxVal;

    if ((originalMax - originalMin).abs() < 0.01) {
      double padding = originalMin == 0.0
          ? 5.0
          : (originalMin * 0.1).clamp(2.0, 10.0);
      minVal = originalMin - padding;
      maxVal = originalMin + padding;
    } else {
      double padding = (originalMax - originalMin) * 0.05;
      minVal = originalMin - padding;
      maxVal = originalMax + padding;
    }
    final range = maxVal - minVal;

    return LayoutBuilder(
      builder: (context, constraints) {
        _visibleWidth = constraints.maxWidth;
        _clampScroll();
        final vw = _virtualWidth();
        final scrollable = _isScrollable;
        final scrollBarH = scrollable ? 20.0 : 0.0;
        final chartH = widget.height - scrollBarH;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onTapUp,
                  onHorizontalDragUpdate:
                      scrollable ? _onHorizontalDragUpdate : null,
                  child: AnimatedBuilder(
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
                          pulseValue: widget.isLive
                              ? _pulseController.value
                              : 0.0,
                          scrollOffset: _scrollOffset,
                          virtualWidth: vw,
                        ),
                        size: Size(_visibleWidth, chartH),
                      );
                    },
                  ),
                ),
                if (curIdx != null && curIdx < widget.data.length)
                  Positioned(
                    top: 3,
                    left: _tooltipLeft(_visibleWidth),
                    child: _buildTooltip(curIdx),
                  ),
              ],
            ),
            if (scrollable)
              SizedBox(
                height: 20,
                child: _buildScrollBar(vw),
              ),
          ],
        );
      },
    );
  }

  Widget _buildScrollBar(double virtualWidth) {
    final maxScroll = max(0.0, virtualWidth - _visibleWidth);
    if (maxScroll <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackW = constraints.maxWidth;
        final thumbFraction = _visibleWidth / virtualWidth;
        final thumbW = max(24.0, trackW * thumbFraction);
        final thumbPos =
            (trackW - thumbW) * (_scrollOffset / maxScroll);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            setState(() {
              _scrollOffset +=
                  details.delta.dx * (maxScroll / (trackW - thumbW));
              _clampScroll();
            });
          },
          onTapDown: (details) {
            final tapX = details.localPosition.dx;
            final normalized = (tapX / trackW).clamp(0.0, 1.0);
            setState(() {
              _scrollOffset = (normalized * maxScroll).clamp(0.0, maxScroll);
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Positioned(
                  left: thumbPos,
                  child: Container(
                    width: thumbW,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.darkWith(0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _tooltipLeft(double totalWidth) {
    final curIdx = widget.selectedIndex;
    if (curIdx == null) return 8;
    final data = widget.data;
    final padL = _yLabelW();
    final vw = _virtualWidth();
    final chartW = vw - padL;
    if (chartW <= 0 || data.length <= 1) return 8;
    final stepX = chartW / (data.length - 1);
    final x = padL + curIdx * stepX - _scrollOffset;
    const tooltipW = 100;
    if (x + tooltipW > totalWidth) {
      return totalWidth - tooltipW;
    }
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
        val.isNaN
            ? '$label: No data'
            : '$label: ${val.toStringAsFixed(widget.decimalPlaces)} ${widget.unit}',
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
  final double scrollOffset;
  final double virtualWidth;

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
    this.scrollOffset = 0.0,
    this.virtualWidth = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final yLabelW = large ? 36.0 : 32.0;
    final padL = showAxis ? yLabelW : 4.0;
    const padR = 0.0;
    final padT = 8.0;
    final padB = showAxis ? (large ? 44.0 : 34.0) : 4.0;

    final visibleChartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;
    if (visibleChartW <= 0 || chartH <= 0) return;

    final vw = virtualWidth > size.width ? virtualWidth : size.width;
    final virtualChartW = vw - padL - padR;
    final stepX =
        data.length > 1 ? virtualChartW / (data.length - 1) : 0.0;

    final visibleLeft = padL;
    final visibleRight = size.width - padR;

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

      int decimalPlaces = 0;
      if (range < 1.0) {
        decimalPlaces = 2;
      } else if (range < 5.0) {
        decimalPlaces = 1;
      } else {
        decimalPlaces = 0;
      }

      final tickCount = 5;
      for (int i = 0; i <= tickCount; i++) {
        final y = padT + (chartH * i / tickCount);
        canvas.drawLine(
          Offset(visibleLeft, y),
          Offset(visibleRight, y),
          gridPaint,
        );

        final val = maxVal - (range * i / tickCount);
        final label = val.toStringAsFixed(decimalPlaces);
        final tp = TextPainter(
          text: TextSpan(
            text: i == tickCount ? '$label $unit' : label,
            style: textStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: yLabelW - 2);
        tp.paint(canvas, Offset(2, y - tp.height / 2));
      }
    }

    // Clip chart area for data
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(padL - 1, 0, visibleChartW + 2, size.height),
    );

    // Threshold lines removed per user request

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
        colors: [
          color.withValues(alpha: 0.15),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(padL, padT, visibleChartW, chartH));

    final path = Path();
    final fillPath = Path();

    // Build smooth points list (skip NaN gaps)
    final segments = <List<Offset>>[];
    var current = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      if (data[i].isNaN) {
        if (current.isNotEmpty) {
          segments.add(current);
          current = [];
        }
        continue;
      }
      final x = padL + i * stepX - scrollOffset;
      final y = padT + chartH - ((data[i] - minVal) / range) * chartH;
      current.add(Offset(x, y));
    }
    if (current.isNotEmpty) segments.add(current);

    for (final seg in segments) {
      if (seg.isEmpty) continue;
      if (seg.length == 1) {
        path.moveTo(seg.first.dx, seg.first.dy);
        fillPath.moveTo(seg.first.dx, padT + chartH);
        fillPath.lineTo(seg.first.dx, seg.first.dy);
        fillPath.lineTo(seg.first.dx, padT + chartH);
        fillPath.close();
        continue;
      }

      path.moveTo(seg.first.dx, seg.first.dy);
      fillPath.moveTo(seg.first.dx, padT + chartH);
      fillPath.lineTo(seg.first.dx, seg.first.dy);

      for (int i = 1; i < seg.length; i++) {
        final p0 = seg[max(0, i - 2)];
        final p1 = seg[max(0, i - 1)];
        final p2 = seg[i];
        final p3 = seg[min(seg.length - 1, i + 1)];

        final tension = 0.3;
        final cp1x = p1.dx + (p2.dx - p0.dx) * tension;
        final cp1y = p1.dy + (p2.dy - p0.dy) * tension;
        final cp2x = p2.dx - (p3.dx - p1.dx) * tension;
        final cp2y = p2.dy - (p3.dy - p1.dy) * tension;

        path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
        fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      }

      fillPath.lineTo(seg.last.dx, padT + chartH);
      fillPath.close();
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paintLine);

    // Dots (skip if too many)
    final dotPaint = Paint()..color = color;
    final dotBorder = Paint()..color = Colors.white;
    final dotStep = max(1, data.length ~/ 120);
    for (int i = 0; i < data.length; i += dotStep) {
      if (data[i].isNaN) continue;
      final x = padL + i * stepX - scrollOffset;
      if (x < visibleLeft - 5 || x > visibleRight + 5) continue;
      final y = padT + chartH - ((data[i] - minVal) / range) * chartH;
      canvas.drawCircle(Offset(x, y), 3, dotBorder);
      canvas.drawCircle(Offset(x, y), 2, dotPaint);
    }

    // Selected point highlight
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < data.length &&
        !data[selectedIndex!].isNaN) {
      final sx = padL + selectedIndex! * stepX - scrollOffset;
      final sy =
          padT + chartH - ((data[selectedIndex!] - minVal) / range) * chartH;

      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 1.2;

      double dashHeight = 4, dashSpace = 3;
      double startY = padT;
      while (startY < padT + chartH) {
        canvas.drawLine(
          Offset(sx, startY),
          Offset(sx, min(startY + dashHeight, padT + chartH)),
          linePaint,
        );
        startY += dashHeight + dashSpace;
      }
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
    if (isLive && data.isNotEmpty && !data.last.isNaN) {
      final lastIdx = data.length - 1;
      final lx = padL + lastIdx * stepX - scrollOffset;
      final ly =
          padT + chartH - ((data[lastIdx] - minVal) / range) * chartH;

      final pulsePaint = Paint()
        ..color = color.withValues(alpha: 0.3 * (1 - pulseValue))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(lx, ly), 4 + 10 * pulseValue, pulsePaint);
    }

    canvas.restore();

    // X-axis labels — always 6, evenly spaced, slanted
    if (showAxis && labels != null && labels!.isNotEmpty) {
      final count = data.length;
      if (count > 0) {
        final targetCount = min(6, count);
        const angle = -0.55;
        final cosA = cos(angle);
        final sinA = sin(angle);
        final maxRight = size.width - padR - 2;

        final idxs = <int>[];
        for (int n = 0; n < targetCount; n++) {
          final t = targetCount > 1 ? n / (targetCount - 1) : 0.5;
          final probeX = padL + (maxRight - padL) * t;
          final dataX = probeX + scrollOffset - padL;
          idxs.add((dataX / stepX).round().clamp(0, count - 1));
        }

        double maxSlantExtent = 0;
        for (final idx in idxs) {
          final tp = TextPainter(
            text: TextSpan(text: labels![idx], style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          final ext = tp.width * cosA.abs() + tp.height * sinA.abs();
          if (ext > maxSlantExtent) maxSlantExtent = ext;
        }

        final firstX = padL;
        final lastX = maxRight - maxSlantExtent;
        final spacing = targetCount > 1 ? (lastX - firstX) / (targetCount - 1) : 0.0;

        for (int n = 0; n < targetCount; n++) {
          final fixedX = firstX + spacing * n;
          final dataX = fixedX + scrollOffset - padL;
          final idx = (dataX / stepX).round().clamp(0, count - 1);
          final tp = TextPainter(
            text: TextSpan(text: labels![idx], style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          final anchorY = size.height - padB + 18;
          final tx = tp.width * 0.15;
          final dx = fixedX + tx * cosA;
          final dy = anchorY + tx * sinA;
          canvas.save();
          canvas.translate(dx, dy);
          canvas.rotate(angle);
          tp.paint(canvas, Offset.zero);
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.large != large ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.pulseValue != pulseValue ||
      oldDelegate.scrollOffset != scrollOffset;
}


