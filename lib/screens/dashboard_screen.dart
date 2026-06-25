import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../widgets/section_label.dart';
import '../services/sensor_service.dart';
import '../services/settings_service.dart';
import '../services/tank_service.dart';
import '../models/control_types.dart';

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
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _quickActionsController = ScrollController();
  Timer? _countdownTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _quickActionsController.dispose();
    SensorService.instance.removeListener(_refreshUI);
    SettingsService.instance.removeListener(_refreshUI);
    TankService.instance.removeListener(_refreshUI);
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _refreshUI() {
    if (!mounted) return;
    setState(() {});
  }

  // LOGIC PARA KUNIN ANG FIRST NAME LANG NG NAKA-LOGIN
  String _getFirstName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null &&
        user.displayName != null &&
        user.displayName!.isNotEmpty) {
      // I-split ang pangalan gamit ang space, tapos kunin ang pinakaunang salita
      return user.displayName!.trim().split(' ').first;
    }
    return 'Farmer'; // Fallback kapag walang pangalan
  }

  // DYNAMIC GREETING DEPENDE SA ORAS NGAYON
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
            _buildWaterLevelGauge(context),
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
    );
  }

  Widget _buildGreeting() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
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

    if (hasAnyData && error == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: error != null
            ? const Color(0xFFFFF3F0)
            : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: error != null
              ? const Color(0xFFFFCCBB)
              : const Color(0xFFFFE082),
        ),
      ),
      child: Row(
        children: [
          Icon(
            error != null ? Icons.error_outline : Icons.info_outline,
            size: 16,
            color: error != null
                ? const Color(0xFFD84315)
                : const Color(0xFFF9A825),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error ?? 'Waiting for sensor data...',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: error != null
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
                    ideal: '25 \u2013 30\u00B0C',
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
                    ideal: '7.0 \u2013 8.5',
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
                    ideal: '>5.0 mg/L',
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
                    ideal: '0 \u2013 25 NTU',
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
    if (max >= 999) return 'Ideal: > ${min.toStringAsFixed(1)}$unit';
    return 'Ideal: ${min.toStringAsFixed(1)} \u2013 ${_formatMax(max)}$unit';
  }

  String _getStatus(String key) {
    final ss = SensorService.instance;
    if (!ss.hasSensorData(key)) return 'No reading';
    return ss.getZone(key);
  }

  Color _getStatusColor(String key) {
    final ss = SensorService.instance;
    if (!ss.hasSensorData(key)) return AppColors.darkWith(0.3);
    final zone = ss.getZone(key);
    if (zone == 'OPTIMAL') return AppColors.success;
    if (zone == 'WARNING') return AppColors.warning;
    if (zone == 'CRITICAL') return AppColors.critical;
    return AppColors.darkWith(0.4);
  }

  Color _getTrendColor(String key, double value, String trend, double rate, String status) {
    if (key == 'do') {
      if (trend == 'rising' || trend == 'rising_fast') return AppColors.success;
      if (trend == 'falling' || trend == 'falling_fast') {
        return status == 'CRITICAL' || status == 'WARNING' ? AppColors.critical : AppColors.warning;
      }
      return AppColors.dark.withValues(alpha: 0.4);
    }

    if (key == 'turb') {
      if (trend == 'falling' || trend == 'falling_fast') return AppColors.success;
      if (trend == 'rising' || trend == 'rising_fast') {
        return status == 'CRITICAL' || status == 'WARNING' ? AppColors.critical : AppColors.warning;
      }
      return AppColors.dark.withValues(alpha: 0.4);
    }

    if (key == 'waterlevel') {
      if (trend == 'rising' || trend == 'rising_fast') return AppColors.success;
      if (trend == 'falling' || trend == 'falling_fast') {
        return status == 'CRITICAL' || status == 'WARNING' ? AppColors.critical : AppColors.warning;
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
    final trendColor = _getTrendColor(sensorKey, rawValue, trend, trendRate, status);
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

  Widget _buildWaterLevelGauge(BuildContext context) {
    final ss = SensorService.instance;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
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
          ideal: '130 \u2013 180 cm',
          iconPath: 'assets/images/waterLevel.png',
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
        'Pump',
        Icons.water_drop,
        null,
        onTap: control != null ? () => control(1) : null,
      ),
      _QuickActionData(
        'Feeder',
        Icons.bubble_chart,
        null,
        onTap: control != null ? () => control(0) : null,
      ),
      _QuickActionData(
        'Inventory',
        Icons.inventory_2_outlined,
        null,
        onTap: tank != null ? () => tank(0) : null,
      ),
      _QuickActionData(
        'Sampling',
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
                border: Border.all(color: AppColors.darkWith(0.1)),
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
    final hasData = tank.isInitialized;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Text(
                      'Tank Status',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.dark),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: _buildStatColumn('assets/images/InitialPopulationNo.png', hasData ? tank.initialCount.toString() : '--', 'initialPopulation')),
                    Expanded(child: _buildStatColumn('assets/images/SurvivalRate.png', hasData ? '${tank.survivalRate.toStringAsFixed(1)}%' : '--', 'Survival Rate')),
                    Expanded(child: _buildStatColumn('assets/images/AliveNo.png', hasData ? tank.liveCount.toString() : '--', 'Alive')),
                    Expanded(child: _buildStatColumn('assets/images/mortalityNo.png', hasData ? tank.mortality.toString() : '--', 'Mortality')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildCurrentStageSection(tank),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.darkWith(0.02),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    _buildEstimatedBiomassRow(tank, hasData),
                    const SizedBox(height: 8),
                    _buildDetailRow(Icons.hourglass_bottom, 'Days in Culture', hasData ? tank.daysInCulture.toString() : '--'),
                    const SizedBox(height: 8),
                    _buildDetailRow(Icons.history, 'Last Sampling', hasData && tank.samplingHistory.isNotEmpty ? _formatTankDate(tank.samplingHistory.last.date) : '--'),
                    const SizedBox(height: 8),
                    _buildNextSamplingRow(),
                  ],
                ),
              ),
            ],
          ),
        );
  }

  static const _stageRules = [
    (label: 'Early Juvenile', min: 1.0, max: 5.0),
    (label: 'Advanced Juvenile', min: 5.0, max: 15.0),
    (label: 'Pre-Adult', min: 15.0, max: 50.0),
    (label: 'Market Size', min: 50.0, max: 100.0),
  ];

  Widget _buildCurrentStageSection(TankService tank) {
    final history = tank.samplingHistory;
    final hasGrowthData = tank.isInitialized && tank.initialCount > 0;
    final currentAbw = hasGrowthData ? (history.isNotEmpty ? history.last.abw : tank.initialWeight) : 0.0;
    final currentAbl = hasGrowthData ? (history.isNotEmpty ? history.last.avgLength : tank.initialLength) : 0.0;

    String stageLabel;
    bool isReady;
    if (!hasGrowthData) {
      stageLabel = '--';
      isReady = false;
    } else {
      int activeIndex = 0;
      for (int i = 0; i < _stageRules.length; i++) {
        final rule = _stageRules[i];
        if (i == _stageRules.length - 1) {
          if (currentAbw >= rule.min) activeIndex = i;
        } else {
          if (currentAbw >= rule.min && currentAbw < rule.max) activeIndex = i;
        }
      }
      stageLabel = _stageRules[activeIndex].label;
      isReady = true;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.eco, size: 16, color: Color(0xFF9E9E9E)),
                  const SizedBox(width: 6),
                  Text('Current Crayfish Stage:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.7))),
                ],
              ),
              Text(stageLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isReady ? AppColors.primary : AppColors.darkWith(0.4))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('ABW: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5))),
              Text(isReady ? '${currentAbw.toStringAsFixed(2)}g' : '--', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.dark)),
              const SizedBox(width: 16),
              Text('ABL: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5))),
              Text(isReady ? '${currentAbl.toStringAsFixed(2)}cm' : '--', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.dark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String iconPath, String value, String label) {
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
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.dark,
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

  Widget _buildEstimatedBiomassRow(TankService tank, bool hasData) {
    final history = tank.samplingHistory;
    final latestAbw = hasData && history.isNotEmpty
        ? history.last.abw
        : tank.initialWeight;
    final biomassKg = hasData && latestAbw > 0
        ? tank.liveCount * latestAbw / 1000
        : 0.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monitor_weight_outlined, size: 14, color: AppColors.darkWith(0.5)),
            const SizedBox(width: 8),
            Text(
              'Estimated Biomass',
              style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.6)),
            ),
          ],
        ),
        Text(
          hasData ? '${biomassKg.toStringAsFixed(2)} kg' : '--',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.dark,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
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
            fontWeight: FontWeight.w600,
            color: AppColors.dark,
          ),
        ),
      ],
    );
  }

  Widget _buildNextSamplingRow() {
    final tank = TankService.instance;
    if (!tank.isInitialized) {
      return _buildDetailRow(Icons.calendar_today, 'Next Sampling', '--');
    }
    final daysLeft = tank.daysUntilNextSampling;
    final isReady = daysLeft == 0;

    String nextDateStr;
    if (tank.samplingHistory.isNotEmpty) {
      final lastSampling = tank.samplingHistory.last.date;
      final nextDate = lastSampling.add(const Duration(days: 7));
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
      nextDateStr =
          '${months[nextDate.month - 1]} ${nextDate.day}, ${nextDate.year}';
    } else {
      final nextDate = tank.stockingDate.add(const Duration(days: 7));
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
      nextDateStr =
          '${months[nextDate.month - 1]} ${nextDate.day}, ${nextDate.year}';
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
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
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
                          color: AppColors.success,
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

  Widget _buildFeedingScheduleCard() {
    final schedules = FeedState.schedules.value;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    List<ScheduleItem> sorted = List.from(schedules);
    sorted.sort((a, b) {
      int aMin = _toScheduleMinutes(a);
      int bMin = _toScheduleMinutes(b);
      return aMin.compareTo(bMin);
    });

    ScheduleItem? lastFed;
    ScheduleItem? nextFeed;
    int completed = 0;

    for (final s in sorted) {
      final status = _scheduleStatus(s, now, nowMin);
      if (status == 'completed') {
        lastFed = s;
        completed++;
      } else if (status == 'upcoming') {
        nextFeed ??= s;
      }
    }

    final total = sorted.length;
    final progress = total > 0 ? completed / total : 0.0;

    String lastFedTime = '--';
    String lastFedDate = 'No feedings';
    if (lastFed != null) {
      lastFedTime = '${lastFed.time} ${lastFed.ampm}';
      lastFedDate = 'Today';
    }

    String nextTime = '--';
    String nextLabel = 'No upcoming';
    if (nextFeed != null) {
      nextTime = '${nextFeed.time} ${nextFeed.ampm}';
      int h = int.parse(nextFeed.time.split(':')[0]);
      final m = int.parse(nextFeed.time.split(':')[1]);
      if (nextFeed.ampm == 'PM' && h != 12) h += 12;
      if (nextFeed.ampm == 'AM' && h == 12) h = 0;
      final target = DateTime(now.year, now.month, now.day, h, m);
      final diff = target.isAfter(now)
          ? target.difference(now)
          : target.add(const Duration(days: 1)).difference(now);
      final dh = diff.inHours;
      final dm = diff.inMinutes.remainder(60);
      final ds = diff.inSeconds.remainder(60);
      final parts = <String>[];
      if (dh > 0) parts.add('${dh}h');
      parts.add('${dm}m');
      parts.add('${ds}s');
      nextLabel = parts.join(' ');
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bubble_chart, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'Feeding Schedule',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.dark,
                      ),
                    ),
                    if (nextFeed?.grams != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          if (total > 0) ...[
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
              '$completed of $total feedings today completed',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.dark,
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _toScheduleMinutes(ScheduleItem s) {
    int h = int.tryParse(s.time.split(':')[0]) ?? 6;
    final m = int.tryParse(s.time.split(':')[1]) ?? 0;
    if (s.ampm == 'PM' && h != 12) h += 12;
    if (s.ampm == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  }

  String _logDateString() {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  String _scheduleStatus(ScheduleItem s, DateTime now, int nowMin) {
    if (s.isDone) return 'completed';
    final scheduleTimeStr = '${s.time} ${s.ampm}';
    final todayStr = _logDateString();
    for (final log in FeedState.feederLogs.value) {
      if (log.action == 'Auto feed dispensed' &&
          log.time == scheduleTimeStr &&
          log.date == todayStr) {
        return 'completed';
      }
    }
    int h = int.tryParse(s.time.split(':')[0]) ?? 6;
    final m = int.tryParse(s.time.split(':')[1]) ?? 0;
    if (s.ampm == 'PM' && h != 12) h += 12;
    if (s.ampm == 'AM' && h == 12) h = 0;
    final scheduleDt = DateTime(now.year, now.month, now.day, h, m);
    final diffSec = now.difference(scheduleDt).inSeconds;
    if (diffSec > 120) return 'skipped';
    if (diffSec >= 0) return 'pending';
    return 'upcoming';
  }

  Widget _buildModalTrendIndicator(String trend, double rate, String status, {String? sensorKey}) {
    IconData icon;
    Color color;
    String label;

    if (sensorKey == 'do') {
      switch (trend) {
        case 'rising_fast':
          icon = Icons.keyboard_double_arrow_up;
          color = AppColors.success;
          label = 'Rising Fast';
          break;
        case 'rising':
          icon = Icons.arrow_upward;
          color = AppColors.success;
          label = 'Rising';
          break;
        case 'falling_fast':
          icon = Icons.keyboard_double_arrow_down;
          color = status == 'CRITICAL' || status == 'WARNING' ? AppColors.critical : AppColors.warning;
          label = 'Falling Fast';
          break;
        case 'falling':
          icon = Icons.arrow_downward;
          color = status == 'CRITICAL' || status == 'WARNING' ? AppColors.critical : AppColors.warning;
          label = 'Falling';
          break;
        default:
          icon = Icons.trending_flat;
          color = AppColors.dark.withValues(alpha: 0.5);
          label = status == 'OPTIMAL' ? 'Stable' : '';
          break;
      }
    } else if (sensorKey == 'turb') {
      switch (trend) {
        case 'falling_fast':
          icon = Icons.keyboard_double_arrow_down;
          color = AppColors.success;
          label = 'Falling Fast';
          break;
        case 'falling':
          icon = Icons.arrow_downward;
          color = AppColors.success;
          label = 'Falling';
          break;
        case 'rising_fast':
          icon = Icons.keyboard_double_arrow_up;
          color = status == 'CRITICAL' || status == 'WARNING' ? AppColors.critical : AppColors.warning;
          label = 'Rising Fast';
          break;
        case 'rising':
          icon = Icons.arrow_upward;
          color = status == 'CRITICAL' || status == 'WARNING' ? AppColors.critical : AppColors.warning;
          label = 'Rising';
          break;
        default:
          icon = Icons.trending_flat;
          color = AppColors.dark.withValues(alpha: 0.5);
          label = status == 'OPTIMAL' ? 'Stable' : '';
          break;
      }
    } else if (sensorKey == 'waterlevel') {
      switch (trend) {
        case 'rising_fast':
          icon = Icons.keyboard_double_arrow_up;
          color = AppColors.success;
          label = 'Rising Fast';
          break;
        case 'rising':
          icon = Icons.arrow_upward;
          color = AppColors.success;
          label = 'Rising';
          break;
        case 'falling_fast':
          icon = Icons.keyboard_double_arrow_down;
          color = status == 'CRITICAL' || status == 'WARNING' ? AppColors.critical : AppColors.warning;
          label = 'Falling Fast';
          break;
        case 'falling':
          icon = Icons.arrow_downward;
          color = status == 'CRITICAL' || status == 'WARNING' ? AppColors.critical : AppColors.warning;
          label = 'Falling';
          break;
        default:
          icon = Icons.trending_flat;
          color = AppColors.dark.withValues(alpha: 0.5);
          label = status == 'OPTIMAL' ? 'Stable' : '';
          break;
      }
    } else {
      switch (trend) {
        case 'rising_fast':
          icon = Icons.keyboard_double_arrow_up;
          color = AppColors.critical;
          label = 'Rising Fast';
          break;
        case 'rising':
          icon = Icons.arrow_upward;
          color = AppColors.warning;
          label = 'Rising';
          break;
        case 'falling_fast':
          icon = Icons.keyboard_double_arrow_down;
          color = AppColors.critical;
          label = 'Falling Fast';
          break;
        case 'falling':
          icon = Icons.arrow_downward;
          color = AppColors.warning;
          label = 'Falling';
          break;
        case 'stable':
        default:
          icon = Icons.trending_flat;
          color = AppColors.dark.withValues(alpha: 0.5);
          label = status == 'OPTIMAL' ? 'Stable' : '';
          break;
      }
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
      optimalRangeText = '${lowWarnEnd.toStringAsFixed(1)}$rUnit \u2013 ${highWarnStart.toStringAsFixed(1)}$rUnit';
      warningRangeText = '${rMin.toStringAsFixed(1)}$rUnit \u2013 ${lowWarnEnd.toStringAsFixed(1)}$rUnit or ${highWarnStart.toStringAsFixed(1)}$rUnit \u2013 ${rMax.toStringAsFixed(1)}$rUnit';
      criticalRangeText = '< ${rMin.toStringAsFixed(1)}$rUnit or > ${rMax.toStringAsFixed(1)}$rUnit';
    } else if (checkLower) {
      final lowWarnEnd = rMin + warningThreshold;
      optimalRangeText = '> ${lowWarnEnd.toStringAsFixed(1)}$rUnit';
      warningRangeText = '${rMin.toStringAsFixed(1)}$rUnit \u2013 ${lowWarnEnd.toStringAsFixed(1)}$rUnit';
      criticalRangeText = '< ${rMin.toStringAsFixed(1)}$rUnit';
    } else if (checkUpper) {
      final highWarnStart = rMax - warningThreshold;
      optimalRangeText = '< ${highWarnStart.toStringAsFixed(1)}$rUnit';
      warningRangeText = '${highWarnStart.toStringAsFixed(1)}$rUnit \u2013 ${rMax.toStringAsFixed(1)}$rUnit';
      criticalRangeText = '> ${rMax.toStringAsFixed(1)}$rUnit';
    } else {
      optimalRangeText = 'Optimal range';
      warningRangeText = 'N/A';
      criticalRangeText = 'N/A';
    }

    final legends = [
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
                : value.toStringAsFixed(2);

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
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onViewGraph?.call(sensorKey);
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'View Live Graph',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
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
                            _buildModalTrendIndicator(ss.getTrend(sensorKey), ss.getTrendRate(sensorKey), status, sensorKey: sensorKey),
                          ]
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
                    if (hasData) ...[
                      const SizedBox(height: 4),
                    ],
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _isPressed
                ? AppColors.darkWith(0.16)
                : AppColors.darkWith(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: _isPressed ? AppColors.darkWith(0.03) : const Color(0xFFFCFCFC),
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
                    ? AppColors.darkWith(0.25)
                    : AppColors.darkWith(0.15),
                width: 1.5,
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


