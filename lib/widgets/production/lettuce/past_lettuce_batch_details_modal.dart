import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import '../../../theme/app_colors.dart';
import '../../../models/lettuce_batch.dart';
import '../../../services/lettuce_service.dart';

void showPastLettuceBatchDetailsModal(BuildContext context, LettuceBatch batch) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      return _PastLettuceBatchDetailsContent(batch: batch);
    },
  );
}

class _PastLettuceBatchDetailsContent extends StatefulWidget {
  final LettuceBatch batch;
  const _PastLettuceBatchDetailsContent({required this.batch});

  @override
  State<_PastLettuceBatchDetailsContent> createState() => _PastLettuceBatchDetailsContentState();
}

class _PastLettuceBatchDetailsContentState extends State<_PastLettuceBatchDetailsContent> {
  bool _isLoading = true;
  List<LettuceGrowthEntry> _growthLogs = [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final logs = await LettuceService.instance.getArchivedBatchDetails(widget.batch.batchId);
    if (mounted) {
      setState(() {
        _growthLogs = logs;
        _isLoading = false;
      });
    }
  }

  String _formatShortDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.dark.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.archive_rounded, color: AppColors.success),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Batch ${widget.batch.batchId}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.dark),
                      ),
                      Text(
                        '${_formatShortDate(widget.batch.plantingDate)} \u2192 ${_formatShortDate(widget.batch.harvestDate ?? widget.batch.plantingDate)}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.dark.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.success))
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryCards(),
                        const SizedBox(height: 24),
                        _buildGrowthChart(),
                        const SizedBox(height: 24),
                        _buildLogsList('Growth Logs', _growthLogs),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(child: _buildCard('Planted', '${widget.batch.initialQuantity} pcs', Icons.eco)),
        const SizedBox(width: 12),
        Expanded(child: _buildCard('Harvest', '${widget.batch.harvestedQuantity} pcs', Icons.agriculture)),
        const SizedBox(width: 12),
        Expanded(child: _buildCard('Weight', '${widget.batch.harvestWeightKg?.toStringAsFixed(2) ?? "0"} kg', Icons.scale_rounded)),
      ],
    );
  }

  Widget _buildCard(String title, String value, IconData icon) {
    const color = AppColors.success;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.dark.withValues(alpha: 0.5))),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildGrowthChart() {
    if (_growthLogs.isEmpty) return const SizedBox.shrink();

    final data = _growthLogs.map((e) => e.plantHeightCm ?? e.avgLeafSize ?? 0.0).toList();
    final labels = _growthLogs.map((e) => '${e.date.month}/${e.date.day}').toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Growth Trend', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: _buildLineChart(data, labels, 'cm', AppColors.success),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(List<double> data, List<String> labels, String unit, Color color) {
    if (data.length < 2) return const Center(child: Text('Not enough data for chart', style: TextStyle(fontSize: 11)));
    
    final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final maxVal = data.reduce(max);
    final chartMaxY = maxVal > 0 ? (maxVal * 1.15).ceilToDouble() : 1.0;

    return LineChart(
      LineChartData(
        minX: 0, maxX: (data.length - 1).toDouble(),
        minY: 0, maxY: chartMaxY,
        gridData: FlGridData(show: false),
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
                    child: Text(labels[i], style: TextStyle(fontSize: 9, color: AppColors.dark.withValues(alpha: 0.5))),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(String title, List<LettuceGrowthEntry> logs) {
    if (logs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark)),
        const SizedBox(height: 12),
        ...logs.map((log) {
          final parts = <String>[];
          if (log.plantHeightCm != null) parts.add('Ht: ${log.plantHeightCm!.toStringAsFixed(1)}cm');
          return _buildLogItem(
            Icons.eco_rounded, 
            AppColors.success, 
            _formatShortDate(log.date), 
            parts.isNotEmpty ? parts.join(' | ') : 'Growth data',
          );
        }),
      ],
    );
  }

  Widget _buildLogItem(IconData icon, Color color, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark)),
              Text(subtitle, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.dark.withValues(alpha: 0.5))),
            ],
          ),
        ],
      ),
    );
  }
}
