import 'dart:math';
import 'package:flutter/foundation.dart' show listEquals;
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
  final double? axisMinY;
  final int? axisDecimalPlaces;
  final int decimalPlaces;
  final bool fitYAxisToData;
  final bool tightLiveYAxis;
  final bool initialScrollToEnd;
  final bool connectAcrossMissingData;
  final bool liveMode;

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
    this.axisMinY,
    this.axisDecimalPlaces,
    this.decimalPlaces = 1,
    this.fitYAxisToData = false,
    this.tightLiveYAxis = false,
    this.initialScrollToEnd = false,
    this.connectAcrossMissingData = false,
    this.liveMode = false,
  });

  @override
  State<AnalyticsLineChart> createState() => _AnalyticsLineChartState();
}

class _AnalyticsLineChartState extends State<AnalyticsLineChart>
    with TickerProviderStateMixin {
  double _scrollOffset = 0.0;
  double _visibleWidth = 0.0;
  bool _needsScrollToEnd = false;
  late final AnimationController _transitionController;
  late final AnimationController _livePulseController;
  List<double>? _transitionFrom;

  static const double _minPointSpacing = 12.0;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(_onTransitionTick);
    _livePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    if (widget.liveMode) _livePulseController.repeat(reverse: true);
    if (widget.initialScrollToEnd) _needsScrollToEnd = true;
  }

  void _onTransitionTick() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AnalyticsLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.liveMode != oldWidget.liveMode) {
      if (widget.liveMode) {
        _livePulseController.repeat(reverse: true);
      } else {
        _livePulseController.stop();
      }
    }
    if (widget.liveMode &&
        oldWidget.liveMode &&
        !listEquals(widget.data, oldWidget.data) &&
        _isSequentialLiveUpdate(oldWidget, widget)) {
      final progress = Curves.easeInOut.transform(_transitionController.value);
      _transitionFrom = _blendData(
        _transitionFrom ?? oldWidget.data,
        oldWidget.data,
        progress,
      );
      _transitionController.forward(from: 0);
    } else if (!listEquals(widget.data, oldWidget.data)) {
      _transitionFrom = null;
      _transitionController
        ..stop()
        ..value = 1;
    }
    if (widget.initialScrollToEnd && widget.data != oldWidget.data) {
      _needsScrollToEnd = true;
    }
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex != null &&
        widget.selectedIndex! >= 0 &&
        widget.selectedIndex! < widget.data.length &&
        (!widget.connectAcrossMissingData ||
            !widget.data[widget.selectedIndex!].isNaN)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _scrollToIndex(widget.selectedIndex!));
      });
    }
  }

  bool _isSequentialLiveUpdate(
    AnalyticsLineChart oldWidget,
    AnalyticsLineChart newWidget,
  ) {
    final oldLabels = oldWidget.labels;
    final newLabels = newWidget.labels;
    if (oldWidget.data.isEmpty ||
        newWidget.data.isEmpty ||
        oldLabels == null ||
        newLabels == null ||
        oldLabels.length != oldWidget.data.length ||
        newLabels.length != newWidget.data.length) {
      return false;
    }
    if (newWidget.data.length == oldWidget.data.length + 1) {
      return listEquals(oldLabels, newLabels.take(oldLabels.length).toList());
    }
    if (newWidget.data.length == oldWidget.data.length &&
        oldWidget.data.length > 1) {
      return listEquals(
        oldLabels.skip(1).toList(),
        newLabels.take(newLabels.length - 1).toList(),
      );
    }
    return oldWidget.data.length == 1 &&
        newWidget.data.length == 1 &&
        oldLabels.single != newLabels.single;
  }

  List<double> _blendData(List<double> from, List<double> to, double progress) {
    if (to.isEmpty) return const [];
    final start = List<double>.from(from);
    while (start.length < to.length) {
      start.add(start.isEmpty ? to.first : start.last);
    }
    if (start.length > to.length) {
      start.removeRange(0, start.length - to.length);
    }
    return List<double>.generate(to.length, (index) {
      final a = start[index];
      final b = to[index];
      if (!a.isFinite || !b.isFinite) return b;
      return a + ((b - a) * progress);
    });
  }

  List<double> get _displayData {
    final from = _transitionFrom;
    if (!widget.liveMode || from == null || _transitionController.value >= 1) {
      return widget.data;
    }
    return _blendData(
      from,
      widget.data,
      Curves.easeInOut.transform(_transitionController.value),
    );
  }

  @override
  void dispose() {
    _transitionController.dispose();
    _livePulseController.dispose();
    super.dispose();
  }

  // Reserve enough room for decimal sensor values and the unit on the
  // bottom tick, while keeping the same six Y-axis labels.
  double _yLabelW() => widget.large ? 48.0 : 44.0;

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
    if (!_isScrollable || _visibleWidth <= 0 || widget.data.length <= 1) return;
    final padL = _yLabelW();
    final vw = _virtualWidth();
    final chartW = vw - padL;
    if (chartW <= 0) return;
    final safeIndex = index.clamp(0, widget.data.length - 1);
    final stepX = chartW / (widget.data.length - 1);
    final pointX = padL + safeIndex * stepX;
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
    if (data.length == 1) {
      widget.onSelectedIndexChanged?.call(0);
      return;
    }
    final padL = _yLabelW();
    final vw = _virtualWidth();
    final chartW = vw - padL;
    if (chartW <= 0) return;
    final stepX = chartW / (data.length - 1);
    if (stepX <= 0) return;
    final virtualDx = details.localPosition.dx + _scrollOffset;
    var index = ((virtualDx - padL) / stepX).round().clamp(0, data.length - 1);
    if (widget.connectAcrossMissingData && data[index].isNaN) {
      int? nearestValidIndex;
      for (var distance = 1; distance < data.length; distance++) {
        final left = index - distance;
        final right = index + distance;
        if (left >= 0 && !data[left].isNaN) {
          nearestValidIndex = left;
          break;
        }
        if (right < data.length && !data[right].isNaN) {
          nearestValidIndex = right;
          break;
        }
      }
      if (nearestValidIndex == null) return;
      index = nearestValidIndex;
    }
    widget.onSelectedIndexChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final displayData = _displayData;
    if (displayData.isEmpty) return const SizedBox.shrink();
    final validData = displayData.where((v) => !v.isNaN).toList();
    if (validData.isEmpty) return const SizedBox.shrink();

    final curIdx = widget.selectedIndex;

    double originalMin = validData.reduce(min);
    double originalMax = validData.reduce(max);
    if (!widget.fitYAxisToData) {
      final safeThresholdMin = widget.thresholdMin;
      final safeThresholdMax = widget.thresholdMax;
      if (safeThresholdMin != null && safeThresholdMin.isFinite) {
        originalMin = min(originalMin, safeThresholdMin);
      }
      // 999 is the app's sentinel for an intentionally unbounded upper range.
      if (safeThresholdMax != null &&
          safeThresholdMax.isFinite &&
          safeThresholdMax < 999) {
        originalMax = max(originalMax, safeThresholdMax);
      }
    }
    double minVal;
    double maxVal;

    if (widget.fitYAxisToData) {
      // The 24-hour chart uses the observed readings for its own Y range so
      // small changes remain visible without changing other time filters.
      final span = originalMax - originalMin;
      final padding = widget.liveMode && widget.tightLiveYAxis
          ? max(span * 0.05, 0.025)
          : max(span * 0.05, max(originalMax.abs() * 0.01, 0.01));
      minVal = originalMin - padding;
      maxVal = originalMax + padding;
    } else if ((originalMax - originalMin).abs() < 0.01) {
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
    // Sensor readings are non-negative. Keep dynamic scaling for detail, but
    // never let the axis padding create negative tick labels. Turbidity can
    // additionally request an exact zero baseline.
    minVal = max(
      0.0,
      widget.fitYAxisToData ? minVal : (widget.axisMinY ?? minVal),
    );
    if (maxVal <= minVal) maxVal = minVal + 1.0;
    final range = maxVal - minVal;

    return LayoutBuilder(
      builder: (context, constraints) {
        _visibleWidth = constraints.maxWidth;
        if (_needsScrollToEnd) {
          _needsScrollToEnd = false;
          final maxScroll = max(0.0, _virtualWidth() - _visibleWidth);
          _scrollOffset = maxScroll;
        }
        _clampScroll();
        final vw = _virtualWidth();
        final scrollable = _isScrollable;
        final chartH = widget.height;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onTapUp,
                  onHorizontalDragUpdate: scrollable
                      ? _onHorizontalDragUpdate
                      : null,
                  child: CustomPaint(
                    painter: _LineChartPainter(
                      displayData,
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
                      axisDecimalPlaces: widget.axisDecimalPlaces,
                      scrollOffset: _scrollOffset,
                      virtualWidth: vw,
                      connectAcrossMissingData: widget.connectAcrossMissingData,
                      liveMode: widget.liveMode,
                      livePulse: _livePulseController,
                    ),
                    size: Size(_visibleWidth, chartH),
                  ),
                ),
                if (curIdx != null &&
                    curIdx >= 0 &&
                    curIdx < widget.data.length &&
                    (!widget.connectAcrossMissingData ||
                        !widget.data[curIdx].isNaN))
                  Positioned(
                    top: 3,
                    left: _tooltipLeft(_visibleWidth),
                    child: _buildTooltip(curIdx),
                  ),
              ],
            ),
            if (scrollable) SizedBox(height: 20, child: _buildScrollBar(vw)),
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
        if (trackW <= 0 || virtualWidth <= 0) return const SizedBox.shrink();
        final thumbFraction = _visibleWidth / virtualWidth;
        final thumbW = min(trackW, max(24.0, trackW * thumbFraction));
        final travel = trackW - thumbW;
        final thumbPos = travel <= 0
            ? 0.0
            : travel * (_scrollOffset / maxScroll);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: travel <= 0
              ? null
              : (details) {
                  setState(() {
                    _scrollOffset += details.delta.dx * (maxScroll / travel);
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
    if (chartW <= 0 || data.length <= 1) return padL;
    final stepX = chartW / (data.length - 1);
    final x = padL + curIdx * stepX - _scrollOffset;
    const tooltipW = 140.0;
    if (x + tooltipW > totalWidth) {
      return max(0.0, totalWidth - tooltipW);
    }
    if (x - tooltipW / 2 < padL) return padL;
    return x - tooltipW / 2;
  }

  Widget _buildTooltip(int index) {
    final val = widget.data[index];
    if (widget.connectAcrossMissingData && val.isNaN) {
      return const SizedBox.shrink();
    }
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
  final int? axisDecimalPlaces;
  final double scrollOffset;
  final double virtualWidth;
  final bool connectAcrossMissingData;
  final bool liveMode;
  final Animation<double>? livePulse;

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
    this.axisDecimalPlaces,
    this.scrollOffset = 0.0,
    this.virtualWidth = 0.0,
    this.connectAcrossMissingData = false,
    this.liveMode = false,
    this.livePulse,
  }) : super(repaint: livePulse);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // Keep chart geometry aligned with hit-testing/scroll calculations in the
    // stateful chart widget. Add visual spacing to the time labels themselves.
    final yLabelW = large ? 48.0 : 44.0;
    final padL = showAxis ? yLabelW : 4.0;
    const padR = 0.0;
    final padT = 8.0;
    final padB = showAxis ? (large ? 52.0 : 42.0) : 4.0;

    final visibleChartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;
    if (visibleChartW <= 0 || chartH <= 0) return;

    final vw = virtualWidth > size.width ? virtualWidth : size.width;
    final virtualChartW = vw - padL - padR;
    final stepX = data.length > 1 ? virtualChartW / (data.length - 1) : 0.0;

    final visibleLeft = padL;
    final visibleRight = size.width - padR;

    final maxVal = minVal + range;
    final yTextStyle = TextStyle(
      color: AppColors.darkWith(0.53),
      fontSize: 8,
      fontWeight: FontWeight.w500,
    );
    final xTextStyle = TextStyle(
      color: AppColors.darkWith(0.53),
      fontSize: large ? 8 : 7,
      fontWeight: FontWeight.w500,
    );

    if (showAxis) {
      final gridPaint = Paint()
        ..color = AppColors.darkWith(0.05)
        ..strokeWidth = 1;

      // Keep two decimal places, matching the precision shown for sensor
      // readings in the chart tooltip, even when the axis range is wide.
      final decimalPlaces = axisDecimalPlaces ?? 2;

      const tickCount = 5;
      for (int i = 0; i <= tickCount; i++) {
        final val = i == tickCount ? minVal : maxVal - (range * i / tickCount);
        final y = padT + (chartH * i / tickCount);
        canvas.drawLine(
          Offset(visibleLeft, y),
          Offset(visibleRight, y),
          gridPaint,
        );
        final safeVal = val.abs() < 1e-9 ? 0.0 : val;
        final label = safeVal.toStringAsFixed(decimalPlaces);
        final tp = TextPainter(
          text: TextSpan(
            text: i == tickCount ? '$label $unit' : label,
            style: yTextStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: yLabelW - 2);
        tp.paint(canvas, Offset(2, y - tp.height / 2));
      }
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(padL - 1, padT, visibleChartW + 2, chartH));

    final paintLine = Paint()
      ..color = color
      ..strokeWidth = large ? 2.5 : 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(padL, padT, visibleChartW, chartH));

    final path = Path();
    final fillPath = Path();

    final segments = <List<Offset>>[];
    var current = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      if (data[i].isNaN) {
        if (!connectAcrossMissingData && current.isNotEmpty) {
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

      // When enabled for the 24-hour view, join measured points across missing
      // buckets without drawing or inventing sensor values for those gaps.
      for (int i = 1; i < seg.length; i++) {
        path.lineTo(seg[i].dx, seg[i].dy);
        fillPath.lineTo(seg[i].dx, seg[i].dy);
      }

      fillPath.lineTo(seg.last.dx, padT + chartH);
      fillPath.close();
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paintLine);

    final dotPaint = Paint()..color = color;
    final dotBorder = Paint()..color = Colors.white;
    for (int i = 0; i < data.length; i++) {
      if (data[i].isNaN) continue;
      final x = padL + i * stepX - scrollOffset;
      if (x < visibleLeft - 5 || x > visibleRight + 5) continue;
      final y = padT + chartH - ((data[i] - minVal) / range) * chartH;
      canvas.drawCircle(Offset(x, y), 3, dotBorder);
      canvas.drawCircle(Offset(x, y), 2, dotPaint);
    }

    if (liveMode) {
      final latestIndex = data.lastIndexWhere((value) => !value.isNaN);
      if (latestIndex >= 0) {
        final x = padL + latestIndex * stepX - scrollOffset;
        if (x >= visibleLeft - 5 && x <= visibleRight + 5) {
          final y =
              padT + chartH - ((data[latestIndex] - minVal) / range) * chartH;
          final pulse = livePulse?.value ?? 0.0;
          canvas.drawCircle(
            Offset(x, y),
            3 + (pulse * 5),
            Paint()..color = color.withValues(alpha: 0.24 * (1 - pulse)),
          );
        }
      }
    }

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

      const dashHeight = 4.0;
      const dashSpace = 3.0;
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

    canvas.restore();

    if (showAxis && labels != null && labels!.isNotEmpty) {
      final count = data.length;
      if (count > 0) {
        const angle = -0.55;
        final cosA = cos(angle);
        final sinA = sin(angle);

        // Select actual data indices across the visible window. Labels use
        // evenly spaced screen positions, and the selected index is included
        // so its time also appears on the bottom axis.
        final firstVisibleIndex = count == 1
            ? 0
            : (scrollOffset / stepX).floor().clamp(0, count - 1);
        final lastVisibleIndex = count == 1
            ? 0
            : ((scrollOffset + visibleChartW) / stepX).ceil().clamp(
                0,
                count - 1,
              );
        final visiblePointCount = lastVisibleIndex - firstVisibleIndex + 1;
        final visibleLabelCount = min(8, visiblePointCount);
        final visibleIndices = List<int>.generate(visibleLabelCount, (n) {
          final position = visibleLabelCount > 1
              ? n * (visiblePointCount - 1) / (visibleLabelCount - 1)
              : 0.0;
          return firstVisibleIndex + position.round();
        });
        final selected = selectedIndex;
        if (selected != null &&
            selected >= firstVisibleIndex &&
            selected <= lastVisibleIndex &&
            !visibleIndices.contains(selected) &&
            visibleIndices.length > 2) {
          // Make the selected point's exact time visible on the bottom axis,
          // so it can be compared directly with the black tooltip.
          var replaceAt = 1;
          var nearestDistance = (visibleIndices[replaceAt] - selected).abs();
          for (var i = 2; i < visibleIndices.length - 1; i++) {
            final distance = (visibleIndices[i] - selected).abs();
            if (distance < nearestDistance) {
              nearestDistance = distance;
              replaceAt = i;
            }
          }
          visibleIndices[replaceAt] = selected;
          visibleIndices.sort();
        }
        final labelPainters = <TextPainter>[];
        final labelExtents = <double>[];
        for (final idx in visibleIndices) {
          final tp = TextPainter(
            text: TextSpan(text: labels![idx], style: xTextStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          labelPainters.add(tp);
          labelExtents.add(tp.width * cosA.abs() + tp.height * sinA.abs());
        }
        final firstPointX = padL + visibleIndices.first * stepX - scrollOffset;
        final lastPointX = padL + visibleIndices.last * stepX - scrollOffset;
        // Keep the last rotated timestamp inside the card, with its visible
        // right edge ending at the final plotted point. Spread the anchors
        // evenly between the first point and that safe endpoint.
        final firstLabelX = max(visibleLeft - 8.0, firstPointX - 8.0);
        final lastLabelX = max(firstLabelX, lastPointX - labelExtents.last);
        final labelSpacing = visibleIndices.length > 1
            ? (lastLabelX - firstLabelX) / (visibleIndices.length - 1)
            : 0.0;
        for (var i = 0; i < visibleIndices.length; i++) {
          final tp = labelPainters[i];
          final labelX = firstLabelX + labelSpacing * i;
          // Keep timestamps below the plot and separated from the y-axis
          // bottom tick; this extra offset prevents the labels from touching.
          final anchorY = size.height - padB + (liveMode ? 35.0 : 41.0);
          canvas.save();
          canvas.translate(labelX, anchorY);
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
      oldDelegate.minVal != minVal ||
      oldDelegate.range != range ||
      oldDelegate.color != color ||
      oldDelegate.labels != labels ||
      oldDelegate.unit != unit ||
      oldDelegate.showAxis != showAxis ||
      oldDelegate.large != large ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.thresholdMin != thresholdMin ||
      oldDelegate.thresholdMax != thresholdMax ||
      oldDelegate.scrollOffset != scrollOffset ||
      oldDelegate.virtualWidth != virtualWidth ||
      oldDelegate.connectAcrossMissingData != connectAcrossMissingData ||
      oldDelegate.liveMode != liveMode ||
      oldDelegate.livePulse != livePulse;
}
