import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/settings_service.dart';
import '../services/sensor_service.dart';
import '../widgets/analytics/analytics_charts.dart';
import '../widgets/analytics/filter_selector.dart';
import '../widgets/analytics/movable_ai_logo.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  AnalyticsScreenState createState() => AnalyticsScreenState();
}

class AnalyticsScreenState extends State<AnalyticsScreen> {
  String _activeFilter = 'live';
  bool _showCustom = false;
  bool _isApplyPressed = false;
  DateTime _customStartDate = DateTime.now().subtract(const Duration(days: 14));
  DateTime _customEndDate = DateTime.now();

  final Map<String, List<double>> _data = {};
  final Map<String, List<String>> _labels = {};
  final Map<String, int?> _selectedIndices = {};
  late final Map<String, GlobalKey> _chartCardKeys;
  late final ScrollController _scrollController;

  bool _isLoading = false;
  Timer? _autoRefreshTimer;
  Timer? _liveTimer;

  bool get _showCritical => _activeFilter != 'live' && _activeFilter == '24h';

  // Historical ranges (24h/7d/30d always, custom only if its end date is
  // today or later) include today's still-being-written subcollection.
  // Only those ranges benefit from auto-refreshing.
  bool get _activeRangeIncludesToday {
    if (_activeFilter == 'live') return false;
    final now = DateTime.now();
    switch (_activeFilter) {
      case '24h':
      case '7d':
      case '30d':
        return true;
      case 'custom':
        return !_customEndDate.isBefore(DateTime(now.year, now.month, now.day));
      default:
        return false;
    }
  }

