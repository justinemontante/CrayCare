import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../services/settings_service.dart';
import '../services/sensor_service.dart';
import '../widgets/analytics/analytics_charts.dart';
import '../widgets/analytics/filter_selector.dart';

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
  final Map<String, List<double>> _minData = {};
  final Map<String, List<double>> _maxData = {};
  final Map<String, List<String>> _labels = {};
  final Set<String> _historyLoadFailed = <String>{};
  final Map<String, int?> _selectedIndices = {};
  late final Map<String, GlobalKey> _chartCardKeys;
  late final ScrollController _scrollController;

  bool _isLoading = false;
  final Set<String> _fetchingRanges = <String>{};
  int _filterRequestId = 0;
  bool get _isFetching => _fetchingRanges.isNotEmpty;
  final Map<String, DateTime> _lastFetchedAt = {}; // range → when last fetched
  static const _historyRefreshInterval = Duration(minutes: 10);
  Timer? _autoRefreshTimer;
  Timer? _liveTimer;
  final ValueNotifier<int> _liveRefresh = ValueNotifier<int>(0);
  static const _liveReadingTimeout = Duration(seconds: 10);
  bool _isTabActive = false;

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
    if (!_isTabActive) return;
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          _activeFilter == 'live' &&
          SensorService.sensorKeys.any((key) {
            if (_data['$key-live']?.isEmpty ?? true) return false;
            final times = SensorService.instance.getDataTimes(key);
            return times.isEmpty ||
                DateTime.now().difference(times.last) > _liveReadingTimeout;
          })) {
        _generateLive();
      }
    });
  }

  void _generateLive() {
    final now = DateTime.now();
    for (final key in SensorService.sensorKeys) {
      final history = SensorService.instance.getData(key);
      final historyTimes = SensorService.instance.getDataTimes(key);
      final hasMatchingTimes = historyTimes.length == history.length;
      final hasFreshReading =
          hasMatchingTimes &&
          historyTimes.isNotEmpty &&
          !now.isBefore(historyTimes.last) &&
          now.difference(historyTimes.last) <= _liveReadingTimeout;
      if (!hasFreshReading) {
        _data['$key-live'] = <double>[];
        _minData['$key-live'] = <double>[];
        _maxData['$key-live'] = <double>[];
        _labels['$key-live'] = <String>[];
        continue;
      }
      // Live view is intentionally limited to the newest eight actual sensor
      // readings so the points and their timestamps stay readable together.
      final last8 = history.length > 8
          ? history.sublist(history.length - 8)
          : history;
      _data['$key-live'] = List<double>.from(last8);
      _minData['$key-live'] = List<double>.from(last8);
      _maxData['$key-live'] = List<double>.from(last8);

      final lastTimes = historyTimes.length > 8
          ? historyTimes.sublist(historyTimes.length - 8)
          : historyTimes;
      _labels['$key-live'] = List<String>.generate(last8.length, (i) {
        final t = lastTimes[i];
        final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
        final ampm = t.hour >= 12 ? 'PM' : 'AM';
        return '$h:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')} $ampm';
      });
    }
    _liveRefresh.value++;
    if (mounted) setState(() {});
  }

  Future<void> _maybeAutoRefreshHistory() async {
    if (!mounted) return;
    if (!_isTabActive) return;
    if (!_activeRangeIncludesToday) return;
    if (_isFetching) return; // another fetch is already in flight
    // Skip if we fetched this range recently (ESP writes every 10 min)
    final lastFetch = _lastFetchedAt[_activeFilter];
    if (lastFetch != null &&
        DateTime.now().difference(lastFetch) < _historyRefreshInterval) {
      return;
    }
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
      'feedlevel': GlobalKey(),
    };
    _scrollController = ScrollController();
    _generateLive();
    _startLiveTimer();
    SettingsService.instance.addListener(_onSettingsChanged);
    SensorService.instance.addListener(_onSensorChanged);
    // Auto-refresh every 10 min — matches the ESP32 history write cadence.
    // Refreshing more often just reads docs that haven't changed yet.
    _autoRefreshTimer = Timer.periodic(
      _historyRefreshInterval,
      (_) => _maybeAutoRefreshHistory(),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _liveTimer?.cancel();
    _liveRefresh.dispose();
    _scrollController.dispose();
    SettingsService.instance.removeListener(_onSettingsChanged);
    SensorService.instance.removeListener(_onSensorChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted && _isTabActive) setState(() {});
  }

  void _onSensorChanged() {
    if (!mounted || !_isTabActive || _activeFilter != 'live') return;
    // Redraw immediately when Firestore delivers a new sensor snapshot.
    // The timer remains only as a fallback for lifecycle/cache updates.
    _generateLive();
  }

  void setTabActive(bool active) {
    if (_isTabActive == active) return;
    _isTabActive = active;
    if (!active) {
      _liveTimer?.cancel();
      return;
    }
    if (_activeFilter == 'live') {
      _generateLive();
      _startLiveTimer();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _retryActiveRange() async {
    final range = _activeFilter;
    if (range == 'live' || _isFetching) return;
    final requestId = ++_filterRequestId;
    setState(() {
      _isLoading = true;
      _historyLoadFailed.remove(range);
    });
    await _generateData(range);
    if (!mounted || requestId != _filterRequestId || _activeFilter != range) {
      return;
    }
    setState(() => _isLoading = false);
  }

  static const Map<String, Map<String, String>> _historyFieldMap = {
    'temp': {'avg': 'temp_avg', 'min': 'temp_min', 'max': 'temp_max'},
    'ph': {'avg': 'pH_avg', 'min': 'pH_min', 'max': 'pH_max'},
    'do': {'avg': 'DO_avg', 'min': 'DO_min', 'max': 'DO_max'},
    'turb': {
      'avg': 'turbidity_avg',
      'min': 'turbidity_min',
      'max': 'turbidity_max',
    },
    'waterlevel': {'avg': 'water_level'},
    'feedlevel': {'avg': 'feed_level'},
  };

  Future<void> _generateData(String range) async {
    if (range == 'live') {
      _generateLive();
      return;
    }
    if (_fetchingRanges.contains(range)) return;
    _fetchingRanges.add(range);
    _historyLoadFailed.remove(range);

    final now = DateTime.now();
    late DateTime historyStart;
    late DateTime historyEnd;
    if (range == '24h') {
      historyStart = now.subtract(const Duration(hours: 24));
      historyEnd = now;
    } else if (range == '7d') {
      historyStart = now.subtract(const Duration(days: 7));
      historyEnd = now;
    } else if (range == '30d') {
      final today = DateTime(now.year, now.month, now.day);
      historyStart = today.subtract(const Duration(days: 29));
      historyEnd = now;
    } else {
      historyStart = DateTime(
        _customStartDate.year,
        _customStartDate.month,
        _customStartDate.day,
      );
      final selectedEnd = DateTime(
        _customEndDate.year,
        _customEndDate.month,
        _customEndDate.day,
        23,
        59,
        59,
        999,
      );
      historyEnd = selectedEnd.isAfter(now) ? now : selectedEnd;
    }

    var customGranularity = 'daily';
    late final int pts;
    if (range == '24h') {
      pts = 144; // 10-minute buckets × 24 hours
    } else if (range == '7d') {
      pts = 168; // hourly buckets × 7 days
    } else if (range == '30d') {
      pts = 30; // daily buckets
    } else if (range == 'custom') {
      final span = historyEnd.difference(historyStart);
      if (span <= const Duration(days: 1)) {
        customGranularity = '10m';
        pts = max(1, (span.inMilliseconds / 600000).ceil());
      } else if (span <= const Duration(days: 7)) {
        customGranularity = 'hourly';
        pts = max(1, (span.inMilliseconds / 3600000).ceil());
      } else {
        pts = historyEnd.difference(historyStart).inDays + 1;
      }
    } else {
      pts = 10;
    }

    List<Map<String, dynamic>> records;
    try {
      // History can be backfilled after the ESP reconnects. Refresh the cache
      // before an explicit Analytics read so an older cached day cannot hide
      // newly uploaded entries for up to 12 hours.
      SensorService.instance.clearHistoryCache();
      final fetch = SensorService.instance.fetchHistoryRange(
        start: historyStart,
        end: historyEnd,
      );
      if (range == 'custom') {
        // Large custom ranges can legitimately span hundreds of daily
        // summaries/raw-history days. Let Firestore complete instead of
        // converting a slow but valid query into a false "No data" result.
        records = await fetch;
      } else {
        final timeout = range == '30d'
            ? const Duration(seconds: 60)
            : const Duration(seconds: 30);
        records = await fetch.timeout(timeout);
      }
      _lastFetchedAt[range] = DateTime.now();
    } catch (e) {
      _historyLoadFailed.add(range);
      debugPrint('[Analytics] Failed to load $range history: $e');
      return;
    } finally {
      _fetchingRanges.remove(range);
    }

    if (records.isEmpty || pts == 0) {
      _clearRange(range);
      return;
    }

    records.sort((a, b) => _recordTime(a).compareTo(_recordTime(b)));
    records = records.where((record) {
      final timestamp = _recordTime(record);
      return !timestamp.isBefore(historyStart) &&
          !timestamp.isAfter(historyEnd);
    }).toList();

    if (records.isEmpty) {
      _clearRange(range);
      return;
    }

    final parsedTs = records.map(_recordTime).toList();
    late final List<DateTime> labelTimes;

    if (range == '24h' || (range == 'custom' && customGranularity == '10m')) {
      labelTimes = List<DateTime>.generate(
        pts,
        (i) => historyStart.add(Duration(minutes: i * 10)),
      );
      _labels[range] = labelTimes.map((d) {
        final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
        final ampm = d.hour >= 12 ? 'PM' : 'AM';
        return '${d.month}/${d.day} $h:${d.minute.toString().padLeft(2, '0')} $ampm';
      }).toList();
    } else if (range == '7d' ||
        (range == 'custom' && customGranularity == 'hourly')) {
      labelTimes = List<DateTime>.generate(
        pts,
        (i) => historyStart.add(Duration(hours: i)),
      );
      _labels[range] = labelTimes.map((d) {
        final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
        final ampm = d.hour >= 12 ? 'PM' : 'AM';
        return '${d.month}/${d.day} $h $ampm';
      }).toList();
    } else if (range == 'custom') {
      labelTimes = List<DateTime>.generate(
        pts,
        (i) => historyStart.add(Duration(days: i)),
      );
      _labels[range] = labelTimes.map(_formatDate).toList();
    } else {
      final today = DateTime(now.year, now.month, now.day);
      labelTimes = List<DateTime>.generate(
        pts,
        (i) => today.subtract(Duration(days: pts - 1 - i)),
      );
      _labels[range] = labelTimes.map((d) => '${d.month}/${d.day}').toList();
    }

    // Use the newest real Firestore record time in each populated bucket for
    // the chart labels. The bucket grid still determines point spacing, while
    // labels no longer inherit seconds from the phone's current clock.
    final axisTimes = List<DateTime?>.filled(labelTimes.length, null);
    for (var i = 0; i < labelTimes.length; i++) {
      final usesDailyBuckets =
          range == '30d' || (range == 'custom' && customGranularity == 'daily');
      final bucketStart = usesDailyBuckets
          ? DateTime(labelTimes[i].year, labelTimes[i].month, labelTimes[i].day)
          : labelTimes[i];
      final bucketEnd = switch ((range, customGranularity)) {
        ('24h', _) || ('custom', '10m') =>
          i == labelTimes.length - 1
              ? historyEnd.add(const Duration(microseconds: 1))
              : bucketStart.add(const Duration(minutes: 10)),
        ('7d', _) || ('custom', 'hourly') =>
          i == labelTimes.length - 1
              ? historyEnd.add(const Duration(microseconds: 1))
              : bucketStart.add(const Duration(hours: 1)),
        _ => bucketStart.add(const Duration(days: 1)),
      };
      for (final timestamp in parsedTs) {
        if (timestamp.isBefore(bucketStart) || !timestamp.isBefore(bucketEnd)) {
          continue;
        }
        if (axisTimes[i] == null || timestamp.isAfter(axisTimes[i]!)) {
          axisTimes[i] = timestamp;
        }
      }
    }
    _labels[range] = List<String>.generate(labelTimes.length, (i) {
      final time = axisTimes[i] ?? labelTimes[i];
      if (range == '30d' ||
          (range == 'custom' && customGranularity == 'daily')) {
        return _formatDate(time);
      }
      final hour = time.hour > 12
          ? time.hour - 12
          : (time.hour == 0 ? 12 : time.hour);
      final ampm = time.hour >= 12 ? 'PM' : 'AM';
      final minute = time.minute.toString().padLeft(2, '0');
      final second = time.second.toString().padLeft(2, '0');
      return '${time.month}/${time.day} $hour:$minute:$second $ampm';
    });

    for (final key in SensorService.sensorKeys) {
      final fields = _historyFieldMap[key];
      if (fields == null) continue;
      final averages = List<double>.filled(labelTimes.length, double.nan);
      // Chart points and period statistics must use the stored average for
      // each sensor-history record. The ESP's *_min/*_max fields describe
      // variation inside one capture window, not the selected Analytics range.

      for (int i = 0; i < labelTimes.length; i++) {
        final usesDailyBuckets =
            range == '30d' ||
            (range == 'custom' && customGranularity == 'daily');
        final bucketStart = usesDailyBuckets
            ? DateTime(
                labelTimes[i].year,
                labelTimes[i].month,
                labelTimes[i].day,
              )
            : labelTimes[i];
        final bucketEnd = switch ((range, customGranularity)) {
          ('24h', _) || ('custom', '10m') =>
            i == labelTimes.length - 1
                ? historyEnd.add(const Duration(microseconds: 1))
                : bucketStart.add(const Duration(minutes: 10)),
          ('7d', _) || ('custom', 'hourly') =>
            i == labelTimes.length - 1
                ? historyEnd.add(const Duration(microseconds: 1))
                : bucketStart.add(const Duration(hours: 1)),
          _ => bucketStart.add(const Duration(days: 1)),
        };

        double sum = 0;
        int count = 0;

        for (int j = 0; j < records.length; j++) {
          final timestamp = parsedTs[j];
          if (timestamp.isBefore(bucketStart) ||
              !timestamp.isBefore(bucketEnd)) {
            continue;
          }

          final avgRaw = key == 'waterlevel'
              ? records[j]['water_level']
              : key == 'feedlevel'
              ? records[j]['feed_level']
              : records[j][fields['avg']!];
          final avg = _historyValue(key, avgRaw);
          if (avg != null) {
            sum += avg;
            count++;
          }
        }

        if (count > 0) averages[i] = sum / count;
      }

      // Keep empty buckets as NaN. AnalyticsLineChart already breaks line
      // segments at NaN, so actual sensor outages remain visible instead of
      // compressing time and joining unrelated readings together.
      _data['$key-$range'] = averages;
      // Period Min/Max are calculated from these same plotted data points.
      _minData['$key-$range'] = List<double>.from(averages);
      _maxData['$key-$range'] = List<double>.from(averages);
    }
  }

  void _clearRange(String range) {
    for (final key in SensorService.sensorKeys) {
      _data['$key-$range'] = <double>[];
      _minData['$key-$range'] = <double>[];
      _maxData['$key-$range'] = <double>[];
    }
    _labels[range] = <String>[];
  }

  double? _historyValue(String key, dynamic raw) {
    final value = _toDouble(raw);
    if (value == null || !value.isFinite) return null;
    return switch (key) {
      'temp' => value >= 0 && value <= 60 ? value : null,
      'ph' => value >= 2 && value <= 12 ? value : null,
      'do' => value >= 0 && value <= 15 ? value : null,
      'turb' => value >= 0 && value <= 500 ? value : null,
      'waterlevel' => value >= 0 && value <= 300 ? value : null,
      'feedlevel' => value >= 0 && value <= 100 ? value : null,
      _ => value >= 0 ? value : null,
    };
  }

  DateTime _recordTime(Map<String, dynamic> record) {
    final raw =
        record['recorded_at'] ??
        record['captured_at_ms'] ??
        record['timestamp'] ??
        record['created_at'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is num) {
      final n = raw.toInt();
      final ms = n < 100000000000 ? n * 1000 : n;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime(2000);
    return DateTime(2000);
  }

  double? _toDouble(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return null;
  }

  List<double> _getData(String key, String range) {
    return _data['$key-$range'] ?? [];
  }

  List<double> _getMinData(String key, String range) {
    return _minData['$key-$range'] ?? _getData(key, range);
  }

  List<double> _getMaxData(String key, String range) {
    return _maxData['$key-$range'] ?? _getData(key, range);
  }

  List<String> _getLabels(String key, String range) {
    return _labels[range == 'live' ? '$key-live' : range] ?? [];
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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
                  child: FilterSelector(
                    activeFilter: _activeFilter,
                    showCustom: _showCustom,
                    onFilterChanged: (val) async {
                      final requestId = ++_filterRequestId;
                      setState(() {
                        _activeFilter = val;
                        _showCustom = false;
                        _selectedIndices.clear();
                        _isLoading = val != 'live';
                      });
                      if (val == 'live') {
                        _startLiveTimer();
                        _generateLive();
                      } else {
                        _liveTimer?.cancel();
                        await _generateData(val);
                      }
                      if (mounted &&
                          requestId == _filterRequestId &&
                          _activeFilter == val) {
                        setState(() => _isLoading = false);
                      }
                    },
                    onToggleCustom: () {
                      setState(() => _showCustom = !_showCustom);
                    },
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        alignment: Alignment.topCenter,
                        child: child,
                      ),
                    ),
                    child: _showCustom
                        ? Padding(
                            key: const ValueKey('custom-date-row'),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _buildCustomDateRow(),
                          )
                        : const SizedBox(key: ValueKey('custom-date-hidden')),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _isLoading
                      ? const Padding(
                          key: ValueKey('analytics-loading'),
                          padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              color: AppColors.primary,
                              backgroundColor: Color(0xFFE7F5F5),
                            ),
                          ),
                        )
                      : const SizedBox(
                          key: ValueKey('analytics-loaded'),
                          height: 2,
                        ),
                ),
                if (!_isLoading &&
                    _activeFilter != 'live' &&
                    _historyLoadFailed.contains(_activeFilter))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Could not refresh history. Check your connection and try again.',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.dark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _retryActiveRange,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                            child: const Text(
                              'Try Again',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAnalyticsGroupHeader(
                        'Water Quality Parameters',
                        Icons.water_drop_rounded,
                        topPadding: 0,
                      ),
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
                          title: 'Dissolved O₂',
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
                      _buildAnalyticsGroupHeader(
                        'Physical Parameters',
                        Icons.straighten_rounded,
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
                      KeyedSubtree(
                        key: _chartCardKeys['feedlevel'],
                        child: _buildChartCard(
                          context,
                          title: 'Feed Level',
                          iconPath: 'assets/images/FeedingImage.png',
                          chartKey: 'feedlevel',
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
            Color(0xFFF8FFFF),
            Color(0xFFF2FDFD),
            Color(0xFFE8FAFA),
            Color(0xFFDAF4F5),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
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

  Widget _buildAnalyticsGroupHeader(
    String title,
    IconData icon, {
    double topPadding = 8,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2, topPadding, 2, 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(color: AppColors.primary.withValues(alpha: 0.24)),
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
          final maxEnd = _customStartDate.add(const Duration(days: 364));
          if (_customEndDate.isAfter(maxEnd)) {
            _customEndDate = maxEnd.isAfter(now) ? now : maxEnd;
          }
        } else {
          _customEndDate = picked;
          if (_customEndDate.isBefore(_customStartDate)) {
            _customStartDate = _customEndDate;
          }
          final minStart = _customEndDate.subtract(const Duration(days: 364));
          if (_customStartDate.isBefore(minStart)) {
            _customStartDate = minStart;
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
                final requestId = ++_filterRequestId;
                setState(() {
                  _activeFilter = 'custom';
                  _selectedIndices.clear();
                  _isLoading = true;
                });
                await _generateData('custom');
                if (mounted &&
                    requestId == _filterRequestId &&
                    _activeFilter == 'custom') {
                  setState(() => _isLoading = false);
                }
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
    final minData = _getMinData(chartKey, _activeFilter);
    final maxData = _getMaxData(chartKey, _activeFilter);
    final labels = _getLabels(chartKey, _activeFilter);
    final dp = _decimalFor(chartKey);
    final validData = data.where((v) => !v.isNaN).toList();
    final validMinData = minData.where((v) => !v.isNaN).toList();
    final validMaxData = maxData.where((v) => !v.isNaN).toList();
    final hasValid = validData.isNotEmpty;
    final mn = validMinData.isEmpty
        ? '--'
        : validMinData.reduce(min).toStringAsFixed(dp);
    final mx = validMaxData.isEmpty
        ? '--'
        : validMaxData.reduce(max).toStringAsFixed(dp);
    const curLabel = 'Selected period';
    final unit = _unitFor(chartKey);

    int minIdx = -1, maxIdx = -1;
    if (validMinData.isNotEmpty) {
      minIdx = minData.indexOf(validMinData.reduce(min));
    }
    if (validMaxData.isNotEmpty) {
      maxIdx = maxData.indexOf(validMaxData.reduce(max));
    }
    const nowIdx = -1;
    final minLabel = (minIdx >= 0 && minIdx < labels.length)
        ? labels[minIdx]
        : '';
    final maxLabel = (maxIdx >= 0 && maxIdx < labels.length)
        ? labels[maxIdx]
        : '';

    final thresholds = _thresholdsFor(chartKey);
    final criticalItems = _showCritical
        ? _criticalItemsFor(
            chartKey: chartKey,
            labels: labels,
            minData: minData,
            maxData: maxData,
            thresholds: thresholds,
          )
        : const <_CriticalItem>[];
    final criticalCount = criticalItems.length;

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
                  if (_activeFilter == 'live')
                    _buildLiveSensorStatus(chartKey, hasValid),
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
                        thresholdMin: chartKey == 'waterlevel'
                            ? null
                            : thresholds['min'],
                        thresholdMax: chartKey == 'waterlevel'
                            ? null
                            : thresholds['max'],
                        decimalPlaces: dp,
                        // Start on the newest point in the selected range.
                        initialScrollToEnd: true,
                      ),
              ),
              if (hasValid && _activeFilter == 'live') ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Current Reading: ${validData.last.toStringAsFixed(dp)} $unit',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                ),
              ],
              if (hasValid && _activeFilter != 'live') ...[
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

  Widget _buildLiveSensorStatus(String chartKey, bool hasReading) {
    final zone = hasReading
        ? SensorService.instance.getZone(chartKey)
        : 'NO READING';
    final label = switch (zone) {
      'OPTIMAL' => 'NORMAL',
      'WARNING' => 'WARNING',
      'CRITICAL' => 'CRITICAL',
      'EMPTY' => 'EMPTY',
      _ => 'NO READING',
    };
    final color = switch (zone) {
      'OPTIMAL' => AppColors.success,
      'WARNING' => AppColors.warning,
      'CRITICAL' || 'EMPTY' => AppColors.critical,
      _ => AppColors.darkWith(0.35),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
          color: color,
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
      case 'feedlevel':
        return const Color(0xFF14B8A6);
      default:
        return AppColors.primary;
    }
  }

  String _unitFor(String key) {
    switch (key) {
      case 'temp':
        return '°C';
      case 'ph':
        return 'pH';
      case 'do':
        return 'mg/L';
      case 'turb':
        return 'NTU';
      case 'waterlevel':
        return 'cm';
      case 'feedlevel':
        return '%';
      default:
        return '';
    }
  }

  int _decimalFor(String key) => key == 'feedlevel' ? 0 : 2;

  Map<String, double> _thresholdsFor(String key) {
    final range = SettingsService.instance.currentRanges[key];
    if (key == 'waterlevel') {
      return {
        'low': range?['low'] ?? 15.0,
        'critical': range?['critical'] ?? 10.0,
      };
    }
    if (range != null) return range;
    return {'min': 0.0, 'max': 999.0};
  }

  String _noDataStatus(String key) {
    if (_activeFilter != 'live' && _historyLoadFailed.contains(_activeFilter)) {
      return 'Unable to load history. Check your connection and try again.';
    }
    return 'No sensor reading';
  }

  List<_CriticalItem> _criticalItemsFor({
    required String chartKey,
    required List<String> labels,
    required List<double> minData,
    required List<double> maxData,
    required Map<String, double> thresholds,
  }) {
    final items = <_CriticalItem>[];
    if (chartKey == 'waterlevel') {
      final lowThreshold = thresholds['low'] ?? 15.0;
      final criticalThreshold = thresholds['critical'] ?? 10.0;
      final length = max(minData.length, maxData.length);
      for (int i = 0; i < length; i++) {
        final value = i < minData.length && !minData[i].isNaN
            ? minData[i]
            : (i < maxData.length ? maxData[i] : double.nan);
        if (!value.isNaN && value <= lowThreshold) {
          items.add(
            _CriticalItem(
              value: value,
              label: i < labels.length ? labels[i] : '',
              isAboveMax: value <= criticalThreshold,
            ),
          );
        }
      }
      return items;
    }
    final minThreshold = thresholds['min'] ?? double.negativeInfinity;
    final maxThreshold = thresholds['max'] ?? double.infinity;
    final length = max(minData.length, maxData.length);
    for (int i = 0; i < length; i++) {
      final label = i < labels.length ? labels[i] : '';
      if (i < minData.length) {
        final low = minData[i];
        if (!low.isNaN && low < minThreshold) {
          items.add(_CriticalItem(value: low, label: label, isAboveMax: false));
        }
      }
      if (i < maxData.length) {
        final high = maxData[i];
        if (!high.isNaN && high > maxThreshold) {
          items.add(_CriticalItem(value: high, label: label, isAboveMax: true));
        }
      }
    }
    return items;
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

    if (chartKey == 'waterlevel') {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primaryWith(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.darkWith(0.06)),
        ),
        child: _buildStatRow(
          Icons.water_drop_outlined,
          'Average: ${avg.toStringAsFixed(dp)} cm',
          'Selected period',
          AppColors.primary,
        ),
      );
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
                        ? chartKey == 'waterlevel'
                              ? '$criticalCount low/critical reading${criticalCount > 1 ? 's' : ''}'
                              : '$criticalCount critical point${criticalCount > 1 ? 's' : ''}'
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
    if (!mounted) return;
    setState(() {
      _activeFilter = 'live';
      _showCustom = false;
      _selectedIndices.clear();
      _isLoading = false;
    });
    _generateLive();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startLiveTimer();
      final ctx = _chartCardKeys[chartKey]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
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
            _liveRefresh,
          ]),
          builder: (context, child) {
            final data = _getData(chartKey, _activeFilter);
            final minData = _getMinData(chartKey, _activeFilter);
            final maxData = _getMaxData(chartKey, _activeFilter);
            final labels = _getLabels(chartKey, _activeFilter);
            final color = _colorFor(chartKey);
            final dp = _decimalFor(chartKey);
            final validData = data.where((v) => !v.isNaN).toList();
            final validMinData = minData.where((v) => !v.isNaN).toList();
            final validMaxData = maxData.where((v) => !v.isNaN).toList();
            final hasValid = validData.isNotEmpty;

            int minIdx = -1, maxIdx = -1;
            final mn = validMinData.isEmpty
                ? '--'
                : validMinData.reduce(min).toStringAsFixed(dp);
            final mx = validMaxData.isEmpty
                ? '--'
                : validMaxData.reduce(max).toStringAsFixed(dp);
            if (validMinData.isNotEmpty) {
              minIdx = minData.indexOf(validMinData.reduce(min));
            }
            if (validMaxData.isNotEmpty) {
              maxIdx = maxData.indexOf(validMaxData.reduce(max));
            }
            const nowIdx = -1;
            final minLabel = (minIdx >= 0 && minIdx < labels.length)
                ? labels[minIdx]
                : '';
            final maxLabel = (maxIdx >= 0 && maxIdx < labels.length)
                ? labels[maxIdx]
                : '';

            final thresholds = _thresholdsFor(chartKey);
            final criticalItems = _showCritical
                ? _criticalItemsFor(
                    chartKey: chartKey,
                    labels: labels,
                    minData: minData,
                    maxData: maxData,
                    thresholds: thresholds,
                  )
                : const <_CriticalItem>[];
            final criticalCount = criticalItems.length;
            const curLabel = 'Selected period';
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
                                  ? chartKey == 'waterlevel'
                                        ? 'Low/Critical Readings'
                                        : 'Critical Points'
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
                          _buildModalCriticalList(
                            criticalItems,
                            unit,
                            chartKey: chartKey,
                            dp: dp,
                          )
                        else ...[
                          if (_activeFilter != 'live')
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
                                  if (chartKey == 'waterlevel')
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: _buildStatRow(
                                        Icons.water_drop_outlined,
                                        'Average: ${avg.toStringAsFixed(dp)} cm',
                                        modalDisplayLabel,
                                        AppColors.primary,
                                      ),
                                    )
                                  else
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
                                                ? chartKey == 'waterlevel'
                                                      ? '$criticalCount low/critical reading${criticalCount > 1 ? 's' : ''}  ›'
                                                      : '$criticalCount critical point${criticalCount > 1 ? 's' : ''}  ›'
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
                                thresholdMin: chartKey == 'waterlevel'
                                    ? null
                                    : thresholds['min'],
                                thresholdMax: chartKey == 'waterlevel'
                                    ? null
                                    : thresholds['max'],
                                decimalPlaces: dp,
                                // Expanded chart follows the same oldest → newest flow.
                                initialScrollToEnd: true,
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
                          if (_activeFilter == 'live') ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    hasValid
                                        ? 'Current Reading: ${validData.last.toStringAsFixed(dp)} $unit'
                                        : 'Current Reading: -- $unit',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.dark,
                                    ),
                                  ),
                                ),
                                _buildLiveSensorStatus(chartKey, hasValid),
                              ],
                            ),
                          ],
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

  Widget _buildModalCriticalList(
    List<_CriticalItem> items,
    String unit, {
    required String chartKey,
    int dp = 1,
  }) {
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
                chartKey == 'waterlevel'
                    ? 'Low/Critical Readings (${items.length})'
                    : 'Critical Points (${items.length})',
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
