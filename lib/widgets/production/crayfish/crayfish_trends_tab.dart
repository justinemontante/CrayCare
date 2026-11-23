import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../theme/app_colors.dart';
import '../../../services/tank_service.dart';
import '../../../services/feeder_service.dart';

class TrendsTab extends StatefulWidget {
  const TrendsTab({super.key});

  @override
  State<TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<TrendsTab> {
  String _activeMetric = 'ABW';
  String _feedViewMetric = 'Daily';

  // Shared paddings: the pinned Y-axis labels and the scrollable chart must
  // use the same top/bottom plot insets or the labels drift off their ticks.
  static const double _kTopReserved = 16.0;
  static const double _kBottomReserved = 44.0;
  static const double _kBottomLabelSpace = 4.0;

  /// fl_chart ignores [reservedSize] when [showTitles] is false, so an
  /// "invisible" axis must still have showTitles: true to reserve the same
  /// plot area as the chart it is pinned beside.
  AxisTitles _reservedOnly(double size) => AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: size,
          getTitlesWidget: (_, _) => const SizedBox.shrink(),
        ),
      );

  /// Rounds max/tickCount up to a readable step (1, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10).
  double _niceYStep(double maxValue, {int tickCount = 4}) {
    final raw = maxValue / tickCount;
    if (raw <= 0) return 1.0;
    final magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
    final normalized = raw / magnitude;
    const niceSteps = <double>[1, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10];
    final nice = niceSteps.firstWhere(
      (s) => s >= normalized,
      orElse: () => 10,
    );
    return nice * magnitude;
  }

  @override
  void initState() {
    super.initState();
    TankService.instance.addListener(_handleUpdate);
    FeederService.instance.addListener(_handleUpdate);
  }

  @override
  void dispose() {
    TankService.instance.removeListener(_handleUpdate);
    FeederService.instance.removeListener(_handleUpdate);
    super.dispose();
  }

  void _handleUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('trends_content'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          if (!TankService.instance.isInitialized)
            _buildEmptyState()
          else ...[
            _buildChartContainer(),
            const SizedBox(height: 16),
            _buildBiomassChartContainer(),
            const SizedBox(height: 16),
            _buildFeedIntakeChartContainer(),
            const SizedBox(height: 16),
            _buildMortalityChartContainer(),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const SizedBox.shrink();
  }

  Widget _pinnedScrollableChart({
    required int pointCount,
    required double height,
    required double yAxisWidth,
    required Widget yAxis,
    required Widget chart,
    double minPointSpacing = 58.0,
    double horizontalPadding = 10.0,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - yAxisWidth;
        final baseWidth = available - (horizontalPadding * 2);
        final contentWidth = pointCount <= 1
            ? (baseWidth > 0 ? baseWidth : 0.0)
            : (pointCount - 1) * minPointSpacing;
        final chartWidth = max(contentWidth, baseWidth > 0 ? baseWidth : 0.0);
        final totalScrollWidth = chartWidth + (horizontalPadding * 2);
        final needsScroll = pointCount > 1 && totalScrollWidth > available;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: yAxisWidth,
              height: height,
              child: yAxis,
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: needsScroll
                    ? const BouncingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: SizedBox(
                  width: chartWidth,
                  height: height,
                  child: chart,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFixedYAxis({
    required double chartMaxY,
    required double interval,
    required String unit,
    required double width,
    required double height,
    required double topReservedSize,
    required double bottomReservedSize,
    int decimalPlaces = 1,
    List<double>? customYLabels,
  }) {
    // Draw the labels ourselves at the exact plot area of the sibling chart
    // (top/bottom reserved sizes match). This avoids fl_chart's axis-padding
    // quirks and guarantees every label lines up with its gridline/data point.
    final values = <double>[];
    if (customYLabels != null) {
      values.addAll(customYLabels);
    } else {
      values.add(0);
      // Guard against a zero/negative interval to avoid an endless loop.
      final safeInterval = interval > 0 ? interval : (chartMaxY > 0 ? chartMaxY : 1.0);
      var v = safeInterval;
      while (v <= chartMaxY + 0.0001) {
        values.add(v);
        v += safeInterval;
      }
    }

    final plotTop = topReservedSize;
    final plotHeight = height - topReservedSize - bottomReservedSize;
    const labelHalfHeight = 7.0;

    return Stack(
      children: values.map((value) {
        final fraction = chartMaxY > 0 ? value / chartMaxY : 0.0;
        final top = plotTop + (1 - fraction) * plotHeight - labelHalfHeight;
        final formatted = decimalPlaces == 0
            ? '${value.toInt()}'
            : value.toStringAsFixed(decimalPlaces);
        final text = unit.isEmpty ? formatted : '$formatted $unit';
        return Positioned(
          top: top,
          left: 0,
          width: width,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.darkWith(0.4),
            ),
          ),
        );
      }).toList(),
    );
  }

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String _formatTrendDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  /// Average weekly change from a least-squares trend line through **every**
  /// sample, not just the first and last. Irregular/noisy sampling no longer
  /// distorts the rate, and two points still reduce to the endpoint slope.
  double? _weeklyRate(List<double> data, List<DateTime> dates) {
    if (data.length < 2 || dates.length != data.length) return null;
    final first = _dateOnly(dates.first);
    final xs = <double>[
      for (final date in dates)
        _dateOnly(date).difference(first).inDays.toDouble(),
    ];
    final xMean = xs.reduce((a, b) => a + b) / xs.length;
    final yMean = data.reduce((a, b) => a + b) / data.length;
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < xs.length; i++) {
      final dx = xs[i] - xMean;
      numerator += dx * (data[i] - yMean);
      denominator += dx * dx;
    }
    if (denominator <= 0) return null;
    return (numerator / denominator) * 7.0;
  }

  Widget _buildChartContainer() {
    final service = TankService.instance;
    final samples = service.samplingHistory.where((e) => !e.isBaseline).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final data = <double>[
      _activeMetric == 'ABW'
          ? service.initialWeight
          : service.initialLengthInches,
      ...samples.map((e) => _activeMetric == 'ABW' ? e.abw : e.avgLengthInches),
    ];
    final dates = <DateTime>[service.stockingDate, ...samples.map((e) => e.date)];

    final unit = _activeMetric == 'ABW' ? 'g' : 'in';
    final isAbw = _activeMetric == 'ABW';
    final lineColor = isAbw ? AppColors.primary : const Color(0xFFf59e0b);
    final labels = <String>[
      'Initial\n${_formatTrendDate(service.stockingDate)}',
      ...samples.map((e) => _formatTrendDate(e.date)),
    ];

    final maxVal = data.isNotEmpty ? data.reduce(max) : 0.0;
    final chartMaxY = maxVal > 0 ? _niceYStep(maxVal) * 4 : 1.0;
    final yInterval = chartMaxY / 4;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: AppShadows.card,
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
                    isAbw
                        ? 'Average Body Weight'
                        : 'Average Body Length',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildToggle(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: _pinnedScrollableChart(
              pointCount: data.length,
              height: 200,
              yAxisWidth: 42,
              yAxis: _buildFixedYAxis(
                chartMaxY: chartMaxY,
                interval: yInterval,
                unit: unit,
                width: 42,
                height: 200,
                topReservedSize: _kTopReserved,
                bottomReservedSize: _kBottomReserved,
                decimalPlaces: isAbw ? 1 : 2,
              ),
              chart: _buildLineChart(
                data, lineColor, unit, labels, chartMaxY, yInterval,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildGrowthFooter(data, dates, unit),
        ],
      ),
    );
  }

  Widget _buildLineChart(List<double> data, Color color, String unit,
      List<String> labels, double chartMaxY, double yInterval) {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        minX: data.length == 1 ? -0.5 : 0,
        maxX: data.length == 1 ? 0.5 : (data.length - 1).toDouble(),
        minY: 0,
        maxY: chartMaxY,
        clipData: const FlClipData.none(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.darkWith(0.04),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: _reservedOnly(_kTopReserved),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _kBottomReserved,
              interval: 1.0,
              getTitlesWidget: (value, meta) {
                // If only 1 spot, only show label at x == 0 to avoid duplicates
                if (data.length == 1 && value != 0) {
                  return const SizedBox.shrink();
                }
                final i = value.toInt();
                if (value == i.toDouble() && i >= 0 && i < labels.length) {
                  return SideTitleWidget(
                    meta: meta,
                    space: _kBottomLabelSpace,
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkWith(0.45),
                        height: 1.15,
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
              reservedSize: 20,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final i = spot.spotIndex;
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(2)} $unit',
                  const TextStyle(
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
              getDotPainter: (spot, percent, barData, index) {
                final text =
                    '${spot.y.toStringAsFixed(unit == 'in' ? 2 : 1)}$unit';
                return _LabelDotPainter(
                  circlePainter: FlDotCirclePainter(
                    radius: 3.5,
                    color: color,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  ),
                  label: text,
                  textColor: color,
                );
              },
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

  Widget _buildGrowthFooter(
      List<double> data, List<DateTime> dates, String unit) {
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

    final gain = data.last - data.first;
    final weekly = _weeklyRate(data, dates);
    final gainText = '${gain >= 0 ? "+" : ""}${gain.toStringAsFixed(2)} $unit';

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text('Total gain: ',
              style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.45))),
          Text(
            gainText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: gain >= 0 ? const Color(0xFF1FA5A5) : AppColors.critical,
            ),
          ),
          if (weekly != null) ...[
            const SizedBox(width: 16),
            Text('Avg weekly: ',
                style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.45))),
            Text(
              '${weekly >= 0 ? "+" : ""}${weekly.toStringAsFixed(2)} $unit/week',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: weekly >= 0 ? const Color(0xFF1FA5A5) : AppColors.critical,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBiomassChartContainer() {
    final service = TankService.instance;
    final samples = service.samplingHistory.where((e) => !e.isBaseline).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final initialBiomass = service.initialWeight > 0
        ? service.initialCount * service.initialWeight / 1000
        : 0.0;
    final data = <double>[
      initialBiomass,
      ...samples.map((e) => e.biomass / 1000),
    ];
    final dates = <DateTime>[service.stockingDate, ...samples.map((e) => e.date)];
    final hasData = data.any((v) => v > 0);
    const unit = 'kg';
    final labels = <String>[
      'Initial\n${_formatTrendDate(service.stockingDate)}',
      ...samples.map((e) => _formatTrendDate(e.date)),
    ];

    final maxVal = data.isNotEmpty ? data.reduce(max) : 0.0;
    final chartMaxY = maxVal > 0 ? _niceYStep(maxVal) * 4 : 1.0;
    final yInterval = chartMaxY / 4;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.monitor_weight_outlined, size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Estimated Biomass',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Biomass = live count × ABW',
              style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.4)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: !hasData
                ? Center(
                    child: Text('No biomass data',
                        style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.4))),
                  )
                : data.length == 1
                    ? Center(
                        child: Text(
                          '${data[0].toStringAsFixed(2)} $unit',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : _pinnedScrollableChart(
                        pointCount: data.length,
                        height: 180,
                        yAxisWidth: 44,
                        yAxis: _buildFixedYAxis(
                          chartMaxY: chartMaxY,
                          interval: yInterval,
                          unit: unit,
                          width: 44,
                          height: 180,
                          topReservedSize: _kTopReserved,
                          bottomReservedSize: _kBottomReserved,
                          decimalPlaces: 1,
                        ),
                        chart: _buildBiomassLineChart(
                          data, unit, labels, chartMaxY, yInterval,
                        ),
                      ),
          ),
          if (hasData) ...[
            const SizedBox(height: 12),
            _buildBiomassFooter(data, dates, unit),
          ],
        ],
      ),
    );
  }

  Widget _buildBiomassLineChart(List<double> data, String unit,
      List<String> labels, double chartMaxY, double yInterval) {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        minX: data.length == 1 ? -0.5 : 0,
        maxX: data.length == 1 ? 0.5 : (data.length - 1).toDouble(),
        minY: 0,
        maxY: chartMaxY,
        clipData: const FlClipData.none(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: AppColors.darkWith(0.04), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: _reservedOnly(_kTopReserved),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _kBottomReserved,
              interval: 1.0,
              getTitlesWidget: (value, meta) {
                // If only 1 spot, only show label at x == 0 to avoid duplicates
                if (data.length == 1 && value != 0) {
                  return const SizedBox.shrink();
                }
                final i = value.toInt();
                if (value == i.toDouble() && i >= 0 && i < labels.length) {
                  return SideTitleWidget(
                    meta: meta,
                    space: _kBottomLabelSpace,
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkWith(0.45),
                        height: 1.15,
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
              reservedSize: 20,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final i = spot.spotIndex;
              return LineTooltipItem(
                '${spot.y.toStringAsFixed(2)} $unit',
                const TextStyle(
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
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: const Color(0xFF1FA5A5),
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final text = '${spot.y.toStringAsFixed(2)}$unit';
                return _LabelDotPainter(
                  circlePainter: FlDotCirclePainter(
                    radius: 3.5,
                    color: const Color(0xFF1FA5A5),
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  ),
                  label: text,
                  textColor: const Color(0xFF1FA5A5),
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF1FA5A5).withValues(alpha: 0.13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiomassFooter(
      List<double> data, List<DateTime> dates, String unit) {
    if (data.length < 2) {
      return Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 12, color: AppColors.darkWith(0.35)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Keep sampling to track biomass',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.darkWith(0.45),
              ),
            ),
          ),
        ],
      );
    }

    final lastVal = data.last;
    final gain = lastVal - data.first;
    final weekly = _weeklyRate(data, dates);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(Icons.trending_up_rounded,
              size: 14,
              color: gain >= 0 ? const Color(0xFF1FA5A5) : AppColors.critical),
          const SizedBox(width: 4),
          Text('Total: ',
              style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.45))),
          Text(
            '${lastVal.toStringAsFixed(2)} $unit',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1FA5A5),
            ),
          ),
          const SizedBox(width: 16),
          Text('Change: ',
              style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.45))),
          Text(
            '${gain >= 0 ? "+" : ""}${gain.toStringAsFixed(2)} $unit',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: gain >= 0 ? const Color(0xFF1FA5A5) : AppColors.critical,
            ),
          ),
          if (weekly != null) ...[
            const SizedBox(width: 16),
            Text('Weekly: ',
                style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.45))),
            Text(
              '${weekly >= 0 ? "+" : ""}${weekly.toStringAsFixed(2)} $unit/week',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: weekly >= 0 ? const Color(0xFF1FA5A5) : AppColors.critical,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --------------- Feed Intake Chart ---------------

  /// The ESP32's servo-cycle estimate is the actual dispensed amount. The
  /// requested dose is only a fallback for legacy logs without that field.
  double _feedGrams(double? estimated, double? requested) =>
      estimated ?? requested ?? 0.0;

  /// Batch timestamps are parsed to device-local DateTimes, but feed logs are
  /// pinned to Asia/Manila. Recover the UTC instant first so both sides use
  /// the same Manila calendar day, even on a device in another timezone.
  DateTime _manilaDate(DateTime instant) {
    final manila = instant.toUtc().add(const Duration(hours: 8));
    return DateTime(manila.year, manila.month, manila.day);
  }

  Widget _buildFeedIntakeChartContainer() {
    final service = TankService.instance;
    final feeder = FeederService.instance;
    final allLogs = feeder.logs;

    // Feeder logs have no batch_id (they live at tanks/{tank}/feeder_logs), so
    // scope them to the selected batch by Manila date: stocking day through
    // harvest/end day, inclusive. Without this, an archived batch's chart and
    // FCR silently use the current batch's feed.
    final batch = service.selectedBatch;
    DateTime? batchStart;
    DateTime? batchEnd;
    if (batch != null) {
      batchStart = _manilaDate(batch.stockingDate);
      final endRaw = batch.harvestDate ?? batch.endedAt;
      if (endRaw != null) {
        batchEnd = _manilaDate(endRaw).add(const Duration(days: 1));
      }
    }

    // Only completed / forced feeds belonging to this batch.
    final completedLogs = allLogs.where((log) {
      if (log.status != 'completed' && log.status != 'forced') return false;
      final start = batchStart;
      if (start == null) return true;
      if (log.timestamp <= 0) return false;
      final day = _manilaDate(
        DateTime.fromMillisecondsSinceEpoch(log.timestamp, isUtc: true),
      );
      if (day.isBefore(start)) return false;
      if (batchEnd != null && !day.isBefore(batchEnd)) return false;
      return true;
    }).toList();

    // Manila offset for timestamp conversion
    const manilaOffset = Duration(hours: 8);

    final List<double> chartData;
    final List<String> chartLabels;

    if (_feedViewMetric == 'Daily') {
      final dailyMap = <DateTime, double>{};
      for (final log in completedLogs) {
        if (log.timestamp <= 0) continue;
        final logDt = DateTime.fromMillisecondsSinceEpoch(
          log.timestamp,
          isUtc: true,
        ).add(manilaOffset);
        final logDay = DateTime(logDt.year, logDt.month, logDt.day);
        final g = _feedGrams(log.estimatedDispensedGrams, log.requestedGrams);
        if (g > 0) {
          dailyMap[logDay] = (dailyMap[logDay] ?? 0.0) + g;
        }
      }
      final sortedEntries = dailyMap.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      chartData = sortedEntries.map((e) => e.value).toList();
      chartLabels = sortedEntries.map((e) => _formatTrendDate(e.key)).toList();
    } else {
      // Weekly buckets from stocking date
      final stockDay = DateTime(
        service.stockingDate.year,
        service.stockingDate.month,
        service.stockingDate.day,
      );
      final now = DateTime.now().toUtc().add(manilaOffset);
      final today = DateTime(now.year, now.month, now.day);

      final weeklyData = <double>[];
      final weekLabels = <String>[];
      var weekStart = stockDay;

      while (!weekStart.isAfter(today)) {
        final weekEnd = weekStart.add(const Duration(days: 7));
        double weekTotal = 0;

        for (final log in completedLogs) {
          if (log.timestamp <= 0) continue;
          final logDt = DateTime.fromMillisecondsSinceEpoch(
            log.timestamp,
            isUtc: true,
          ).add(manilaOffset);
          final logDay = DateTime(logDt.year, logDt.month, logDt.day);

          if (!logDay.isBefore(weekStart) && logDay.isBefore(weekEnd)) {
            weekTotal +=
                _feedGrams(log.estimatedDispensedGrams, log.requestedGrams);
          }
        }

        weeklyData.add(weekTotal);
        weekLabels.add(_formatTrendDate(weekStart));
        weekStart = weekEnd;
      }
      chartData = weeklyData;
      chartLabels = weekLabels;
    }

    final hasData = chartData.any((v) => v > 0);
    final totalFeed = completedLogs.fold<double>(
      0.0,
      (sum, l) => sum + _feedGrams(l.estimatedDispensedGrams, l.requestedGrams),
    );

    // FCR = total feed / biomass gain (grams)
    final samples = service.samplingHistory
        .where((e) => !e.isBaseline)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final initialBiomass = service.initialCount * service.initialWeight;
    final latestBiomass =
        samples.isNotEmpty ? samples.last.biomass : initialBiomass;
    final biomassGain = latestBiomass - initialBiomass;
    final fcr = biomassGain > 0 ? totalFeed / biomassGain : null;

    final maxVal = chartData.isNotEmpty ? chartData.reduce(max) : 0.0;
    final effectiveMax = maxVal == 0 ? 1.0 : maxVal;
    final rawStep = (effectiveMax / 4).ceilToDouble();
    final step = rawStep < 1 ? 1.0 : rawStep;
    final chartMaxY = step * 4;
    final yLabels = [0.0, step, step * 2, step * 3, step * 4];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Feed Intake',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
              ),
              _buildFeedToggle(),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _feedViewMetric == 'Daily'
                  ? 'Daily feed dispensed · grams'
                  : 'Weekly total feed dispensed · grams',
              style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.4)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: !hasData
                ? Center(
                    child: Text('No feeding data yet',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.darkWith(0.4))),
                  )
                : _pinnedScrollableChart(
                    pointCount: chartData.length,
                    height: 180,
                    yAxisWidth: 38,
                    // "Nov 12" needs ~38px at 9.5pt; spaceAround divides this
                    // by pointCount, so leave headroom to avoid label collisions.
                    minPointSpacing: _feedViewMetric == 'Daily' ? 44.0 : 58.0,
                    yAxis: _buildFixedYAxis(
                      chartMaxY: chartMaxY,
                      interval: step,
                      unit: 'g',
                      width: 38,
                      height: 180,
                      topReservedSize: _kTopReserved,
                      bottomReservedSize: _kBottomReserved,
                      decimalPlaces: 0,
                      customYLabels: yLabels,
                    ),
                    chart: _buildFeedIntakeBarChart(chartData, chartLabels, chartMaxY),
                  ),
          ),
          if (hasData) ...[
            const SizedBox(height: 12),
            _buildFeedIntakeFooter(totalFeed, fcr),
          ],
        ],
      ),
    );
  }

  Widget _buildFeedToggle() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _feedToggleBtn('Daily', 'Daily'),
          _feedToggleBtn('Weekly', 'Weekly'),
        ],
      ),
    );
  }

  Widget _feedToggleBtn(String label, String value) {
    final isSelected = _feedViewMetric == value;
    return GestureDetector(
      onTap: () => setState(() => _feedViewMetric = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

  Widget _buildFeedIntakeBarChart(
      List<double> data, List<String> labels, double chartMaxY) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: chartMaxY,
        minY: 0,
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: _reservedOnly(_kTopReserved),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 16,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _kBottomReserved,
              interval: 1.0,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (value == i.toDouble() && i >= 0 && i < labels.length) {
                  return SideTitleWidget(
                    meta: meta,
                    space: _kBottomLabelSpace,
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: 9,
                            color: AppColors.darkWith(0.4))),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 16,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: false,
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 3,
            tooltipBorder: BorderSide.none,
            getTooltipColor: (_) => Colors.transparent,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final val = rod.toY;
              if (val <= 0) return null;
              final text = val % 1 == 0
                  ? '${val.toInt()}g'
                  : '${val.toStringAsFixed(1)}g';
              return BarTooltipItem(
                text,
                const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 8.5,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(data.length, (i) {
          return BarChartGroupData(
            x: i,
            showingTooltipIndicators: data[i] > 0 ? [0] : [],
            barRods: [
              BarChartRodData(
                toY: data[i],
                color: AppColors.primary,
                width: _feedViewMetric == 'Daily' ? 14 : 22,
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

  Widget _buildFeedIntakeFooter(double totalFeed, double? fcr) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.summarize_outlined,
                  size: 13, color: AppColors.darkWith(0.35)),
              const SizedBox(width: 5),
              Text('Total dispensed: ',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.darkWith(0.5))),
              Text(
                '${totalFeed.toStringAsFixed(0)} g',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (fcr != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calculate_outlined,
                    size: 13, color: AppColors.darkWith(0.35)),
                const SizedBox(width: 5),
                Text('Feed Conversion Ratio (FCR): ',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.darkWith(0.5))),
                Text(
                  fcr.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fcr <= 2.0
                        ? const Color(0xFF52C283)
                        : fcr <= 3.0
                            ? const Color(0xFFf59e0b)
                            : AppColors.critical,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMortalityChartContainer() {
    final service = TankService.instance;
    final entries = service.mortalityHistory;
    final totalMort = service.totalMortalityFromHistory;

    final dailyMap = <DateTime, int>{};
    for (final e in entries) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      dailyMap[day] = (dailyMap[day] ?? 0) + e.count;
    }
    final dailyEntries = dailyMap.entries
        .map((e) => MortalityEntry(date: e.key, count: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final maxVal = dailyEntries.isNotEmpty
        ? dailyEntries.map((e) => e.count.toDouble()).reduce(max)
        : 0.0;
    final effectiveMax = maxVal == 0 ? 1.0 : maxVal;
    final rawStep = (effectiveMax / 4).ceilToDouble();
    final step = rawStep < 1 ? 1.0 : rawStep;
    final chartMaxY = step * 4;
    final yLabels = [0.0, step, step * 2, step * 3, step * 4];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: AppShadows.card,
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
                    child: Text('No mortality data',
                        style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.4))),
                  )
                : _pinnedScrollableChart(
                    pointCount: dailyEntries.length,
                    height: 180,
                    yAxisWidth: 30,
                    yAxis: _buildFixedYAxis(
                      chartMaxY: chartMaxY,
                      interval: step,
                      unit: '',
                      width: 30,
                      height: 180,
                      topReservedSize: _kTopReserved,
                      bottomReservedSize: _kBottomReserved,
                      decimalPlaces: 0,
                      customYLabels: yLabels,
                    ),
                    chart: _buildMortalityLineChart(dailyEntries, chartMaxY),
                  ),
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
              totalMort > 0 ? '$totalMort total mortality' : 'No mortality',
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
          Text('$label: ',
              style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.5))),
          Text(
            value,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMortalityLineChart(
      List<MortalityEntry> entries, double chartMaxY) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final labels = entries.map((e) => _formatTrendDate(e.date)).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: chartMaxY,
        minY: 0,
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: _reservedOnly(_kTopReserved),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 16,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _kBottomReserved,
              interval: entries.length > 10
                  ? (entries.length / 5).ceilToDouble()
                  : 1.0,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i >= 0 && i < labels.length) {
                  return SideTitleWidget(
                    meta: meta,
                    space: _kBottomLabelSpace,
                    child: Text(labels[i],
                        style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.4))),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 16,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: false,
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 3,
            tooltipBorder: BorderSide.none,
            getTooltipColor: (_) => Colors.transparent,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final val = rod.toY;
              if (val <= 0) return null;
              return BarTooltipItem(
                '${val.toInt()}',
                const TextStyle(
                  color: AppColors.critical,
                  fontWeight: FontWeight.w700,
                  fontSize: 8.5,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(entries.length, (i) {
          final val = entries[i].count;
          return BarChartGroupData(
            x: i,
            showingTooltipIndicators: val > 0 ? [0] : [],
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

class _LabelDotPainter extends FlDotPainter {
  final FlDotCirclePainter circlePainter;
  final String label;
  final Color textColor;

  _LabelDotPainter({
    required this.circlePainter,
    required this.label,
    required this.textColor,
  });

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    circlePainter.draw(canvas, spot, offsetInCanvas);
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        fontSize: 8.5,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        offsetInCanvas.dx - textPainter.width / 2,
        offsetInCanvas.dy - circlePainter.radius - textPainter.height - 2,
      ),
    );
  }

  @override
  Size getSize(FlSpot spot) => circlePainter.getSize(spot);

  @override
  Color get mainColor => circlePainter.mainColor;

  @override
  List<Object?> get props => [circlePainter, label, textColor];

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => this;
}
