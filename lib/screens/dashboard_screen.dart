import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../widgets/section_label.dart';
import '../services/sensor_service.dart';
import '../services/settings_service.dart';
import '../services/tank_service.dart';
import '../services/feeder_service.dart';
import '../models/control_types.dart';
import '../models/crayfish_batch.dart';

class DashboardScreen extends StatefulWidget {
  final ValueChanged<String>? onViewGraph;
  final ValueChanged<int>? onNavigate;
  final ValueChanged<int>? onTankTab;
  final ValueChanged<int>? onControlTab;

  const DashboardScreen({
    super.key,
    this.onViewGraph,
    this.onNavigate,
    this.onTankTab,
    this.onControlTab,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _quickActionsController = ScrollController();
  Timer? _countdownTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isTabActive = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    SensorService.instance.addListener(_refreshUI);
    SettingsService.instance.addListener(_refreshUI);
    TankService.instance.addListener(_refreshUI);
    FeedState.schedules.addListener(_refreshUI);
    FeedState.feederLogs.addListener(_refreshUI);
    _refreshUI();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isTabActive) setState(() {});
    });
  }

  void setTabActive(bool active) {
    if (_isTabActive == active) return;
    _isTabActive = active;
    if (active) {
      _pulseController.repeat(reverse: true);
      if (mounted) setState(() {});
    } else {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _quickActionsController.dispose();
    SensorService.instance.removeListener(_refreshUI);
    SettingsService.instance.removeListener(_refreshUI);
    TankService.instance.removeListener(_refreshUI);
    FeedState.schedules.removeListener(_refreshUI);
    FeedState.feederLogs.removeListener(_refreshUI);
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _refreshUI() {
    if (!mounted || !_isTabActive) return;
    setState(() {});
  }

  DateTime _manilaNow() => manilaWallClock();

  // Returns the first name of the signed-in user.
  String _getFirstName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null &&
        user.displayName != null &&
        user.displayName!.isNotEmpty) {
      // Split the full name by spaces and take the first word.
      return user.displayName!.trim().split(' ').first;
    }
    return 'Farmer'; // Fallback when no name is set
  }

  // DYNAMIC GREETING BASED ON TIME OF DAY
  String _getGreetingTime() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 18) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  // DYNAMIC DATE FORMATTER (Para hindi hardcoded ang May 12, 2026)
  String _getFormattedDate() {
    final now = DateTime.now();
    final weekdays = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final weekday = weekdays[now.weekday % 7];
    final month = months[now.month - 1];
    return '$weekday, $month ${now.day}, ${now.year}';
  }

  String _formatTankDate(DateTime dt) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildGreeting(),
                  _buildConnectionBanner(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: SectionLabel(
                      label: 'Water Quality Overview',
                      showLiveData: false,
                      icon: Icons.water_drop_outlined,
                      topPadding: 4,
                    ),
                  ),
                  _buildGaugeGrid(context),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: SectionLabel(
                      label: 'Physical Parameter',
                      showLiveData: false,
                      icon: Icons.analytics_outlined,
                    ),
                  ),
                  _buildPhysicalParameterRow(context),
                  const SizedBox(height: 12),
                  _buildQuickActionsHeader(),
                  _buildQuickActions(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: SectionLabel(
                      label: 'Monitoring & Inventory',
                      showLiveData: false,
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                  _buildTankStatusCard(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: SectionLabel(
                      label: 'Operational Schedule',
                      showLiveData: false,
                      icon: Icons.event_note_outlined,
                    ),
                  ),
                  _buildFeedingScheduleCard(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: AppShadows.card,
      ),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 23, 20, 23),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF8FFFF),
                  Color(0xFFF2FDFD),
                  Color(0xFFE8FAFA),
                  Color(0xFFDAF4F5),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // GREETING NAME CONNECTED TO FIREBASE (FIRST NAME ONLY)
                      Text(
                        '${_getGreetingTime()}, ${_getFirstName()}!',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // DYNAMIC DATE BASED ON PHONE TIME
                      Text(
                        _getFormattedDate(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: AppColors.mutedText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Here's what's happening in your tank today.",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.subtitleText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 190,
            child: Image.asset(
              'assets/images/seaweedImage.png',
              fit: BoxFit.contain,
              alignment: Alignment.bottomRight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner() {
    final ss = SensorService.instance;
    final hasAnyData = SensorService.sensorKeys.any((k) => ss.hasSensorData(k));
    final error = ss.lastError;
    final syncing = ss.bufferedEntries > 0;

    // Show the banner while the ESP is flushing its offline backlog even if
    // live data is already flowing again (store-and-forward in progress).
    if (hasAnyData && error == null && !syncing) return const SizedBox.shrink();

    final String message;
    final IconData bannerIcon;
    final tankService = TankService.instance;
    if (!tankService.isInitialized) {
      // A registered owner may not have a tank document until first setup.
      // TankService also returns here for an existing tank with no active
      // initialized grow-out batch.
      message = 'Tank not set up yet.';
      bannerIcon = Icons.info_outline_rounded;
    } else if (error != null && error.contains('No tank assigned')) {
      message = 'No tank assigned to this account yet.';
      bannerIcon = Icons.link_off_rounded;
    } else if (error != null) {
      message = error;
      bannerIcon = Icons.error_outline_rounded;
    } else if (!ss.initialDataLoaded) {
      message = 'Connecting to sensors...';
      bannerIcon = Icons.sensors_rounded;
    } else if (syncing) {
      final n = ss.bufferedEntries;
      message =
          'Syncing $n offline reading${n == 1 ? '' : 's'} captured during the outage…';
      bannerIcon = Icons.sync_rounded;
    } else {
      message = 'Sensors offline — waiting for new readings';
      bannerIcon = Icons.wifi_off_rounded;
    }

    final isErrorState = error != null && tankService.isInitialized;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 3, 14, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isErrorState ? const Color(0xFFFFF3F0) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isErrorState
              ? const Color(0xFFFFCCBB)
              : const Color(0xFFFFE082),
        ),
      ),
      child: Row(
        children: [
          Icon(
            bannerIcon,
            size: 16,
            color: isErrorState
                ? const Color(0xFFD84315)
                : const Color(0xFFF9A825),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isErrorState
                    ? const Color(0xFFBF360C)
                    : const Color(0xFF795548),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGaugeGrid(BuildContext context) {
    final ss = SensorService.instance;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildGaugeCard(
                  title: 'Temperature',
                  value: ss.hasSensorData('temp')
                      ? ss.getLatestValue('temp').toStringAsFixed(2)
                      : '--',
                  unit: '\u00B0C',
                  ideal: _getIdealText('temp'),
                  iconPath: 'assets/images/temperature.png',
                  status: _getStatus('temp'),
                  statusColor: _getStatusColor('temp'),
                  trend: ss.getTrend('temp'),
                  trendRate: ss.getTrendRate('temp'),
                  hasData: ss.hasSensorData('temp'),
                  sensorKey: 'temp',
                  rawValue: ss.getLatestValue('temp'),
                  onTap: () => _showGaugeDetail(
                    context,
                    sensorKey: 'temp',
                    title: 'Temperature',
                    unit: '\u00B0C',
                    ideal: _getIdealText('temp'),
                    iconPath: 'assets/images/temperature.png',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildGaugeCard(
                  title: 'pH Level',
                  value: ss.hasSensorData('ph')
                      ? ss.getLatestValue('ph').toStringAsFixed(2)
                      : '--',
                  unit: 'pH',
                  ideal: _getIdealText('ph'),
                  iconPath: 'assets/images/pH.png',
                  status: _getStatus('ph'),
                  statusColor: _getStatusColor('ph'),
                  trend: ss.getTrend('ph'),
                  trendRate: ss.getTrendRate('ph'),
                  hasData: ss.hasSensorData('ph'),
                  sensorKey: 'ph',
                  rawValue: ss.getLatestValue('ph'),
                  onTap: () => _showGaugeDetail(
                    context,
                    sensorKey: 'ph',
                    title: 'pH Level',
                    unit: 'pH',
                    ideal: _getIdealText('ph'),
                    iconPath: 'assets/images/pH.png',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildGaugeCard(
                  title: 'Dissolved O\u2082',
                  value: ss.hasSensorData('do')
                      ? ss.getLatestValue('do').toStringAsFixed(2)
                      : '--',
                  unit: 'mg/L',
                  ideal: _getIdealText('do'),
                  iconPath: 'assets/images/DO.png',
                  status: _getStatus('do'),
                  statusColor: _getStatusColor('do'),
                  trend: ss.getTrend('do'),
                  trendRate: ss.getTrendRate('do'),
                  hasData: ss.hasSensorData('do'),
                  sensorKey: 'do',
                  rawValue: ss.getLatestValue('do'),
                  onTap: () => _showGaugeDetail(
                    context,
                    sensorKey: 'do',
                    title: 'Dissolved O\u2082',
                    unit: 'mg/L',
                    ideal: _getIdealText('do'),
                    iconPath: 'assets/images/DO.png',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildGaugeCard(
                  title: 'Turbidity',
                  value: ss.hasSensorData('turb')
                      ? ss.getLatestValue('turb').toStringAsFixed(2)
                      : '--',
                  unit: 'NTU',
                  ideal: _getIdealText('turb'),
                  iconPath: 'assets/images/Turbidity.png',
                  status: _getStatus('turb'),
                  statusColor: _getStatusColor('turb'),
                  trend: ss.getTrend('turb'),
                  trendRate: ss.getTrendRate('turb'),
                  hasData: ss.hasSensorData('turb'),
                  sensorKey: 'turb',
                  rawValue: ss.getLatestValue('turb'),
                  onTap: () => _showGaugeDetail(
                    context,
                    sensorKey: 'turb',
                    title: 'Turbidity',
                    unit: 'NTU',
                    ideal: _getIdealText('turb'),
                    iconPath: 'assets/images/Turbidity.png',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatMax(double max) {
    if (max >= 999) return '\u221E';
    return max.toStringAsFixed(1);
  }

  String _getUnit(String key) {
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

  String _getIdealText(String key) {
    final ranges = SettingsService.instance.currentRanges;
    final range = ranges[key];
    if (range == null) return '';
    final min = range['min'] ?? 0.0;
    final max = range['max'] ?? 999.0;
    final unit = _getUnit(key);
    if (key == 'feedlevel') {
      return 'Ideal: > ${min.toStringAsFixed(0)}%';
    }
    if (max >= 999) return 'Ideal: > ${min.toStringAsFixed(1)}$unit';
    return 'Ideal: ${min.toStringAsFixed(1)} \u2013 ${_formatMax(max)}$unit';
  }

  String _getStatus(String key) {
    final ss = SensorService.instance;
    if (!ss.hasSensorData(key)) return 'No reading';
    final zone = ss.getZone(key);
    if (key == 'feedlevel') {
      if (zone == 'OPTIMAL') return 'NORMAL';
      if (zone == 'WARNING') return 'LOW';
    }
    return zone;
  }

  Color _getStatusColor(String key) {
    final ss = SensorService.instance;
    if (!ss.hasSensorData(key)) return AppColors.darkWith(0.3);
    final zone = ss.getZone(key);
    if (zone == 'OPTIMAL') return AppColors.success;
    if (zone == 'WARNING') return AppColors.warning;
    if (zone == 'CRITICAL' || zone == 'EMPTY') return AppColors.critical;
    return AppColors.darkWith(0.4);
  }

  /// Rising is beneficial for DO (more oxygen) and for water level while it is
  /// still BELOW the safe maximum (filling toward normal). Once water level is
  /// at/above max, rising means approaching overflow, so it is no longer good.
  bool _risingIsGood(String key, double value) {
    if (key == 'do') return true;
    if (key == 'waterlevel') {
      final ranges = SettingsService.instance.currentRanges;
      final max = ranges[key]?['max'] ?? 999.0;
      return value < max;
    }
    return false;
  }

  /// Falling is beneficial for turbidity (clearer water) and for water level
  /// while it is still ABOVE the safe minimum (draining back from overflow).
  /// Below min, falling means the tank is getting too shallow.
  bool _fallingIsGood(String key, double value) {
    if (key == 'turb') return true;
    if (key == 'waterlevel') {
      final ranges = SettingsService.instance.currentRanges;
      final min = ranges[key]?['min'] ?? 0.0;
      return value > min;
    }
    return false;
  }

  Color _getTrendColor(
    String key,
    double value,
    String trend,
    double rate,
    String status,
  ) {
    // Sensors with a clear preferred direction — collapse the 3 identical branches into one.
    if (_risingIsGood(key, value) || _fallingIsGood(key, value)) {
      final bool goodDir = _risingIsGood(key, value)
          ? (trend == 'rising' || trend == 'rising_fast')
          : (trend == 'falling' || trend == 'falling_fast');
      final bool badDir = _risingIsGood(key, value)
          ? (trend == 'falling' || trend == 'falling_fast')
          : (trend == 'rising' || trend == 'rising_fast');
      if (goodDir) return AppColors.success;
      if (badDir) {
        return status == 'CRITICAL' || status == 'WARNING'
            ? AppColors.critical
            : AppColors.warning;
      }
      return AppColors.dark.withValues(alpha: 0.4);
    }

    if (status == 'OPTIMAL' || trend == 'stable' || rate == 0) {
      switch (trend) {
        case 'rising_fast':
        case 'falling_fast':
          return AppColors.critical;
        case 'rising':
        case 'falling':
          return AppColors.warning;
        default:
          return AppColors.dark.withValues(alpha: 0.4);
      }
    }

    final ranges = SettingsService.instance.currentRanges;
    final range = ranges[key];
    if (range == null) return AppColors.warning;
    final min = range['min'] ?? 0.0;
    final max = range['max'] ?? 999.0;

    final bool improving;
    if (value < min) {
      improving = rate > 0;
    } else if (value > max && max < 999.0) {
      improving = rate < 0;
    } else {
      final mid = (min + (max < 999 ? max : min * 2)) / 2;
      improving = rate > 0 ? value < mid : value > mid;
    }

    if (improving) return AppColors.success;
    if (status == 'CRITICAL') return AppColors.critical;
    return AppColors.warning;
  }

  Widget _buildGaugeCard({
    required String title,
    required String value,
    required String unit,
    required String ideal,
    required String iconPath,
    required String status,
    required Color statusColor,
    required String trend,
    required double trendRate,
    required bool hasData,
    required String sensorKey,
    required double rawValue,
    VoidCallback? onTap,
  }) {
    final trendColor = _getTrendColor(
      sensorKey,
      rawValue,
      trend,
      trendRate,
      status,
    );
    return _GaugeCard(
      title: title,
      value: value,
      unit: unit,
      ideal: ideal,
      iconPath: iconPath,
      status: status,
      statusColor: statusColor,
      trend: trend,
      trendRate: trendRate,
      trendColor: trendColor,
      hasData: hasData,
      sensorKey: sensorKey,
      rawValue: rawValue,
      onTap: onTap,
    );
  }

  Widget _buildPhysicalParameterRow(BuildContext context) {
    final ss = SensorService.instance;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildGaugeCard(
                title: 'Water Level',
                value: ss.hasSensorData('waterlevel')
                    ? ss.getLatestValue('waterlevel').toStringAsFixed(2)
                    : '--',
                unit: 'cm',
                ideal: _getIdealText('waterlevel'),
                iconPath: 'assets/images/waterLevel.png',
                status: _getStatus('waterlevel'),
                statusColor: _getStatusColor('waterlevel'),
                trend: ss.getTrend('waterlevel'),
                trendRate: ss.getTrendRate('waterlevel'),
                hasData: ss.hasSensorData('waterlevel'),
                sensorKey: 'waterlevel',
                rawValue: ss.getLatestValue('waterlevel'),
                onTap: () => _showGaugeDetail(
                  context,
                  sensorKey: 'waterlevel',
                  title: 'Water Level',
                  unit: 'cm',
                  ideal: _getIdealText('waterlevel'),
                  iconPath: 'assets/images/waterLevel.png',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGaugeCard(
                title: 'Feed Level',
                value: ss.hasSensorData('feedlevel')
                    ? ss.getLatestValue('feedlevel').toStringAsFixed(0)
                    : '--',
                unit: '%',
                ideal: _getIdealText('feedlevel'),
                iconPath: 'assets/images/FeedingImage.png',
                status: _getStatus('feedlevel'),
                statusColor: _getStatusColor('feedlevel'),
                trend: ss.getTrend('feedlevel'),
                trendRate: ss.getTrendRate('feedlevel'),
                hasData: ss.hasSensorData('feedlevel'),
                sensorKey: 'feedlevel',
                rawValue: ss.getLatestValue('feedlevel'),
                onTap: () => _showGaugeDetail(
                  context,
                  sensorKey: 'feedlevel',
                  title: 'Feed Level',
                  unit: '%',
                  ideal: _getIdealText('feedlevel'),
                  iconPath: 'assets/images/FeedingImage.png',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: SectionLabel(
              label: 'Quick Actions',
              showLiveData: false,
              icon: Icons.bolt_outlined,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 18, top: 4),
            child: GestureDetector(
              onTap: () {
                if (_quickActionsController.hasClients) {
                  _quickActionsController.animateTo(
                    _quickActionsController.offset + 150,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final tank = widget.onTankTab;
    final control = widget.onControlTab;
    final actions = [
      _QuickActionData(
        'Aerator 1',
        Icons.air,
        null,
        onTap: control != null ? () => control(1) : null,
      ),
      _QuickActionData(
        'Aerator 2',
        Icons.air,
        null,
        onTap: control != null ? () => control(1) : null,
      ),
      _QuickActionData(
        'Water Pump',
        Icons.water_drop,
        null,
        onTap: control != null ? () => control(1) : null,
      ),
      _QuickActionData(
        'Auto Feeder',
        Icons.bubble_chart,
        null,
        onTap: control != null ? () => control(0) : null,
      ),
      _QuickActionData(
        'Batch Overview',
        Icons.dashboard_rounded,
        null,
        onTap: tank != null ? () => tank(0) : null,
      ),
      _QuickActionData(
        'Take Sample',
        Icons.speed_rounded,
        null,
        onTap: tank != null ? () => tank(1) : null,
      ),
      _QuickActionData(
        'Growth Trends',
        Icons.trending_up_rounded,
        null,
        onTap: tank != null ? () => tank(2) : null,
      ),
    ];

    return SingleChildScrollView(
      controller: _quickActionsController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: actions.map((a) {
          return GestureDetector(
            onTap: a.onTap,
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.darkWith(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.darkWith(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryWith(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(a.icon, size: 16, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                      if (a.status != null)
                        Text(
                          a.status!,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: a.status == 'Active'
                                ? AppColors.success
                                : AppColors.darkWith(0.4),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTankStatusCard() {
    final tank = TankService.instance;
    final batch = tank.selectedBatch ?? tank.activeOrLatestBatch;
    final hasActive = batch?.status == 'active';
    final hasBatch = batch != null;

    String popStr, survivalStr, aliveStr, mortalityStr;
    if (hasActive && batch != null) {
      final isSelected = tank.selectedBatchId == batch.batchId;
      final effectiveMortality = isSelected
          ? tank.mortality
          : batch.totalMortality;
      final effectiveInitial = batch.initialCount;
      popStr = effectiveInitial.toString();
      final surv = effectiveInitial > 0
          ? ((effectiveInitial - effectiveMortality) / effectiveInitial * 100)
                .clamp(0.0, 100.0)
          : 0.0;
      survivalStr = '${surv.toStringAsFixed(1)}%';
      aliveStr = isSelected
          ? tank.inTankCount.toString()
          : (effectiveInitial - effectiveMortality - batch.harvestCount)
                .clamp(0, effectiveInitial)
                .toString();
      mortalityStr = effectiveMortality.toString();
    } else if (batch != null) {
      final surv = batch.initialCount > 0
          ? ((batch.initialCount - batch.totalMortality) /
                    batch.initialCount *
                    100)
                .clamp(0.0, 100.0)
          : 0.0;
      popStr = '${batch.initialCount}';
      survivalStr = '${surv.toStringAsFixed(1)}%';
      aliveStr = '0';
      mortalityStr = '${batch.totalMortality}';
    } else {
      popStr = survivalStr = aliveStr = mortalityStr = '--';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Crayfish Information',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (batch != null) {
                      tank.selectBatch(batch.batchId);
                    }
                    widget.onTankTab?.call(0);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasActive
                              ? 'Manage'
                              : (hasBatch ? 'View' : 'Initialize'),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 9,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatColumn(
                    'assets/images/InitialPopulationNo.png',
                    popStr,
                    'Initial Population',
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    'assets/images/SurvivalRate.png',
                    survivalStr,
                    'Survival Rate',
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    'assets/images/AliveNo.png',
                    aliveStr,
                    'In Tank',
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    'assets/images/mortalityNo.png',
                    mortalityStr,
                    'Mortality',
                    valueColor: AppColors.critical,
                  ),
                ),
              ],
            ),
          ),
          _buildCrayfishGraySection(tank, hasActive, batch),
        ],
      ),
    );
  }

  Widget _buildCrayfishGraySection(
    TankService tank,
    bool hasActive, [
    CrayfishBatch? batch,
  ]) {
    final isArchived = batch != null && !hasActive;
    final isSelected = batch != null && tank.selectedBatchId == batch.batchId;

    double abw, abl;
    String stageLabel, daysStr, lastSamplingStr;
    bool showSampling;

    if (hasActive && batch != null) {
      final history = tank.samplingHistory;
      final weekly = history.where((e) => !e.isBaseline).toList();
      final latest = weekly.isNotEmpty ? weekly.last : null;
      abw = latest != null ? latest.abw : tank.initialWeight;
      abl = latest != null ? latest.avgLength : tank.initialLength;
      daysStr = tank.daysInCulture.toString();
      lastSamplingStr = latest != null
          ? _formatTankDate(latest.date)
          : (history.isNotEmpty
                ? 'Baseline (${_formatTankDate(history.first.date)})'
                : '--');
      showSampling = true;
    } else if (isArchived) {
      abw = batch.finalAbw;
      abl = batch.finalAbl;
      daysStr = '${batch.daysInCulture}';
      lastSamplingStr = batch.harvestDate != null
          ? _formatTankDate(batch.harvestDate!)
          : '--';
      showSampling = false;
    } else {
      abw = abl = 0;
      daysStr = lastSamplingStr = '--';
      showSampling = false;
    }

    if (abw <= 0) {
      stageLabel = '--';
    } else if (hasActive && isSelected) {
      stageLabel = tank.currentGrowthStage.label;
    } else {
      if (abw < 5 || abl < 4) {
        stageLabel = 'Early Juvenile';
      } else if (abw < 15 || abl < 6) {
        stageLabel = 'Advanced Juvenile';
      } else if (abw < 50 || abl < 10) {
        stageLabel = 'Pre-Adult';
      } else {
        stageLabel = 'Market Size';
      }
    }

    final biomassKg = hasActive && isSelected && abw > 0
        ? tank.inTankCount * abw / 1000
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.02),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _grayItem(Icons.eco, 'Stage', stageLabel)),
              Expanded(
                child: _grayItem(
                  Icons.monitor_weight_outlined,
                  'ABW',
                  abw > 0 ? '${abw.toStringAsFixed(2)}g' : '--',
                ),
              ),
              Expanded(
                child: _grayItem(
                  Icons.straighten,
                  'ABL',
                  abl > 0 ? '${abl.toStringAsFixed(2)}cm' : '--',
                ),
              ),
            ],
          ),
          if (hasActive) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            _buildGrayDetailRow(
              Icons.monitor_weight_outlined,
              'Estimated Biomass',
              '${biomassKg.toStringAsFixed(2)} kg',
            ),
            const SizedBox(height: 10),
          ],
          if (!hasActive)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
          _buildGrayDetailRow(
            Icons.hourglass_bottom,
            'Days in Culture',
            daysStr == '--' ? '--' : '${daysStr}d',
          ),
          const SizedBox(height: 8),
          _buildGrayDetailRow(
            Icons.calendar_today,
            'Stocking Date',
            batch != null ? _formatTankDate(batch.stockingDate) : '--',
          ),
          if (showSampling) ...[
            const SizedBox(height: 8),
            _buildGrayDetailRow(
              Icons.history,
              'Last Sampling',
              lastSamplingStr,
            ),
            const SizedBox(height: 8),
            _buildNextSamplingRow(),
          ],
          if (isArchived) ...[
            const SizedBox(height: 8),
            _buildGrayDetailRow(
              Icons.archive_rounded,
              'Harvested',
              '${batch.harvestCount}',
            ),
            if (batch.harvestWeightGrams != null) ...[
              const SizedBox(height: 8),
              _buildGrayDetailRow(
                Icons.monitor_weight_outlined,
                'Harvest Weight',
                '${batch.harvestWeightGrams!.toStringAsFixed(1)} g',
              ),
            ],
          ],
          if (hasActive && tank.harvestRecords.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildGrayDetailRow(
              Icons.archive_rounded,
              'Total Harvested',
              '${tank.harvestRecords.fold<int>(0, (s, r) => s + r.harvestedCount)}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _grayItem(IconData icon, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.darkWith(0.5)),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.dark,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w600,
            color: AppColors.darkWith(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildNextSamplingRow() {
    final tank = TankService.instance;
    if (!tank.isInitialized) {
      return _buildGrayDetailRow(Icons.calendar_today, 'Next Sampling', '--');
    }
    final daysLeft = tank.daysUntilNextSampling;
    final isReady = daysLeft == 0;
    final weekly = tank.samplingHistory.where((e) => !e.isBaseline).toList();
    String nextDateStr;
    if (weekly.isNotEmpty) {
      final lastSampling = weekly.last.date;
      final nextDate = lastSampling.add(const Duration(days: 7));
      nextDateStr = _formatTankDate(nextDate);
    } else {
      final nextDate = tank.stockingDate.add(const Duration(days: 7));
      nextDateStr = _formatTankDate(nextDate);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today,
              size: 14,
              color: AppColors.darkWith(0.5),
            ),
            const SizedBox(width: 8),
            Text(
              'Next Sampling',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.darkWith(0.7),
              ),
            ),
          ],
        ),
        isReady
            ? GestureDetector(
                onTap: () => widget.onTankTab?.call(1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Ready!',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FadeTransition(
                      opacity: _pulseAnimation,
                      child: Text(
                        'Tap to record',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    nextDateStr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _AnimatedDaysLeft(daysLeft: daysLeft),
                ],
              ),
      ],
    );
  }

  Widget _buildGrayDetailRow(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.darkWith(0.5)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.darkWith(0.7),
              ),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.dark,
          ),
        ),
      ],
    );
  }

  Widget _buildStatColumn(
    String iconPath,
    String value,
    String label, {
    Color? valueColor,
  }) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Image.asset(iconPath, fit: BoxFit.contain),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: valueColor ?? AppColors.dark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: AppColors.darkWith(0.6),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildFeedingScheduleCard() {
    final schedules = FeedState.schedules.value;
    final now = _manilaNow();
    final sensorService = SensorService.instance;
    final hasFeedLevel = sensorService.hasSensorData('feedlevel');
    final feedLevel = hasFeedLevel
        ? sensorService.getLatestValue('feedlevel')
        : null;
    final estimatedFeed = sensorService.estimatedFeedGrams;
    final feedStatus = _getStatus('feedlevel');
    final feedStatusColor = _getStatusColor('feedlevel');
    final consumptionToday = FeederService.instance.consumptionTodayGrams;
    final completedToday = FeederService.instance.completedFeedingsToday;

    final sorted = List<ScheduleItem>.from(schedules)
      ..sort(
        (a, b) => feederScheduleMinutes(a).compareTo(feederScheduleMinutes(b)),
      );

    ScheduleItem? lastFed;
    final statuses = <ScheduleItem, String>{};
    int completed = 0;
    int activeToday = 0;

    for (final s in sorted) {
      final status = _scheduleStatus(s, now);
      statuses[s] = status;
      if (feederScheduleRunsOnDate(s, now)) {
        final minutes = feederScheduleMinutes(s);
        final occurrence = DateTime(
          now.year,
          now.month,
          now.day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (feederScheduleWasEffectiveAt(s, occurrence)) activeToday++;
      }
      if (status == 'completed') {
        lastFed = s;
        completed++;
      }
    }

    final nextOccurrence = nextEnabledFeeding(
      sorted,
      now,
      skipToday: (schedule) =>
          const ['completed', 'skipped', 'failed'].contains(statuses[schedule]),
    );
    final nextFeed = nextOccurrence?.schedule;
    final nextFeedAt = nextOccurrence?.at;

    final progress = activeToday > 0 ? completed / activeToday : 0.0;

    String lastFedTime = '--';
    String lastFedDate = 'No feedings';
    if (lastFed != null) {
      lastFedTime = '${lastFed.time} ${lastFed.ampm}';
      lastFedDate = 'Today';
    }

    String nextTime = '--';
    String nextLabel = 'No enabled schedule';
    if (nextFeed != null && nextFeedAt != null) {
      nextTime = '${nextFeed.time} ${nextFeed.ampm}';
      final diff = nextFeedAt.difference(now);
      final days = diff.inDays;
      final dh = diff.inHours.remainder(24);
      final dm = diff.inMinutes.remainder(60);
      final ds = diff.inSeconds.remainder(60);
      final parts = <String>[];
      if (days > 0) parts.add('${days}d');
      if (dh > 0) parts.add('${dh}h');
      parts.add('${dm}m');
      parts.add('${ds}s');
      nextLabel = '${_feedingDayLabel(nextFeedAt, now)}\n${parts.join(' ')}';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bubble_chart, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'Automatic Feeder',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onControlTab?.call(0),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Feeding',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 9,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFeederSummaryTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'FEED LEVEL',
                  value: feedLevel == null
                      ? '--'
                      : '${feedLevel.toStringAsFixed(0)}%',
                  detail: feedLevel == null
                      ? 'No reading'
                      : estimatedFeed == null
                      ? feedStatus
                      : '$feedStatus • ~${estimatedFeed.toStringAsFixed(0)} g',
                  color: feedStatusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFeederSummaryTile(
                  icon: Icons.scale_outlined,
                  label: 'CONSUMPTION\nTODAY',
                  value: '~${consumptionToday.toStringAsFixed(0)} g',
                  detail:
                      '$completedToday completed feeding${completedToday == 1 ? '' : 's'}',
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 20,
                      color: AppColors.darkWith(0.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'LAST FED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkWith(0.5),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastFedTime,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastFedDate,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.dark,
                      ),
                    ),
                    if (lastFed?.grams != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${lastFed!.grams!.toStringAsFixed(1)}g',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(width: 1, height: 60, color: AppColors.darkWith(0.1)),
              Expanded(
                child: Column(
                  children: [
                    Icon(
                      Icons.calendar_month,
                      size: 20,
                      color: AppColors.darkWith(0.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'NEXT FEEDING',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkWith(0.5),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextTime,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nextLabel,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.dark,
                      ),
                    ),
                    if (nextFeed?.grams != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${nextFeed!.grams!.toStringAsFixed(1)}g',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (activeToday > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.darkWith(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$completed of $activeToday feedings today completed',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.dark,
              ),
            ),
          ] else if (schedules.any((schedule) => schedule.enabled)) ...[
            const SizedBox(height: 14),
            Text(
              'No feedings scheduled for today. The next active repeat day is shown above.',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.darkWith(0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeederSummaryTile({
    required IconData icon,
    required String label,
    required String value,
    required String detail,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 7.5,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.35,
                    color: AppColors.darkWith(0.5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkWith(0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _logDateString(DateTime date) {
    const months = [
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _scheduleStatus(ScheduleItem s, DateTime now) {
    if (!s.enabled) return 'disabled';
    if (!feederScheduleRunsOnDate(s, now)) return 'off_today';
    final outcome = feederRecordedOutcome(s, now, FeedState.feederLogs.value);
    if (outcome != null) return outcome;
    final scheduleTimeStr = '${s.time} ${s.ampm}';
    final todayStr = _logDateString(now);
    for (final log in FeedState.feederLogs.value) {
      if (log.type == 'missed' &&
          s.id != null &&
          log.scheduleKey == s.id &&
          log.scheduleTime == scheduleTimeStr &&
          log.date == todayStr) {
        return 'missed';
      }
    }
    final minutes = feederScheduleMinutes(s);
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final scheduleDt = DateTime(now.year, now.month, now.day, h, m);
    if (!feederScheduleWasEffectiveAt(s, scheduleDt)) return 'upcoming';
    if (now.isBefore(scheduleDt)) return 'upcoming';
    return 'pending';
  }

  String _feedingDayLabel(DateTime target, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(target.year, target.month, target.day);
    final dayOffset = targetDay.difference(today).inDays;
    if (dayOffset == 0) return 'Today';
    if (dayOffset == 1) return 'Tomorrow';
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdays[target.weekday - 1];
  }

  Widget _buildModalTrendIndicator(
    String trend,
    double rate,
    String status, {
    String? sensorKey,
    double? value,
  }) {
    final v = value ?? 0.0;
    final risingIsGood = sensorKey != null && _risingIsGood(sensorKey, v);
    final fallingIsGood = sensorKey != null && _fallingIsGood(sensorKey, v);
    final isBadStatus = status == 'CRITICAL' || status == 'WARNING';

    Color goodColor() => AppColors.success;
    Color badColor() => isBadStatus ? AppColors.critical : AppColors.warning;

    IconData icon;
    Color color;
    String label;

    switch (trend) {
      case 'rising_fast':
        icon = Icons.keyboard_double_arrow_up;
        label = 'Rising Fast';
        color = risingIsGood
            ? goodColor()
            : (fallingIsGood ? badColor() : AppColors.critical);
        break;
      case 'rising':
        icon = Icons.arrow_upward;
        label = 'Rising';
        color = risingIsGood
            ? goodColor()
            : (fallingIsGood ? badColor() : AppColors.warning);
        break;
      case 'falling_fast':
        icon = Icons.keyboard_double_arrow_down;
        label = 'Falling Fast';
        color = fallingIsGood
            ? goodColor()
            : (risingIsGood ? badColor() : AppColors.critical);
        break;
      case 'falling':
        icon = Icons.arrow_downward;
        label = 'Falling';
        color = fallingIsGood
            ? goodColor()
            : (risingIsGood ? badColor() : AppColors.warning);
        break;
      case 'stable':
      default:
        icon = Icons.trending_flat;
        color = AppColors.dark.withValues(alpha: 0.5);
        label = status == 'OPTIMAL' || status == 'NORMAL' ? 'Stable' : '';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: color),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ],
    );
  }

  void _showGaugeDetail(
    BuildContext context, {
    required String sensorKey,
    required String title,
    required String unit,
    required String ideal,
    required String iconPath,
  }) {
    final ranges = SettingsService.instance.currentRanges;
    final range = ranges[sensorKey] ?? {'min': 0.0, 'max': 0.0};
    final rMin = (range['min'] ?? 0.0).toDouble();
    final rMax = (range['max'] ?? 999.0).toDouble();
    final rUnit = _getUnit(sensorKey);

    final isMaxBound = rMax < 999.0;
    final rangeSpan = isMaxBound ? (rMax - rMin) : rMin;
    final warningThreshold = rangeSpan * 0.10;

    final checkLower = rMin > 0.0;
    final checkUpper = isMaxBound;

    String optimalRangeText = '';
    String warningRangeText = '';
    String criticalRangeText = '';

    if (checkLower && checkUpper) {
      final lowWarnEnd = rMin + warningThreshold;
      final highWarnStart = rMax - warningThreshold;
      optimalRangeText =
          '${lowWarnEnd.toStringAsFixed(1)}$rUnit \u2013 ${highWarnStart.toStringAsFixed(1)}$rUnit';
      warningRangeText =
          '${rMin.toStringAsFixed(1)}$rUnit \u2013 ${lowWarnEnd.toStringAsFixed(1)}$rUnit or ${highWarnStart.toStringAsFixed(1)}$rUnit \u2013 ${rMax.toStringAsFixed(1)}$rUnit';
      criticalRangeText =
          '< ${rMin.toStringAsFixed(1)}$rUnit or > ${rMax.toStringAsFixed(1)}$rUnit';
    } else if (checkLower) {
      final lowWarnEnd = rMin + warningThreshold;
      optimalRangeText = '> ${lowWarnEnd.toStringAsFixed(1)}$rUnit';
      warningRangeText =
          '${rMin.toStringAsFixed(1)}$rUnit \u2013 ${lowWarnEnd.toStringAsFixed(1)}$rUnit';
      criticalRangeText = '< ${rMin.toStringAsFixed(1)}$rUnit';
    } else if (checkUpper) {
      final highWarnStart = rMax - warningThreshold;
      optimalRangeText = '< ${highWarnStart.toStringAsFixed(1)}$rUnit';
      warningRangeText =
          '${highWarnStart.toStringAsFixed(1)}$rUnit \u2013 ${rMax.toStringAsFixed(1)}$rUnit';
      criticalRangeText = '> ${rMax.toStringAsFixed(1)}$rUnit';
    } else {
      optimalRangeText = 'Optimal range';
      warningRangeText = 'N/A';
      criticalRangeText = 'N/A';
    }

    final List<_LegendItem> legends;
    if (sensorKey == 'feedlevel') {
      final critical = (range['critical'] ?? 10.0).toDouble();
      legends = [
        _LegendItem(
          'Normal',
          '> ${rMin.toStringAsFixed(0)}%',
          'Enough feed is available in the hopper.',
          AppColors.success,
        ),
        _LegendItem(
          'Low',
          '> ${critical.toStringAsFixed(0)}% to ${rMin.toStringAsFixed(0)}%',
          'Refill is recommended soon.',
          AppColors.warning,
        ),
        _LegendItem(
          'Critical',
          '> 0% to ${critical.toStringAsFixed(0)}%',
          'Refill soon. Feeding may continue only when enough grams remain.',
          AppColors.critical,
        ),
        const _LegendItem(
          'Empty',
          '0%',
          'Feeding is blocked until the hopper is refilled.',
          AppColors.critical,
        ),
      ];
    } else {
      legends = [
        _LegendItem(
          'Optimal',
          optimalRangeText,
          'Stable and healthy environment.',
          AppColors.success,
        ),
        _LegendItem(
          'Warning',
          warningRangeText,
          'Approaching threshold. Action recommended.',
          AppColors.warning,
        ),
        _LegendItem(
          'Critical',
          criticalRangeText,
          'Dangerous levels. Immediate attention required.',
          AppColors.critical,
        ),
      ];
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: Listenable.merge([
            SensorService.instance,
            SettingsService.instance,
          ]),
          builder: (context, child) {
            final ss = SensorService.instance;
            final hasData = ss.hasSensorData(sensorKey);
            final value = ss.getLatestValue(sensorKey);
            final status = _getStatus(sensorKey);
            final statusColor = _getStatusColor(sensorKey);
            final formattedValue = !hasData
                ? '--'
                : value.toStringAsFixed(sensorKey == 'feedlevel' ? 0 : 2);

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Details',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark,
                            ),
                          ),
                          if (sensorKey != 'feedlevel')
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                widget.onViewGraph?.call(sensorKey);
                              },
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'View Live Graph',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  SizedBox(width: 3),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 11,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primaryWith(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(7),
                            child: Image.asset(iconPath),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFf7f7f7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  formattedValue,
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.dark,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  unit,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.darkWith(0.4),
                                  ),
                                ),
                              ],
                            ),
                            if (hasData) ...[
                              const SizedBox(height: 6),
                              _buildModalTrendIndicator(
                                ss.getTrend(sensorKey),
                                ss.getTrendRate(sensorKey),
                                status,
                                sensorKey: sensorKey,
                                value: value,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryWith(0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 10,
                                color: AppColors.primaryWith(0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasData
                                    ? _formatTimestamp(
                                        SensorService.instance.lastUpdated,
                                      )
                                    : 'Captured: --',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.darkWith(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...legends.map(
                        (l) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFf9f9f9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 2),
                                  decoration: BoxDecoration(
                                    color: l.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.label,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.dark,
                                        ),
                                      ),
                                      Text(
                                        l.range,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: const Color(
                                            0xFF0B3C49,
                                          ).withValues(alpha: 0.75),
                                        ),
                                      ),
                                      Text(
                                        l.desc,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: const Color(
                                            0xFF0B3C49,
                                          ).withValues(alpha: 0.65),
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return 'Captured: $h:$m:$s $ampm';
  }
}

class _GaugeCard extends StatefulWidget {
  final String title;
  final String value;
  final String unit;
  final String ideal;
  final String iconPath;
  final String status;
  final Color statusColor;
  final String trend;
  final double trendRate;
  final Color trendColor;
  final bool hasData;
  final String sensorKey;
  final double rawValue;
  final VoidCallback? onTap;

  const _GaugeCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.ideal,
    required this.iconPath,
    required this.status,
    required this.statusColor,
    required this.trend,
    required this.trendRate,
    required this.trendColor,
    required this.hasData,
    required this.sensorKey,
    required this.rawValue,
    this.onTap,
  });

  @override
  State<_GaugeCard> createState() => _GaugeCardState();
}

class _GaugeCardState extends State<_GaugeCard> {
  bool _isPressed = false;

  Widget _buildTrendIndicator() {
    IconData icon;
    String label;
    final color = widget.trendColor;

    switch (widget.trend) {
      case 'rising_fast':
        icon = Icons.keyboard_double_arrow_up;
        label = 'Rising Fast';
        break;
      case 'rising':
        icon = Icons.arrow_upward;
        label = 'Rising';
        break;
      case 'falling_fast':
        icon = Icons.keyboard_double_arrow_down;
        label = 'Falling Fast';
        break;
      case 'falling':
        icon = Icons.arrow_downward;
        label = 'Falling';
        break;
      case 'stable':
      default:
        icon = Icons.trending_flat;
        label = widget.status == 'OPTIMAL' ? 'Stable' : '';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 12, color: color),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      child: Material(
        color: _isPressed ? AppColors.primaryWith(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isPressed
                    ? AppColors.primaryWith(0.24)
                    : AppColors.darkWith(0.08),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Image.asset(widget.iconPath),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dark,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        widget.value,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.dark,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.unit,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                if (widget.hasData) _buildTrendIndicator(),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: widget.statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.status,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: widget.statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Text(
                    widget.ideal,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendItem {
  final String label;
  final String range;
  final String desc;
  final Color color;
  const _LegendItem(this.label, this.range, this.desc, this.color);
}

class _QuickActionData {
  final String name;
  final IconData icon;
  final String? status;
  final VoidCallback? onTap;
  const _QuickActionData(this.name, this.icon, this.status, {this.onTap});
}

class _AnimatedDaysLeft extends StatefulWidget {
  final int daysLeft;
  const _AnimatedDaysLeft({required this.daysLeft});

  @override
  State<_AnimatedDaysLeft> createState() => _AnimatedDaysLeftState();
}

class _AnimatedDaysLeftState extends State<_AnimatedDaysLeft>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Text(
        '${widget.daysLeft} day${widget.daysLeft == 1 ? '' : 's'} left',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
