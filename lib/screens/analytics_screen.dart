import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _activeFilter = '24h';
  bool _showCustom = false;
  String? _pressedFilterValue;
  bool _isApplyPressed = false;
  DateTime _customStartDate = DateTime.now().subtract(const Duration(days: 14));
  DateTime _customEndDate = DateTime.now();

  final Map<String, List<double>> _data = {};
  final Map<String, List<String>> _labels = {};
  final Map<String, int?> _selectedIndices = {};
  String _insight = 'Loading insights...';

  final _rng = Random(42);

  void _onChartSelectionChanged(String chartKey, int? index) {
    setState(() => _selectedIndices[chartKey] = index);
  }

  @override
  void initState() {
    super.initState();
    _generateData('24h');
  }

  void _generateData(String range) {
    int pts;
    if (range == '24h')
      pts = 144;
    else if (range == '7d')
      pts = 7;
    else if (range == 'custom') {
      pts = _customEndDate.difference(_customStartDate).inDays + 1;
      if (pts < 1) pts = 1;
      if (pts > 365) pts = 365;
    } else
      pts = 10;

    final now = DateTime.now();
    List<String> labels;
    if (range == '24h') {
      labels = List.generate(pts, (i) {
        final d = now.subtract(Duration(minutes: (pts - 1 - i) * 10));
        final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
        final ampm = d.hour >= 12 ? 'PM' : 'AM';
        return '${h}:${d.minute.toString().padLeft(2, '0')} $ampm';
      });
    } else if (range == 'custom') {
      labels = List.generate(pts, (i) {
        final d = _customStartDate.add(Duration(days: i));
        return _formatDate(d);
      });
    } else {
      labels = List.generate(pts, (i) {
        final days = range == '7d' ? (pts - 1 - i) : (pts - 1 - i) * 3;
        final d = now.subtract(Duration(days: days));
        return [
              'Jan',
              'Feb',
              'Mar',
              'Apr',
              'May',
              'Jun',
              'Jul',
              'Aug',
              'Sep',
              'Oct',
              'Nov',
              'Dec',
            ][d.month - 1] +
            ' ${d.day}';
      });
    }

    _labels[range] = labels;

    final seeds = {
      'temp': {'min': 24.0, 'max': 32.0},
      'ph': {'min': 6.5, 'max': 9.0},
      'do': {'min': 2.5, 'max': 7.0},
      'turb': {'min': 10.0, 'max': 70.0},
      'waterlevel': {'min': 100.0, 'max': 200.0},
    };

    seeds.forEach((key, bounds) {
      _data['$key-$range'] = List.generate(pts, (_) {
        return (bounds['min']! +
            _rng.nextDouble() * (bounds['max']! - bounds['min']!));
      });
    });

    _updateInsight(range);
  }

  void _updateInsight(String range) {
    final d = _getData('temp', range);
    final peakTemp = d.isEmpty ? 0.0 : d.reduce(max);
    final peakTurb = _getData('turb', range).isEmpty
        ? 0.0
        : _getData('turb', range).reduce(max);
    final minDo = _getData('do', range).isEmpty
        ? 0.0
        : _getData('do', range).reduce(min);
    final minWl = _getData('waterlevel', range).isEmpty
        ? 0.0
        : _getData('waterlevel', range).reduce(min);
    final maxWl = _getData('waterlevel', range).isEmpty
        ? 0.0
        : _getData('waterlevel', range).reduce(max);

    String text = 'Peak temperature reached ${peakTemp.toStringAsFixed(1)}°C. ';
    if (peakTurb > 50)
      text +=
          'Turbidity spiked to ${peakTurb.toStringAsFixed(0)} NTU — check filtration. ';
    if (minDo < 3.5)
      text +=
          'DO dropped to ${minDo.toStringAsFixed(1)} mg/L — aerator may have triggered. ';
    if (minWl < 100)
      text +=
          'Water level dropped to ${minWl.toStringAsFixed(0)} cm — low water warning. ';
    if (maxWl > 200)
      text +=
          'Water level peaked at ${maxWl.toStringAsFixed(0)} cm — flood risk.';

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
            _buildChartCard(
              context,
              title: 'Temperature',
              iconPath: 'assets/images/temperature.png',
              chartKey: 'temp',
            ),
            _buildChartCard(
              context,
              title: 'pH Level',
              iconPath: 'assets/images/pH.png',
              chartKey: 'ph',
            ),
            _buildChartCard(
              context,
              title: 'Dissolved O\u2082',
              iconPath: 'assets/images/DO.png',
              chartKey: 'do',
            ),
            _buildChartCard(
              context,
              title: 'Turbidity',
              iconPath: 'assets/images/Turbidity.png',
              chartKey: 'turb',
            ),
            _buildChartCard(
              context,
              title: 'Water Level',
              iconPath: 'assets/images/waterLevel.png',
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
        color: AppColors.primaryWith(0.08),
        border: Border.all(color: AppColors.primaryWith(0.2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _insight,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.dark,
                height: 1.5,
              ),
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
    final isActive = value == 'custom' ? _showCustom : _activeFilter == value;
    final isPressed = _pressedFilterValue == value;
    Color bgColor;
    Color borderColor;
    Color textColor;
    if (isActive) {
      bgColor = isPressed ? const Color(0xFF178a8a) : AppColors.primary;
      borderColor = isPressed ? const Color(0xFF178a8a) : AppColors.primary;
      textColor = Colors.white;
    } else {
      bgColor = isPressed ? AppColors.primaryWith(0.1) : Colors.white;
      borderColor = AppColors.darkWith(0.15);
      textColor = isPressed ? AppColors.primary : AppColors.darkWith(0.5);
    }
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTapDown: (_) => setState(() => _pressedFilterValue = value),
            onTapUp: (_) => setState(() => _pressedFilterValue = null),
            onTapCancel: () => setState(() => _pressedFilterValue = null),
            onTap: () {
              if (value == 'custom') {
                setState(() {
                  _showCustom = !_showCustom;
                  _activeFilter = '';
                });
              } else {
                setState(() {
                  _activeFilter = value;
                  _showCustom = false;
                  _generateData(value);
                });
              }
            },
            child: Ink(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _customStartDate : _customEndDate,
      firstDate: DateTime(2025),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _customStartDate = picked;
          if (_customStartDate.isAfter(_customEndDate)) {
            _customEndDate = _customStartDate;
          }
        } else {
          _customEndDate = picked;
          if (_customEndDate.isBefore(_customStartDate)) {
            _customStartDate = _customEndDate;
          }
        }
      });
    }
  }

  Widget _buildCustomDateRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _pickDate(true),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.darkWith(0.15),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _formatDate(_customStartDate),
                  style: const TextStyle(fontSize: 10, color: AppColors.dark),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'to',
              style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.5)),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _pickDate(false),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.darkWith(0.15),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _formatDate(_customEndDate),
                  style: const TextStyle(fontSize: 10, color: AppColors.dark),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTapDown: (_) => setState(() => _isApplyPressed = true),
              onTapUp: (_) => setState(() => _isApplyPressed = false),
              onTapCancel: () => setState(() => _isApplyPressed = false),
              onTap: () {
                _generateData('custom');
                setState(() => _activeFilter = 'custom');
              },
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _isApplyPressed
                      ? const Color(0xFF178a8a)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Apply',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(
    BuildContext context, {
    required String title,
    required String iconPath,
    required String chartKey,
  }) {
    final data = _getData(chartKey, _activeFilter);
    final labels = _labels[_activeFilter] ?? [];
    final mn = data.isEmpty
        ? '--'
        : _calc(data, (d) => d.reduce(min)).toStringAsFixed(1);
    final mx = data.isEmpty
        ? '--'
        : _calc(data, (d) => d.reduce(max)).toStringAsFixed(1);
    final cur = data.isEmpty ? '--' : data.last.toStringAsFixed(1);
    final curLabel = labels.isNotEmpty ? labels.last : '';
    final unit = _unitFor(chartKey);

    int minIdx = -1, maxIdx = -1;
    if (data.isNotEmpty) {
      final minVal = data.reduce(min);
      final maxVal = data.reduce(max);
      minIdx = data.indexOf(minVal);
      maxIdx = data.indexOf(maxVal);
    }
    final nowIdx = data.length - 1;
    final minLabel = (minIdx >= 0 && minIdx < labels.length)
        ? labels[minIdx]
        : '';
    final maxLabel = (maxIdx >= 0 && maxIdx < labels.length)
        ? labels[maxIdx]
        : '';

    final thresholds = _thresholdsFor(chartKey);
    final criticalCount = data
        .where((v) => v < thresholds['min']! || v > thresholds['max']!)
        .length;

    final selIdx = _selectedIndices[chartKey];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _showChartModal(
          context,
          title: title,
          chartKey: chartKey,
          unit: unit,
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.darkWith(0.1), width: 1.5),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkWith(0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
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
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Image.asset(iconPath, width: 18, height: 18),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.primaryWith(0.03),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: data.isEmpty
                    ? Center(
                        child: Text(
                          'No data',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.darkWith(0.2),
                          ),
                        ),
                      )
                    : _buildMiniChart(
                        context,
                        data,
                        _colorFor(chartKey),
                        title,
                        unit,
                        chartKey: chartKey,
                        selectedIndex: selIdx,
                        onSelectedIndexChanged: (idx) =>
                            _onChartSelectionChanged(chartKey, idx),
                      ),
              ),
              if (data.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildStatsFooter(
                  cur,
                  curLabel,
                  mn,
                  mx,
                  minLabel,
                  maxLabel,
                  criticalCount,
                  chartKey,
                  unit,
                  minIdx: minIdx,
                  maxIdx: maxIdx,
                  nowIdx: nowIdx,
                  onSelectIndex: (idx) =>
                      _onChartSelectionChanged(chartKey, idx),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChart(
    BuildContext context,
    List<double> data,
    Color color,
    String title,
    String unit, {
    required String chartKey,
    int? selectedIndex,
    ValueChanged<int?>? onSelectedIndexChanged,
  }) {
    if (data.isEmpty) return const SizedBox.shrink();
    final labels = _labels[_activeFilter] ?? [];

    return _ChartWithTooltip(
      data: data,
      color: color,
      unit: unit,
      labels: labels,
      height: 180,
      selectedIndex: selectedIndex,
      onSelectedIndexChanged: onSelectedIndexChanged,
      thresholdMin: _thresholdsFor(chartKey)['min'],
      thresholdMax: _thresholdsFor(chartKey)['max'],
    );
  }

  Color _colorFor(String key) {
    switch (key) {
      case 'temp':
        return AppColors.warning;
      case 'ph':
        return AppColors.primary;
      case 'do':
        return const Color(0xFF52c283);
      case 'turb':
        return AppColors.critical;
      case 'waterlevel':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  String _unitFor(String key) {
    switch (key) {
      case 'temp':
        return '\u00B0C';
      case 'ph':
        return 'pH';
      case 'do':
        return 'mg/L';
      case 'turb':
        return 'NTU';
      case 'waterlevel':
        return 'cm';
      default:
        return '';
    }
  }

  Map<String, double> _thresholdsFor(String key) {
    switch (key) {
      case 'temp':
        return {'min': 25.0, 'max': 30.0};
      case 'ph':
        return {'min': 6.5, 'max': 8.5};
      case 'do':
        return {'min': 3.5, 'max': 999.0};
      case 'turb':
        return {'min': 0.0, 'max': 50.0};
      case 'waterlevel':
        return {'min': 130.0, 'max': 180.0};
      default:
        return {'min': 0.0, 'max': 999.0};
    }
  }

  Widget _buildStatsFooter(
    String cur,
    String curLabel,
    String mn,
    String mx,
    String minLabel,
    String maxLabel,
    int criticalCount,
    String chartKey,
    String unit, {
    int minIdx = -1,
    int maxIdx = -1,
    int nowIdx = -1,
    ValueChanged<int>? onSelectIndex,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primaryWith(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkWith(0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: minIdx >= 0 ? () => onSelectIndex?.call(minIdx) : null,
                  child: _buildStatRow(
                    Icons.arrow_downward,
                    'Min: $mn $unit',
                    minLabel,
                    AppColors.success,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: maxIdx >= 0 ? () => onSelectIndex?.call(maxIdx) : null,
                  child: _buildStatRow(
                    Icons.arrow_upward,
                    'Max: $mx $unit',
                    maxLabel,
                    AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: nowIdx >= 0 ? () => onSelectIndex?.call(nowIdx) : null,
                  child: _buildStatRow(
                    Icons.sensors,
                    'Now: $cur $unit',
                    curLabel,
                    AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 11,
                color: criticalCount > 0
                    ? AppColors.critical
                    : AppColors.success,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  criticalCount > 0
                      ? '$criticalCount critical point${criticalCount > 1 ? 's' : ''}'
                      : 'No critical points',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: criticalCount > 0
                        ? AppColors.critical
                        : AppColors.success,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String value, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: TextStyle(fontSize: 8, color: AppColors.darkWith(0.5)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModalCriticalList(List<_CriticalItem> items, String unit) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.critical.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.critical.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.critical),
              const SizedBox(width: 4),
              Text(
                'Critical Points (${items.length})',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.critical,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: items.reversed.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.isAboveMax ? AppColors.critical : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${c.value.toStringAsFixed(1)} $unit',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dark,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          c.label,
                          style: TextStyle(fontSize: 8, color: AppColors.darkWith(0.5)),
                        ),
                      ],
                    ),
                  ),
                ).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChartModal(
    BuildContext context, {
    required String title,
    required String chartKey,
    required String unit,
  }) {
    final data = _getData(chartKey, _activeFilter);
    final labels = _labels[_activeFilter] ?? [];
    final color = _colorFor(chartKey);

    int minIdx = -1, maxIdx = -1;
    final mn = data.isEmpty ? '--' : data.reduce(min).toStringAsFixed(1);
    final mx = data.isEmpty ? '--' : data.reduce(max).toStringAsFixed(1);
    if (data.isNotEmpty) {
      final minVal = data.reduce(min);
      final maxVal = data.reduce(max);
      minIdx = data.indexOf(minVal);
      maxIdx = data.indexOf(maxVal);
    }
    final nowIdx = data.length - 1;
    final minLabel = (minIdx >= 0 && minIdx < labels.length)
        ? labels[minIdx]
        : '';
    final maxLabel = (maxIdx >= 0 && maxIdx < labels.length)
        ? labels[maxIdx]
        : '';

    final thresholds = _thresholdsFor(chartKey);
    final criticalCount = data
        .where((v) => v < thresholds['min']! || v > thresholds['max']!)
        .length;
    final criticalItems = <_CriticalItem>[];
    if (criticalCount > 0) {
      for (int i = 0; i < data.length; i++) {
        final v = data[i];
        if (v < thresholds['min']! || v > thresholds['max']!) {
          criticalItems.add(
            _CriticalItem(
              value: v,
              label: i < labels.length ? labels[i] : '',
              isAboveMax: v > thresholds['max']!,
            ),
          );
        }
      }
    }
    final cur = data.isEmpty ? '--' : data.last.toStringAsFixed(1);
    final curLabel = labels.isNotEmpty ? labels.last : '';

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) {
        bool closePressed = false;
        int? modalSelectedIndex;
        bool modalShowCritical = false;
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (modalShowCritical)
                          GestureDetector(
                            onTap: () => setDialogState(
                                () => modalShowCritical = false),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(Icons.arrow_back,
                                  size: 16, color: AppColors.dark),
                            ),
                          ),
                        Text(
                          modalShowCritical
                              ? 'Critical Points'
                              : '$title ($unit)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark,
                          ),
                        ),
                        const Spacer(),
                        Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTapDown: (_) =>
                                setDialogState(() => closePressed = true),
                            onTapUp: (_) =>
                                setDialogState(() => closePressed = false),
                            onTapCancel: () =>
                                setDialogState(() => closePressed = false),
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: closePressed
                                    ? AppColors.darkWith(0.2)
                                    : AppColors.darkWith(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 13,
                                color: AppColors.dark,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (modalShowCritical)
                      _buildModalCriticalList(criticalItems, unit)
                    else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryWith(0.04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: minIdx >= 0
                                        ? () => setDialogState(
                                            () => modalSelectedIndex = minIdx,
                                          )
                                        : null,
                                    child: _buildStatRow(
                                      Icons.arrow_downward,
                                      'Min: $mn $unit',
                                      minLabel,
                                      AppColors.success,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: maxIdx >= 0
                                        ? () => setDialogState(
                                            () => modalSelectedIndex = maxIdx,
                                          )
                                        : null,
                                    child: _buildStatRow(
                                      Icons.arrow_upward,
                                      'Max: $mx $unit',
                                      maxLabel,
                                      AppColors.warning,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: nowIdx >= 0
                                        ? () => setDialogState(
                                            () => modalSelectedIndex = nowIdx,
                                          )
                                        : null,
                                    child: _buildStatRow(
                                      Icons.sensors,
                                      'Now: $cur $unit',
                                      curLabel,
                                      AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: criticalCount > 0
                                  ? () => setDialogState(
                                      () => modalShowCritical = true)
                                  : null,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 11,
                                    color: criticalCount > 0
                                        ? AppColors.critical
                                        : AppColors.success,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    criticalCount > 0
                                        ? '$criticalCount critical point${criticalCount > 1 ? 's' : ''}  \u203A'
                                        : 'No critical points',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: criticalCount > 0
                                          ? AppColors.critical
                                          : AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (data.isNotEmpty && labels.isNotEmpty)
                        Container(
                          height: 220,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.primaryWith(0.03),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _ChartWithTooltip(
                            data: data,
                            color: color,
                            unit: unit,
                            labels: labels,
                            large: true,
                            height: 220,
                            selectedIndex: modalSelectedIndex,
                            onSelectedIndexChanged: (idx) =>
                                setDialogState(() => modalSelectedIndex = idx),
                            thresholdMin: _thresholdsFor(chartKey)['min'],
                            thresholdMax: _thresholdsFor(chartKey)['max'],
                          ),
                        )
                      else
                        Container(
                          height: 220,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.primaryWith(0.03),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'No data available',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.darkWith(0.3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
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
  final double? thresholdMin;
  final double? thresholdMax;

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
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final yLabelW = large ? 42.0 : 36.0;
    final padL = showAxis ? yLabelW : 4.0;
    final padR = 4.0;
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
      oldDelegate.thresholdMax != thresholdMax;
}

class _ChartWithTooltip extends StatefulWidget {
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

  const _ChartWithTooltip({
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
  });

  @override
  State<_ChartWithTooltip> createState() => _ChartWithTooltipState();
}

class _ChartWithTooltipState extends State<_ChartWithTooltip> {
  void _selectPoint(Offset localPosition) {
    final data = widget.data;
    if (data.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final width = renderBox.size.width;

    final yLabelW = widget.large ? 42.0 : 36.0;
    final padL = yLabelW;
    final padR = 4.0;
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
    final range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (details) => _selectPoint(details.localPosition),
          onPanUpdate: (details) => _selectPoint(details.localPosition),
          onPanEnd: (_) {},
          child: Stack(
            children: [
              CustomPaint(
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
                ),
                size: Size(constraints.maxWidth, widget.height),
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
    final padR = 4.0;
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

class _CriticalItem {
  final double value;
  final String label;
  final bool isAboveMax;
  const _CriticalItem({
    required this.value,
    required this.label,
    required this.isAboveMax,
  });
}

class _XLabel {
  final String text;
  final int index;
  const _XLabel(this.text, this.index);
}
