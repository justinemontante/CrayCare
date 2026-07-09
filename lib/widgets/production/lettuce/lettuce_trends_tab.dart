import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../theme/app_colors.dart';
import '../../../services/lettuce_service.dart';
import '../../../models/lettuce_batch.dart';

class LettuceTrendsTab extends StatefulWidget {
  final DateTime lastEdited;

  const LettuceTrendsTab({
    super.key,
    required this.lastEdited,
  });

  @override
  State<LettuceTrendsTab> createState() => _LettuceTrendsTabState();
}

class _LettuceTrendsTabState extends State<LettuceTrendsTab> {

  @override
  void initState() {
    super.initState();
    LettuceService.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    LettuceService.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = LettuceService.instance;

    if (!service.isInitialized) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          _buildGrowthChartContainer(service),
          const SizedBox(height: 10),
          _buildMortalityChartContainer(service),
          const SizedBox(height: 10),
          _buildHarvestHistorySection(service),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildGrowthChartContainer(LettuceService service) {
    final logs = service.growthHistory.where((e) => e.plantHeightCm != null).toList();
    final data = logs.map((e) => e.plantHeightCm!).toList();
    final unit = 'cm';

    return Container(
      width: double.infinity,
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
            children: [
              const Icon(Icons.show_chart, size: 16, color: AppColors.success),
              const SizedBox(width: 8),
              const Text(
                'Growth Height',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
              ),
              const Spacer(),
              Text(
                '${data.length} logged',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Plant height over time',
              style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.4)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: data.isEmpty
                ? Center(
                    child: Text(
                      'No growth data yet',
                      style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.4)),
                    ),
                  )
                : data.length == 1
                    ? Center(
                        child: Text(
                          '${data[0].toStringAsFixed(1)} $unit',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.success),
                        ),
                      )
                    : _buildLineChart(logs, data, unit),
          ),
          if (data.length >= 2) ...[
            const SizedBox(height: 12),
            _buildGrowthFooter(data, unit),
          ],
        ],
      ),
    );
  }

  Widget _buildLineChart(List<LettuceGrowthEntry> logs, List<double> data, String unit) {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final maxVal = data.isNotEmpty ? data.reduce(max) : 0.0;
    final chartMaxY = maxVal > 0 ? (maxVal * 1.15).ceilToDouble() : 1.0;

    final labels = logs.map((e) => _formatShortDate(e.date)).toList();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: chartMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: chartMaxY / 3,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.darkWith(0.04),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: data.length > 8
                  ? (data.length / 4).ceilToDouble()
                  : (data.length > 5 ? 2.0 : 1.0),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i >= 0 && i < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: TextStyle(fontSize: 8, color: AppColors.darkWith(0.4)),
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
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${value.toStringAsFixed(1)} $unit',
                      style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.4)),
                    ),
                  );
                }
                final mid = (meta.max + meta.min) / 2;
                if ((value - mid).abs() < 0.5) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${value.toStringAsFixed(1)} $unit',
                      style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.4)),
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
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  children: [
                    TextSpan(
                      text: '\n${labels[i]}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w500),
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
            color: AppColors.success,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 4,
                color: AppColors.success,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.success.withValues(alpha: 0.13),
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
          Icon(Icons.info_outline_rounded, size: 12, color: AppColors.darkWith(0.35)),
          const SizedBox(width: 4),
          Text(
            'Keep logging growth to track progress',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.45)),
          ),
        ],
      );
    }

    final firstVal = data.first;
    final lastVal = data.last;
    final gain = lastVal - firstVal;
    final avgPerEntry = gain / (data.length - 1);

    return Row(
      children: [
        Icon(Icons.trending_up_rounded, size: 14, color: gain >= 0 ? AppColors.success : AppColors.critical),
        const SizedBox(width: 4),
        Text(
          'Total: ',
          style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.45)),
        ),
        Text(
          '${lastVal.toStringAsFixed(1)} $unit',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success),
        ),
        const SizedBox(width: 16),
        Text(
          'Growth: ',
          style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.45)),
        ),
        Text(
          '+${gain.toStringAsFixed(1)} $unit',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success),
        ),
        if (data.length > 2) ...[
          const SizedBox(width: 16),
          Text(
            'Avg: ',
            style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.45)),
          ),
          Text(
            '+${avgPerEntry.toStringAsFixed(2)} $unit',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success),
          ),
        ],
      ],
    );
  }

  Widget _buildMortalityChartContainer(LettuceService service) {
    final entries = service.mortalityHistory;

    final dailyMap = <DateTime, int>{};
    for (final e in entries) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      dailyMap[day] = (dailyMap[day] ?? 0) + e.count;
    }
    final dailyEntries = dailyMap.entries
        .map((e) => _MortEntry(date: e.key, count: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final totalMort = entries.fold(0, (sum, e) => sum + e.count);

    return Container(
      width: double.infinity,
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
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.critical),
                const SizedBox(width: 6),
                const Text(
                  'Plant Loss Trend',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: dailyEntries.isEmpty
                ? Center(
                    child: Text(
                      'No plant loss data',
                      style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.4)),
                    ),
                  )
                : _buildMortalityBarChart(dailyEntries),
          ),
          if (dailyEntries.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildMortalityFooter(totalMort),
          ],
        ],
      ),
    );
  }

  Widget _buildMortalityBarChart(List<_MortEntry> entries) {
    final maxVal = entries.map((e) => e.count.toDouble()).reduce(max);
    final effectiveMax = maxVal == 0 ? 1.0 : maxVal;

    final labels = entries.map((e) => _formatShortDate(e.date)).toList();

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
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                      style: TextStyle(fontSize: 8, color: AppColors.darkWith(0.4)),
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
                      style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.4)),
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
                '${val.toInt()} ${val == 1 ? 'plant lost' : 'plants lost'}',
                TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                children: [
                  TextSpan(
                    text: '\n$date',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w500),
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
                color: val > 0 ? AppColors.critical : AppColors.success,
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

  Widget _buildMortalityFooter(int totalMort) {
    return Row(
      children: [
        Icon(
          totalMort > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
          size: 12,
          color: totalMort > 0 ? AppColors.critical : const Color(0xFF52C283),
        ),
        const SizedBox(width: 4),
        Text(
          totalMort > 0 ? '$totalMort total plant loss' : 'No plant loss',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: totalMort > 0 ? AppColors.critical : const Color(0xFF52C283),
          ),
        ),
      ],
    );
  }

  Widget _buildHarvestHistorySection(LettuceService service) {
    final history = service.harvestHistory;
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.archive_outlined, size: 14, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'Harvest History',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.dark),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: history.length,
            separatorBuilder: (context, index) => Divider(color: AppColors.darkWith(0.06), height: 16),
            itemBuilder: (context, index) {
              final batch = history[index];
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.batchId,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.dark),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatShortDate(batch.plantingDate)} \u2192 ${_formatShortDate(batch.harvestDate ?? DateTime.now())}',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.4)),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${batch.harvestedQuantity} / ${batch.initialQuantity} pcs',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.dark),
                      ),
                          if (batch.harvestWeightKg != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${batch.harvestWeightKg!.toStringAsFixed(2)} kg',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.success),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _growthChip(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.isNotEmpty ? '$value $label' : value,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  String _formatShortDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minuteStr $period';
  }
}

class _MortEntry {
  final DateTime date;
  final int count;
  const _MortEntry({required this.date, required this.count});
}
