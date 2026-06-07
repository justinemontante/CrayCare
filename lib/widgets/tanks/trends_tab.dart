import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme/app_colors.dart';
import '../../services/tank_service.dart';
import 'sampling_tab.dart';

class TrendsTab extends StatefulWidget {
  final DateTime lastEdited;
  final VoidCallback? onInfoTap;
  const TrendsTab({super.key, required this.lastEdited, this.onInfoTap});

  @override
  State<TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<TrendsTab> {
  String _activeMetric = 'ABW';

  @override
  void initState() {
    super.initState();
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
            Icon(
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

    final unit = _activeMetric == 'ABW' ? 'g' : 'cm';
    final isAbw = _activeMetric == 'ABW';
    final lineColor = isAbw ? AppColors.primary : const Color(0xFFf59e0b);

    final labels = List.generate(
      data.length,
      (i) => i == 0 ? 'Initial' : 'Week $i',
    );

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
                    isAbw ? 'Average Weight' : 'Average Length',
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
            child: data.length == 1
                ? Center(
                    child: Text(
                      '${data[0].toStringAsFixed(1)} $unit',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: lineColor,
                      ),
                    ),
                  )
                : _buildLineChart(data, lineColor, unit, labels),
          ),
          const SizedBox(height: 12),
          _buildGrowthFooter(data, unit),
        ],
      ),
    );
  }

  Widget _buildLineChart(
      List<double> data, Color color, String unit, List<String> labels) {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: (data.reduce(max) * 1.15).ceilToDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ((data.reduce(max) * 1.15).ceilToDouble()) / 3,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.darkWith(0.04),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i >= 0 && i < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${value.toStringAsFixed(1)} $unit',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                  );
                }
                final mid = (meta.max + meta.min) / 2;
                if ((value - mid).abs() < 0.5) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${value.toStringAsFixed(1)} $unit',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final i = spot.spotIndex;
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)} $unit',
                  TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: '\n${labels[i]}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 4,
                color: color,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthFooter(List<double> data, String unit) {
    if (data.length < 2) {
      return Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 12, color: AppColors.darkWith(0.35)),
          const SizedBox(width: 4),
          Text(
            'Keep sampling to track growth',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.darkWith(0.45),
            ),
          ),
        ],
      );
    }

    final firstVal = data.first;
    final lastVal = data.last;
    final gain = lastVal - firstVal;
    final weekly = gain / (data.length - 1);

    return Row(
      children: [
        if (data.length == 2) ...[
          Text(
            'Total gain: ',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.darkWith(0.45),
            ),
          ),
          Text(
            '+${gain.toStringAsFixed(2)} $unit',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: gain >= 0 ? const Color(0xFF1FA5A5) : AppColors.critical,
            ),
          ),
        ] else ...[
          Text(
            'Total gain: ',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.darkWith(0.45),
            ),
          ),
          Text(
            '+${gain.toStringAsFixed(2)} $unit',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: gain >= 0 ? const Color(0xFF1FA5A5) : AppColors.critical,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Avg weekly: ',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.darkWith(0.45),
            ),
          ),
          Text(
            '+${weekly.toStringAsFixed(2)} $unit',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: weekly >= 0
                  ? const Color(0xFF1FA5A5)
                  : AppColors.critical,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMortalityChartContainer() {
    final service = TankService.instance;
    final entries = service.mortalityHistory;
    final totalMort = service.totalMortality;

    // Group entries by date para iwas multiple bars sa same day
    final dailyMap = <DateTime, int>{};
    for (final e in entries) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      dailyMap[day] = (dailyMap[day] ?? 0) + e.count;
    }
    final dailyEntries = dailyMap.entries
        .map((e) => MortalityEntry(date: e.key, count: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

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
            height: 180,
            child: dailyEntries.isEmpty
                ? Center(
                    child: Text(
                      'No mortality data',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                  )
                : _buildMortalityLineChart(dailyEntries),
          ),
          const SizedBox(height: 12),
          _buildMortalityFooter(service, entries, totalMort),
        ],
      ),
    );
  }

  Widget _buildMortalityFooter(
      TankService service, List<MortalityEntry> entries, int totalMort) {
    final survRate = service.survivalRate;

    return Column(
      children: [
        Row(
          children: [
            Icon(
              totalMort > 0
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline_rounded,
              size: 12,
              color: totalMort > 0
                  ? AppColors.critical
                  : const Color(0xFF52C283),
            ),
            const SizedBox(width: 4),
            Text(
              totalMort > 0
                  ? '$totalMort total mortality'
                  : 'No mortality',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: totalMort > 0
                    ? AppColors.critical
                    : const Color(0xFF52C283),
              ),
            ),
          ],
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              _statChip(
                'Survival',
                '${survRate.toStringAsFixed(1)}%',
                survRate > 80
                    ? const Color(0xFF52C283)
                    : survRate > 50
                        ? const Color(0xFFf59e0b)
                        : AppColors.critical,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 9,
              color: AppColors.darkWith(0.5),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMortalityLineChart(List<MortalityEntry> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final maxVal = entries.map((e) => e.count.toDouble()).reduce(max);
    final effectiveMax = maxVal == 0 ? 1.0 : maxVal;

    final labels = entries.map((e) => _formatMortDate(e.date)).toList();

    final rawStep = (effectiveMax / 4).ceilToDouble();
    final step = rawStep < 1 ? 1.0 : rawStep;
    final chartMaxY = step * 4;
    final yLabels = [0.0, step, step * 2, step * 3, step * 4];

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: chartMaxY,
        minY: 0,
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i >= 0 && i < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 8,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: step,
              getTitlesWidget: (value, meta) {
                final v = value.toInt();
                if (yLabels.contains(value)) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '$v',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.darkWith(0.4),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final val = rod.toY;
              final date = labels[group.x];
              return BarTooltipItem(
                '${val.toInt()} ${val == 1 ? 'mortality' : 'mortalities'}',
                TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                children: [
                  TextSpan(
                    text: '\n$date',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        barGroups: List.generate(entries.length, (i) {
          final val = entries[i].count;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: val.toDouble(),
                color: val > 0 ? AppColors.critical : const Color(0xFF52C283),
                width: 20,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  String _formatMortDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
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
