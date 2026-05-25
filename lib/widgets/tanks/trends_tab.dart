import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/tank_service.dart';
import 'sampling_tab.dart';

class TrendsTab extends StatefulWidget {
  final VoidCallback? onInfoTap;
  const TrendsTab({super.key, this.onInfoTap});

  @override
  State<TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<TrendsTab> {
  String _activeMetric = 'ABW';

  @override
  void initState() {
    super.initState();
    // Nakikinig sa TankService para mag-update ang UI pag may new data
    TankService.instance.addListener(_handleUpdate);
  }

  @override
  void dispose() {
    TankService.instance.removeListener(_handleUpdate);
    super.dispose();
  }

  void _handleUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!TankService.instance.isInitialized) return _buildEmptyState();

    return SingleChildScrollView(
      key: const ValueKey('trends_content'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          _buildChartContainer(),
          const SizedBox(height: 16),
          _buildMortalityChartContainer(),
          const SizedBox(height: 16),
          GrowthStagePanel(onInfoTap: widget.onInfoTap ?? () {}),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.trending_up_rounded,
              size: 40,
              color: AppColors.primary,
            ),
            const SizedBox(height: 20),
            const Text(
              'No Trend Data',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Initialize the tank inventory to visualize live growth and mortality trends.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.dark.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMortalityChartContainer() {
    final service = TankService.instance;
    // Siguraduhin na may laman kahit 0.0 para sa graph
    final mortalityData = service.mortalityHistory.isEmpty
        ? [0.0]
        : service.mortalityHistory;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Mortality Trend',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 160,
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: _BarChartPainter(
                      mortalityData,
                      AppColors.critical,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: mortalityData.length == 1
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    mortalityData.length,
                    (i) => Text(
                      i == 0 ? 'Init' : 'W$i',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartContainer() {
    final service = TankService.instance;
    final history = service.samplingHistory;

    final data = <double>[];
    if (_activeMetric == 'ABW') {
      data.add(service.initialWeight);
      data.addAll(history.map((e) => e.abw));
    } else {
      data.add(service.initialLength);
      data.addAll(history.map((e) => e.avgLength));
    }

    final maxVal = data.reduce(max);
    final minVal = data.reduce(min);
    final unit = _activeMetric == 'ABW' ? 'g' : 'cm';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                  Text(
                    _activeMetric == 'ABW'
                        ? 'Average Weight'
                        : 'Average Length',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                ],
              ),
              _buildToggle(),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${maxVal.toStringAsFixed(1)} $unit',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                    Text(
                      '${((maxVal + minVal) / 2).toStringAsFixed(1)} $unit',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                    Text(
                      '${minVal.toStringAsFixed(1)} $unit',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          painter: _LineChartPainter(data, AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: data.length == 1
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          data.length,
                          (i) => Text(
                            i == 0 ? 'Init' : 'W$i',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.darkWith(0.4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [_toggleBtn('ABW', 'ABW'), _toggleBtn('ABL', 'ABL')],
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
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final maxVal = data.reduce(max);
    final minVal = data.reduce(min);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final xStep = data.length > 1 ? size.width / (data.length - 1) : 0.0;
    final path = Path();

    for (int i = 0; i < data.length; i++) {
      final x = data.length == 1 ? size.width / 2 : i * xStep;
      final y = size.height - ((data[i] - minVal) / range * size.height);
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
      canvas.drawCircle(Offset(x, y), 5, dotPaint);
    }
    if (data.length > 1) canvas.drawPath(path, paint);
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
    final maxVal = data.reduce(max) == 0 ? 1.0 : data.reduce(max);
    final barWidth = size.width / (data.length * 2);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final x = data.length == 1
          ? (size.width / 2) - (barWidth / 2)
          : i * (barWidth * 2);
      final barHeight = (data[i] / maxVal) * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - barHeight, barWidth, barHeight),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) => true;
}