  void _startLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _activeFilter == 'live') {
        _generateLive();
      }
    });
  }

  void _generateLive() {
    final now = DateTime.now();
    for (final key in SensorService.sensorKeys) {
      final history = SensorService.instance.getData(key);
      final last8 = history.length > 8 ? history.sublist(history.length - 8) : history;
      _data['$key-live'] = List<double>.from(last8);

      _labels['live'] = List<String>.generate(last8.length, (i) {
        final t = now.subtract(Duration(seconds: (last8.length - 1 - i) * 5));
        final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
        final ampm = t.hour >= 12 ? 'PM' : 'AM';
        return '$h:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')} $ampm';
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _maybeAutoRefreshHistory() async {
    if (!mounted) return;
    if (!_activeRangeIncludesToday) return;
    await _generateData(_activeFilter);
    if (mounted) setState(() {});
  }

  void _onChartSelectionChanged(String chartKey, int? index) {
    setState(() => _selectedIndices[chartKey] = index);
  }

  @override
  void initState() {
    super.initState();
    _chartCardKeys = {
      'temp': GlobalKey(),
      'ph': GlobalKey(),
      'do': GlobalKey(),
      'turb': GlobalKey(),
      'waterlevel': GlobalKey(),
    };
    _scrollController = ScrollController();
    _generateLive();
    _startLiveTimer();
    SettingsService.instance.addListener(_onSettingsChanged);
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _maybeAutoRefreshHistory(),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _liveTimer?.cancel();
    _scrollController.dispose();
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  static const _historyKeyMap = {
    'temp': 'temp_avg',
    'ph': 'pH_avg',
    'do': 'DO_avg',
    'turb': 'turbidity_avg',
    'waterlevel': 'waterLevel_avg',
  };

  Future<void> _generateData(String range) async {
    if (range == 'live') {
      _generateLive();
      return;
    }
    int pts;
    int intervalMinutes;
    if (range == '24h') {
      pts = 144; // every 10 minutes × 24h
      intervalMinutes = 10;
    } else if (range == '7d') {
      pts = 168; // every hour × 7d
      intervalMinutes = 60;
    } else if (range == '30d') {
      pts = 30; // every day
      intervalMinutes = 0;
    } else if (range == 'custom') {
      pts = _customEndDate.difference(_customStartDate).inDays + 1;
      if (pts < 1) pts = 1;
      if (pts > 365) pts = 365;
      intervalMinutes = 0;
    } else {
      pts = 10;
      intervalMinutes = 0;
    }

    final now = DateTime.now();
    DateTime historyStart;
    DateTime historyEnd;
    if (range == '24h') {
      historyStart = now.subtract(const Duration(hours: 24));
      historyEnd = now;
    } else if (range == '7d') {
      historyStart = now.subtract(const Duration(days: 7));
      historyEnd = now;
    } else if (range == '30d') {
      historyStart = now.subtract(const Duration(days: 30));
      historyEnd = now;
    } else {
      historyStart = _customStartDate;
      historyEnd = _customEndDate;
    }

    List<Map<String, dynamic>> records;
    try {
      records = await SensorService.instance.fetchHistoryRange(
        start: historyStart,
        end: historyEnd,
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      records = [];
    }

    if (records.isEmpty || pts == 0) {
      for (final key in SensorService.sensorKeys) {
        _data['$key-$range'] = [];
      }
      _labels[range] = [];
      return;
    }

    records.sort((a, b) {
      final at = _toInt(a['timestamp']) ?? 0;
      final bt = _toInt(b['timestamp']) ?? 0;
      return at.compareTo(bt);
    });

    // 24h, 7d, 30d, custom: use bucketed aggregation
    List<DateTime> labelTimes;
    if (range == '24h') {
      labelTimes = List<DateTime>.generate(pts, (i) {
        return now.subtract(Duration(minutes: (pts - 1 - i) * 10));
      });
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      _labels[range] = labelTimes.map((d) {
        final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
        final ampm = d.hour >= 12 ? 'PM' : 'AM';
        return '${months[d.month - 1]} $d.day, $h:${d.minute.toString().padLeft(2, '0')} $ampm';
      }).toList();
    } else if (range == '7d') {
      labelTimes = List<DateTime>.generate(pts, (i) {
        return now.subtract(Duration(hours: (pts - 1 - i)));
      });
      _labels[range] = labelTimes.map((d) => '${d.month}/${d.day}').toList();
    } else if (range == 'custom') {
      labelTimes = List<DateTime>.generate(pts, (i) {
        return _customStartDate.add(Duration(days: i));
      });
      _labels[range] = labelTimes.map((d) => _formatDate(d)).toList();
    } else {
      // 30d
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      labelTimes = List<DateTime>.generate(pts, (i) {
        return now.subtract(Duration(days: (pts - 1 - i)));
      });
      _labels[range] = labelTimes.map((d) => '${months[d.month - 1]} ${d.day}').toList();
    }

    // Pre-parse timestamps and extract values ONCE for all keys
    final parsedTs = List<DateTime>.generate(records.length, (i) {
      return _parseTimestamp(records[i]['timestamp']);
    });
    final valuesPerKey = <String, List<double?>>{};
    for (final key in SensorService.sensorKeys) {
      final hKey = _historyKeyMap[key]!;
      valuesPerKey[key] = List<double?>.generate(records.length, (i) {
        return _toDouble(records[i][hKey]);
      });
    }

    Duration window;
    if (intervalMinutes > 0) {
      window = Duration(minutes: intervalMinutes ~/ 2);
    } else {
      final interval = labelTimes.length > 1
          ? labelTimes[1].difference(labelTimes[0])
          : const Duration(minutes: 10);
      window = interval ~/ 2;
    }

    for (final key in SensorService.sensorKeys) {
      final vals = valuesPerKey[key]!;
      _data['$key-$range'] = List<double>.generate(labelTimes.length, (i) {
        final isDaily = i < labelTimes.length - 1 &&
            labelTimes[i + 1].difference(labelTimes[i]).inDays >= 1;

        if (isDaily) {
          final dayStart = DateTime(labelTimes[i].year, labelTimes[i].month, labelTimes[i].day);
          final dayEnd = dayStart.add(const Duration(days: 1));
          double sum = 0;
          int count = 0;
          for (int j = 0; j < records.length; j++) {
            if (parsedTs[j].isAfter(dayStart) && parsedTs[j].isBefore(dayEnd)) {
              final v = vals[j];
              if (v != null && v >= 0) { sum += v; count++; }
            }
          }
          return count > 0 ? sum / count : double.nan;
        }

        final mid = labelTimes[i];
        final start = mid.subtract(window);
        final end = mid.add(window);
        double sum = 0;
        int count = 0;
        for (int j = 0; j < records.length; j++) {
          if (parsedTs[j].isAfter(start) && parsedTs[j].isBefore(end)) {
            final v = vals[j];
            if (v != null && v >= 0) { sum += v; count++; }
          }
        }
        return count > 0 ? sum / count : double.nan;
      });
    }

    // Remove buckets where every sensor is NaN (no data at all)
    final keepIdx = <int>[];
    for (int i = 0; i < labelTimes.length; i++) {
      bool anyValid = false;
      for (final key in SensorService.sensorKeys) {
        final d = _data['$key-$range'];
        if (d != null && i < d.length && !d[i].isNaN) {
          anyValid = true;
          break;
        }
      }
      if (anyValid) keepIdx.add(i);
    }
    if (keepIdx.length < labelTimes.length) {
      for (final key in SensorService.sensorKeys) {
        final d = _data['$key-$range'];
        if (d != null) {
          _data['$key-$range'] = keepIdx.map((i) => d[i]).toList();
        }
      }
      _labels[range] = keepIdx.map((i) => _labels[range]![i]).toList();
    }

  }

  DateTime _parseTimestamp(dynamic ts) {
    if (ts is! num) return DateTime(2000);
    final ms = ts.toInt() < 100000000000 ? ts.toInt() * 1000 : ts.toInt();
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  double? _toDouble(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return null;
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return null;
  }

  List<double> _getData(String key, String range) {
    return _data['$key-$range'] ?? [];
  }

  double _calc(List<double> data, double Function(List<double>) fn) {
    return data.isEmpty ? 0.0 : fn(data);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: Colors.white,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilterSelector(
                    activeFilter: _activeFilter,
                    showCustom: _showCustom,
                    onFilterChanged: (val) async {
                      setState(() {
                        _activeFilter = val;
                        _showCustom = false;
                        _isLoading = val != 'live';
                      });
                      if (val == 'live') {
                        _startLiveTimer();
                        _generateLive();
                      } else {
                        _liveTimer?.cancel();
                        await _generateData(val);
                      }
                      if (mounted) setState(() => _isLoading = false);
                    },
                    onToggleCustom: () {
                      setState(() {
                        _showCustom = !_showCustom;
                        _activeFilter = '';
                      });
                    },
                  ),
                ),
                if (_showCustom)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _buildCustomDateRow(),
                  ),
                const SizedBox(height: 10),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_isLoading)
                  Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KeyedSubtree(
                        key: _chartCardKeys['temp'],
                        child: _buildChartCard(
                          context,
                          title: 'Temperature',
                          iconPath: 'assets/images/temperature.png',
                          chartKey: 'temp',
                        ),
                      ),
                      KeyedSubtree(
                        key: _chartCardKeys['ph'],
                        child: _buildChartCard(
                          context,
                          title: 'pH Level',
                          iconPath: 'assets/images/pH.png',
                          chartKey: 'ph',
                        ),
                      ),
                      KeyedSubtree(
                        key: _chartCardKeys['do'],
                        child: _buildChartCard(
                          context,
                          title: 'Dissolved O\u2082',
                          iconPath: 'assets/images/DO.png',
                          chartKey: 'do',
                        ),
                      ),
                      KeyedSubtree(
                        key: _chartCardKeys['turb'],
                        child: _buildChartCard(
                          context,
                          title: 'Turbidity',
                          iconPath: 'assets/images/Turbidity.png',
                          chartKey: 'turb',
                        ),
                      ),
                      KeyedSubtree(
                        key: _chartCardKeys['waterlevel'],
                        child: _buildChartCard(
                          context,
                          title: 'Water Level',
                          iconPath: 'assets/images/waterLevel.png',
                          chartKey: 'waterlevel',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const MovableAiLogo(),
      ],
    );
  }


  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF8FFFF), // #f8ffff
            Color(0xFFF2FDFD), // #f2fdfd
            Color(0xFFE8FAFA), // #e8fafa
            Color(0xFFDAF4F5), // #daf4f5
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            width: 150,
            height: 120,
            child: Image.asset(
              'assets/images/analytics_image.png',
              fit: BoxFit.contain,
              alignment: Alignment.bottomRight,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Analytics',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Data Trends & Insights',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkWith(0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
              onTap: () async {
                setState(() {
                  _activeFilter = 'custom';
                  _isLoading = true;
                });
                await _generateData('custom');
                if (mounted) setState(() => _isLoading = false);
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
    final dp = _decimalFor(chartKey);
    final validData = data.where((v) => !v.isNaN).toList();
    final hasValid = validData.isNotEmpty;
    final mn = !hasValid
        ? '--'
        : _calc(validData, (d) => d.reduce(min)).toStringAsFixed(dp);
    final mx = !hasValid
        ? '--'
        : _calc(validData, (d) => d.reduce(max)).toStringAsFixed(dp);
    final curLabel = labels.isNotEmpty ? labels.last : '';
    final unit = _unitFor(chartKey);

    int minIdx = -1, maxIdx = -1;
    if (hasValid) {
      final minVal = validData.reduce(min);
      final maxVal = validData.reduce(max);
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
    final criticalCount = _showCritical
        ? data.where((v) => !v.isNaN && (v < thresholds['min']! || v > thresholds['max']!)).length
        : 0;

    final selIdx = _selectedIndices[chartKey];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                      if (_activeFilter == '24h') ...[const SizedBox(width: 8)],
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
                child: !hasValid
                    ? Center(
                        child: Text(
                          _noDataStatus(chartKey),
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.darkWith(0.2),
                          ),
                        ),
                      )
                    : AnalyticsLineChart(
                        data: data,
                        color: _colorFor(chartKey),
                        unit: unit,
                        labels: labels,
                        height: 180,
                        selectedIndex: selIdx,
                        onSelectedIndexChanged: (idx) =>
                            _onChartSelectionChanged(chartKey, idx),
                        thresholdMin: thresholds['min'],
                        thresholdMax: thresholds['max'],
                        decimalPlaces: dp,
                      ),
              ),
              if (hasValid) ...[
                const SizedBox(height: 8),
                _buildStatsFooter(
                  curLabel,
                  mn,
                  mx,
                  minLabel,
                  maxLabel,
                  criticalCount,
                  chartKey,
                  unit,
                  data: data,
                  minIdx: minIdx,
                  maxIdx: maxIdx,
                  nowIdx: nowIdx,
                  onSelectIndex: (idx) =>
                      _onChartSelectionChanged(chartKey, idx),
                  dp: dp,
                ),
              ],
            ],
          ),
        ),
      ),
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

  int _decimalFor(String key) => 2;

  Map<String, double> _thresholdsFor(String key) {
    final range = SettingsService.instance.currentRanges[key];
    if (range != null) return range;
    return {'min': 0.0, 'max': 999.0};
  }

  String _noDataStatus(String key) {
    return 'No sensor reading';
  }

  Widget _buildStatsFooter(
    String curLabel,
    String mn,
    String mx,
    String minLabel,
    String maxLabel,
    int criticalCount,
    String chartKey,
    String unit, {
    required List<double> data,
    int minIdx = -1,
    int maxIdx = -1,
    int nowIdx = -1,
    ValueChanged<int>? onSelectIndex,
    int dp = 1,
  }) {

    double avg = 0.0;
    if (data.isNotEmpty) {
      final valid = data.where((v) => !v.isNaN).toList();
      if (valid.isNotEmpty) {
        avg = valid.reduce((a, b) => a + b) / valid.length;
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primaryWith(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkWith(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: minIdx >= 0
                      ? () => onSelectIndex?.call(minIdx)
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
                      ? () => onSelectIndex?.call(maxIdx)
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
                      ? () => onSelectIndex?.call(nowIdx)
                      : null,
                  child: _buildStatRow(
                    Icons.sensors,
                    'Avg: ${avg.toStringAsFixed(dp)} $unit',
                    curLabel,
                    AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (_showCritical) ...[
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
                      maxLines: 1,
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(fontSize: 8, color: AppColors.darkWith(0.5)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> scrollToChart(String chartKey) async {
    _activeFilter = '24h';
    _liveTimer?.cancel();
    setState(() {});
    await _generateData('24h');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _chartCardKeys[chartKey];
      if (key?.currentContext == null) return;
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _showChartModal(
    BuildContext context, {
    required String title,
    required String chartKey,
    required String unit,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) {
        bool closePressed = false;
        int? modalSelectedIndex;
        bool modalShowCritical = false;

        return ListenableBuilder(
          listenable: Listenable.merge([
            SensorService.instance,
            SettingsService.instance,
          ]),
          builder: (context, child) {
            final data = _getData(chartKey, _activeFilter);
            final labels = _labels[_activeFilter] ?? [];
            final color = _colorFor(chartKey);
            final dp = _decimalFor(chartKey);
            final validData = data.where((v) => !v.isNaN).toList();
            final hasValid = validData.isNotEmpty;

            int minIdx = -1, maxIdx = -1;
            final mn = !hasValid
                ? '--'
                : validData.reduce(min).toStringAsFixed(dp);
            final mx = !hasValid
                ? '--'
                : validData.reduce(max).toStringAsFixed(dp);
            if (hasValid) {
              final minVal = validData.reduce(min);
              final maxVal = validData.reduce(max);
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
            int criticalCount;
            List<_CriticalItem> criticalItems;
            if (_showCritical) {
              criticalCount = data
                  .where((v) => !v.isNaN && (v < thresholds['min']! || v > thresholds['max']!))
                  .length;
              criticalItems = <_CriticalItem>[];
              if (criticalCount > 0) {
                for (int i = 0; i < data.length; i++) {
                  final v = data[i];
                  if (!v.isNaN && (v < thresholds['min']! || v > thresholds['max']!)) {
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
            } else {
              criticalCount = 0;
              criticalItems = [];
            }
            final curLabel = labels.isNotEmpty ? labels.last : '';
            double avg = 0.0;
            if (validData.isNotEmpty) {
              avg = validData.reduce((a, b) => a + b) / validData.length;
            }

            return StatefulBuilder(
              builder: (ctx2, setDialogState) {
                String modalDisplayLabel = curLabel;

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
                                  () => modalShowCritical = false,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.arrow_back,
                                    size: 16,
                                    color: AppColors.dark,
                                  ),
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
                          _buildModalCriticalList(criticalItems, unit, dp: dp)
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
                                                () => modalSelectedIndex =
                                                    minIdx,
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
                                                () => modalSelectedIndex =
                                                    maxIdx,
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
                                                () => modalSelectedIndex =
                                                    nowIdx,
                                              )
                                            : null,
                                        child: _buildStatRow(
                                          Icons.sensors,
                                          'Avg: ${avg.toStringAsFixed(dp)} $unit',
                                          modalDisplayLabel,
                                          AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_showCritical) ...[
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: criticalCount > 0
                                        ? () => setDialogState(
                                            () => modalShowCritical = true,
                                          )
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
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (hasValid && labels.isNotEmpty)
                            Container(
                              height: 220,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppColors.primaryWith(0.03),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: AnalyticsLineChart(
                                data: data,
                                color: color,
                                unit: unit,
                                labels: labels,
                                large: true,
                                height: 220,
                                selectedIndex: modalSelectedIndex,
                                onSelectedIndexChanged: (idx) => setDialogState(
                                  () => modalSelectedIndex = idx,
                                ),
                                thresholdMin: thresholds['min'],
                                thresholdMax: thresholds['max'],
                                decimalPlaces: dp,
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
                                  _noDataStatus(chartKey),
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
      },
    );
  }

  Widget _buildModalCriticalList(List<_CriticalItem> items, String unit, {int dp = 1}) {
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
              const Icon(
                Icons.warning_amber_rounded,
                size: 12,
                color: AppColors.critical,
              ),
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
                children: items.reversed
                    .map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.isAboveMax
                                    ? AppColors.critical
                                    : AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${c.value.toStringAsFixed(dp)} $unit',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppColors.dark,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              c.label,
                              style: TextStyle(
                                fontSize: 8,
                                color: AppColors.darkWith(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
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
