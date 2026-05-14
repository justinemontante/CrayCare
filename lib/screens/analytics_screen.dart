import 'dart:math';
import 'package:flutter/material.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _activeFilter = '24h';
  bool _showCustom = false;

  final Map<String, List<double>> _data = {};
  final Map<String, List<String>> _labels = {};
  String _insight = 'Loading insights...';

  final _rng = Random(42);

  @override
  void initState() {
    super.initState();
    _generateData('24h');
  }

  void _generateData(String range) {
    int pts;
    if (range == '24h') pts = 144;
    else if (range == '7d') pts = 7;
    else pts = 10;

    final now = DateTime.now();
    List<String> labels;
    if (range == '24h') {
      labels = List.generate(pts, (i) {
        final d = now.subtract(Duration(minutes: (pts - 1 - i) * 10));
        final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
        final ampm = d.hour >= 12 ? 'PM' : 'AM';
        return '${h}:${d.minute.toString().padLeft(2, '0')} $ampm';
      });
    } else {
      labels = List.generate(pts, (i) {
        final days = range == '7d' ? (pts - 1 - i) : (pts - 1 - i) * 3;
        final d = now.subtract(Duration(days: days));
        return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]
            + ' ${d.day}';
      });
    }

    _labels[range] = labels;

    final seeds = {
      'temp': { 'min': 22.0, 'max': 32.0 },
      'ph':   { 'min': 6.5,  'max': 9.0 },
      'do':   { 'min': 2.5,  'max': 7.0 },
      'turb': { 'min': 10.0, 'max': 70.0 },
      'waterlevel': { 'min': 60.0, 'max': 140.0 },
    };

    seeds.forEach((key, bounds) {
      _data['$key-$range'] = List.generate(pts, (_) {
        return (bounds['min']! + _rng.nextDouble() * (bounds['max']! - bounds['min']!));
      });
    });

    _updateInsight(range);
  }

  void _updateInsight(String range) {
    final d = _getData('temp', range);
    final peakTemp = d.isEmpty ? 0.0 : d.reduce(max);
    final peakTurb = _getData('turb', range).isEmpty ? 0.0 : _getData('turb', range).reduce(max);
    final minDo = _getData('do', range).isEmpty ? 0.0 : _getData('do', range).reduce(min);
    final minWl = _getData('waterlevel', range).isEmpty ? 0.0 : _getData('waterlevel', range).reduce(min);
    final maxWl = _getData('waterlevel', range).isEmpty ? 0.0 : _getData('waterlevel', range).reduce(max);

    String text = 'Peak temperature reached ${peakTemp.toStringAsFixed(1)}°C. ';
    if (peakTurb > 50) text += 'Turbidity spiked to ${peakTurb.toStringAsFixed(0)} NTU — check filtration. ';
    if (minDo < 3.5) text += 'DO dropped to ${minDo.toStringAsFixed(1)} mg/L — aerator may have triggered. ';
    if (minWl < 60) text += 'Water level dropped to ${minWl.toStringAsFixed(0)} cm — low water warning. ';
    if (maxWl > 140) text += 'Water level peaked at ${maxWl.toStringAsFixed(0)} cm — flood risk.';

    setState(() => _insight = text);
  }

  List<double> _getData(String key, String range) {
    return _data['$key-$range'] ?? [];
  }

  double _calc(List<double> data, double Function(List<double>) fn) {
    return data.isEmpty ? 0.0 : fn(data);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInsightCard(),
            const SizedBox(height: 10),
            _buildFilterRow(),
            if (_showCustom) _buildCustomDateRow(),
            const SizedBox(height: 10),
            _buildChartCard(context,
              title: 'Temperature', iconPath: 'assets/images/temperature.png',
              chartKey: 'temp',
            ),
            _buildChartCard(context,
              title: 'pH Level', iconPath: 'assets/images/pH.png',
              chartKey: 'ph',
            ),
            _buildChartCard(context,
              title: 'Dissolved O\u2082', iconPath: 'assets/images/DO.png',
              chartKey: 'do',
            ),
            _buildChartCard(context,
              title: 'Turbidity', iconPath: 'assets/images/Turbidity.png',
              chartKey: 'turb',
            ),
            _buildChartCard(context,
              title: 'Water Level', iconPath: 'assets/images/waterLevel.png',
              chartKey: 'waterlevel',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1FA5A5).withValues(alpha: 0.08),
        border: Border.all(color: const Color(0xFF1FA5A5).withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 16, color: const Color(0xFF1FA5A5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _insight,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF0B3C49), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Row(
      children: [
        _buildFilterBtn('24H', '24h'),
        _buildFilterBtn('7 Days', '7d'),
        _buildFilterBtn('30 Days', '30d'),
        _buildFilterBtn('Custom', 'custom'),
      ],
    );
  }

  Widget _buildFilterBtn(String label, String value) {
    final isActive = _activeFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (value == 'custom') {
            setState(() => _showCustom = !_showCustom);
          } else {
            setState(() {
              _activeFilter = value;
              _showCustom = false;
              _generateData(value);
            });
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1FA5A5) : Colors.white,
            border: Border.all(color: const Color(0xFF0B3C49).withValues(alpha: 0.15), width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: isActive ? Colors.white : const Color(0xFF0B3C49).withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDateRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF0B3C49).withValues(alpha: 0.15), width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('May 1, 2026', style: TextStyle(fontSize: 10, color: Color(0xFF0B3C49))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('to', style: TextStyle(fontSize: 10, color: const Color(0xFF0B3C49).withValues(alpha: 0.5))),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF0B3C49).withValues(alpha: 0.15), width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('May 15, 2026', style: TextStyle(fontSize: 10, color: Color(0xFF0B3C49))),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _generateData('custom'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1FA5A5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Apply', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, {
    required String title,
    required String iconPath,
    required String chartKey,
  }) {
    final data = _getData(chartKey, _activeFilter);
    final avg = data.isEmpty ? '--' : _calc(data, (d) => d.reduce((a, b) => a + b) / d.length).toStringAsFixed(1);
    final mn = data.isEmpty ? '--' : _calc(data, (d) => d.reduce(min)).toStringAsFixed(1);
    final mx = data.isEmpty ? '--' : _calc(data, (d) => d.reduce(max)).toStringAsFixed(1);
    final unit = _unitFor(chartKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _showChartModal(context, title: title, chartKey: chartKey, unit: unit),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFF0B3C49).withValues(alpha: 0.1), width: 1.5),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: const Color(0xFF0B3C49).withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(10)),
                        child: Image.asset(iconPath, width: 18, height: 18),
                      ),
                      const SizedBox(width: 6),
                      Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49))),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Min: $mn', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF1FA5A5))),
                      const SizedBox(width: 6),
                      Text('Avg: $avg', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF1FA5A5))),
                      const SizedBox(width: 6),
                      Text('Max: $mx', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF1FA5A5))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1FA5A5).withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: data.isEmpty
                    ? Center(child: Text('No data', style: TextStyle(fontSize: 10, color: const Color(0xFF0B3C49).withValues(alpha: 0.2))))
                    : _buildMiniChart(context, data, _colorFor(chartKey), title, unit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChart(BuildContext context, List<double> data, Color color, String title, String unit) {
    if (data.isEmpty) return const SizedBox.shrink();
    final labels = _labels[_activeFilter] ?? [];

    return _ChartWithTooltip(
      data: data,
      color: color,
      unit: unit,
      labels: labels,
      height: 180,
    );
  }

  Color _colorFor(String key) {
    switch (key) {
      case 'temp': return const Color(0xFFf59e0b);
      case 'ph': return const Color(0xFF1FA5A5);
      case 'do': return const Color(0xFF52c283);
      case 'turb': return const Color(0xFFE63946);
      case 'waterlevel': return const Color(0xFF1FA5A5);
      default: return const Color(0xFF1FA5A5);
    }
  }

  String _unitFor(String key) {
    switch (key) {
      case 'temp': return '\u00B0C';
      case 'ph': return 'pH';
      case 'do': return 'mg/L';
      case 'turb': return 'NTU';
      case 'waterlevel': return 'cm';
      default: return '';
    }
  }

  void _showChartModal(BuildContext context, {
    required String title,
    required String chartKey,
    required String unit,
  }) {
    final data = _getData(chartKey, _activeFilter);
    final labels = _labels[_activeFilter] ?? [];
    final color = _colorFor(chartKey);

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$title ($unit)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49))),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(color: const Color(0xFF0B3C49).withValues(alpha: 0.08), shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 13, color: Color(0xFF0B3C49)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (data.isNotEmpty && labels.isNotEmpty)
                  Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1FA5A5).withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _ChartWithTooltip(
                        data: data,
                        color: color,
                        unit: unit,
                        labels: labels,
                        large: true,
                        height: 220,
                      ),
                    ),
                  )
                else
                  Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1FA5A5).withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Text('No data available', style: TextStyle(fontSize: 11, color: const Color(0xFF0B3C49).withValues(alpha: 0.3)))),
                  ),
              ],
            ),
          ),
        );
      },
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

  _LineChartPainter(this.data, this.minVal, this.range, this.color, {
    this.labels,
    this.unit = '',
    this.showAxis = false,
    this.large = false,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const labelH = 18.0;
    final yLabelW = large ? 42.0 : 36.0;
    final padL = showAxis ? yLabelW : 4.0;
    final padR = 4.0;
    final padT = 8.0;
    final padB = showAxis ? labelH : 4.0;

    final chartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;
    if (chartW <= 0 || chartH <= 0) return;

    final maxVal = minVal + range;
    final textStyle = TextStyle(
      color: const Color(0xFF0B3C49).withValues(alpha: 0.53),
      fontSize: large ? 8 : 7,
      fontWeight: FontWeight.w500,
    );

    // Y-axis grid lines + labels
    if (showAxis) {
      final gridPaint = Paint()
        ..color = const Color(0xFF0B3C49).withValues(alpha: 0.05)
        ..strokeWidth = 1;

      final tickCount = large ? 5 : 3;
      for (int i = 0; i <= tickCount; i++) {
        final y = padT + (chartH * i / tickCount);
        canvas.drawLine(Offset(padL, y), Offset(size.width - padR, y), gridPaint);

        final val = maxVal - (range * i / tickCount);
        final label = val.toStringAsFixed(val.abs() >= 10 ? 0 : 1);
        final tp = TextPainter(
          text: TextSpan(text: i == tickCount ? '$label $unit' : label, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: yLabelW - 4);
        tp.paint(canvas, Offset(padL - yLabelW + 2, y - tp.height / 2));
      }
    }

    // X-axis labels
    if (showAxis && labels != null && labels!.isNotEmpty) {
      final xLabels = _getXLabels();
      for (final xl in xLabels) {
        final x = padL + (chartW * xl.index / (data.length - 1));
        final tp = TextPainter(
          text: TextSpan(text: xl.text, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 50);
        tp.paint(canvas, Offset(x - tp.width / 2, size.height - labelH + 2));
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
    final dotStep = large ? 1 : (data.length > 50 ? data.length ~/ 15 : 1);

    for (int i = 0; i < data.length; i += dotStep) {
      final x = padL + i * stepX;
      final y = padT + chartH - ((data[i] - minVal) / range) * chartH;
      canvas.drawCircle(Offset(x, y), large ? 3 : 2.5, dotBorder);
      canvas.drawCircle(Offset(x, y), large ? 2 : 1.5, dotPaint);
    }

    // Selected point highlight
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < data.length) {
      final sx = padL + selectedIndex! * stepX;
      final sy = padT + chartH - ((data[selectedIndex!] - minVal) / range) * chartH;
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(sx, padT), Offset(sx, padT + chartH), linePaint);
      final hlSize = (large ? 3.0 : 2.5) + 3;
      canvas.drawCircle(Offset(sx, sy), hlSize, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(sx, sy), hlSize - 1, Paint()..color = color);
      canvas.drawCircle(Offset(sx, sy), hlSize - 2, Paint()..color = Colors.white);
    }
  }

  List<_XLabel> _getXLabels() {
    if (labels == null || labels!.isEmpty) return [];
    final count = data.length;
    if (count <= 1) return [_XLabel(labels![0], 0)];
    if (large) {
      final step = count > 48 ? count ~/ 7 : (count ~/ 6).clamp(1, count - 1);
      return [0, step, step * 2, step * 3, step * 4, step * 5, count - 1]
          .where((i) => i < count)
          .map((i) => _XLabel(labels![i], i))
          .toList();
    }
    if (count <= 5) {
      return List.generate(count, (i) => _XLabel(labels![i], i));
    }
    final step = count ~/ 4;
    return [0, step, step * 2, step * 3, count - 1]
        .map((i) => _XLabel(labels![i], i.clamp(0, count - 1)))
        .toList();
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.large != large || oldDelegate.selectedIndex != selectedIndex;
}

class _ChartWithTooltip extends StatefulWidget {
  final List<double> data;
  final Color color;
  final String unit;
  final List<String>? labels;
  final bool large;
  final double height;

  const _ChartWithTooltip({
    required this.data,
    required this.color,
    required this.unit,
    this.labels,
    this.large = false,
    required this.height,
  });

  @override
  State<_ChartWithTooltip> createState() => _ChartWithTooltipState();
}

class _ChartWithTooltipState extends State<_ChartWithTooltip> {
  int? _selectedIndex;

  void _handleTap(TapDownDetails details) {
    final data = widget.data;
    if (data.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final width = renderBox.size.width;

    final yLabelW = widget.large ? 42.0 : 36.0;
    final padL = yLabelW;
    final padR = 4.0;
    final chartW = width - padL - padR;
    if (chartW <= 0) return;

    final tapX = details.localPosition.dx;
    final stepX = data.length > 1 ? chartW / (data.length - 1) : 0.0;
    final index = ((tapX - padL) / stepX).round().clamp(0, data.length - 1);

    setState(() {
      _selectedIndex = _selectedIndex == index ? null : index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) return const SizedBox.shrink();

    final minVal = widget.data.reduce(min);
    final maxVal = widget.data.reduce(max);
    final range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: _handleTap,
          child: Stack(
            children: [
              CustomPaint(
                painter: _LineChartPainter(
                  widget.data, minVal, range, widget.color,
                  labels: widget.labels,
                  unit: widget.unit,
                  showAxis: true,
                  large: widget.large,
                  selectedIndex: _selectedIndex,
                ),
                size: Size(constraints.maxWidth, widget.height),
              ),
              if (_selectedIndex != null && _selectedIndex! < widget.data.length)
                Positioned(
                  top: 3,
                  left: 8,
                  child: _buildTooltip(_selectedIndex!),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTooltip(int index) {
    final val = widget.data[index];
    final label = (widget.labels != null && index < widget.labels!.length)
        ? widget.labels![index]
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: widget.color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: ${val.toStringAsFixed(1)} ${widget.unit}',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: widget.color,
        ),
      ),
    );
  }
}

class _XLabel {
  final String text;
  final int index;
  const _XLabel(this.text, this.index);
}
