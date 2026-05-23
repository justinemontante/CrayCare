import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/tank_service.dart';

class TrendsTab extends StatefulWidget {
  const TrendsTab({super.key});

  @override
  State<TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<TrendsTab> {
  String _activeMetric = 'ABW'; // ABW or ABL

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          _buildChartContainer(),
          const SizedBox(height: 16),
          _buildMortalityChartContainer(),
        ],
      ),
    );
  }

  Widget _buildMortalityChartContainer() {
    // Simulated mortality data per week
    final mortalityData = [2.0, 1.0, 0.0, 3.0, 1.0, 2.0, 0.0];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.darkWith(0.05)),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Mortality Trend',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _BarChartPainter(mortalityData, AppColors.critical),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartContainer() {
    final service = TankService.instance;
    final history = service.samplingHistory;
    
    // Create data points starting with baseline, followed by sampling history
    final data = <double>[];
    if (_activeMetric == 'ABW') {
      data.add(service.initialWeight);
      data.addAll(history.map((e) => e.abw));
    } else {
      data.add(service.initialLength);
      data.addAll(history.map((e) => e.avgLength));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.darkWith(0.05)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Growth Trend',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _activeMetric == 'ABW' ? 'Average Body Weight' : 'Average Body Length',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.dark.withValues(alpha: 0.5)),
                  ),
                ],
              ),
              _buildToggle(),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: data.length > 1
                ? CustomPaint(
                    painter: _LineChartPainter(data, AppColors.primary),
                    child: Container(),
                  )
                : Center(
                    child: Text(
                      'Not enough sampling data.',
                      style: TextStyle(color: AppColors.darkWith(0.4)),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.show_chart, size: 16, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  'Weekly Growth Rate: +5.2 g/week',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.success),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: AppColors.darkWith(0.05), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          _toggleBtn('ABW', 'ABW'),
          _toggleBtn('ABL', 'ABL'),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, String value) {
    final isSelected = _activeMetric == value;
    return GestureDetector(
      onTap: () => setState(() => _activeMetric = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: isSelected ? AppColors.primary : AppColors.darkWith(0.4),
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  _LineChartPainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path();
    final maxVal = data.reduce(max);
    final minVal = data.reduce(min);
    final range = maxVal - minVal;
    
    final xStep = size.width / (data.length - 1);
    
    for (int i = 0; i < data.length; i++) {
      final x = i * xStep;
      final y = size.height - ((data[i] - minVal) / (range == 0 ? 1 : range) * size.height);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => true;
}

class _BarChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  _BarChartPainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxVal = data.reduce(max);
    final barWidth = size.width / (data.length * 1.5);
    final gap = barWidth * 0.5;
    
    final paint = Paint()..color = color.withValues(alpha: 0.6)..style = PaintingStyle.fill;
    
    for (int i = 0; i < data.length; i++) {
      final x = i * (barWidth + gap);
      final barHeight = (data[i] / (maxVal == 0 ? 1 : maxVal)) * size.height;
      final rect = Rect.fromLTWH(x, size.height - barHeight, barWidth, barHeight);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) => true;
}
