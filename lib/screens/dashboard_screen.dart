import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../widgets/section_label.dart';
import '../services/sensor_service.dart';
import '../services/settings_service.dart';
import '../models/control_types.dart';

class DashboardScreen extends StatefulWidget {
  final ValueChanged<String>? onViewGraph;
  final ValueChanged<int>? onNavigate;
  final ValueChanged<int>? onTankTab;

  const DashboardScreen({super.key, this.onViewGraph, this.onNavigate, this.onTankTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _quickActionsController = ScrollController();
  Timer? _countdownTimer;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    SensorService.instance.addListener(_refreshUI);
    SettingsService.instance.addListener(_refreshUI);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _quickActionsController.dispose();
    SensorService.instance.removeListener(_refreshUI);
    SettingsService.instance.removeListener(_refreshUI);
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _refreshUI() {
    if (!mounted) return;
    final isOnline = SensorService.instance.isEspOnline;
    if (isOnline && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!isOnline && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildGreeting(),
            _buildConnectionStatus(),
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

  Widget _buildConnectionStatus() {
    final ss = SensorService.instance;
    final err = ss.lastError;
    final isOnline = ss.isEspOnline;
    final hasData = ss.lastUpdated.millisecondsSinceEpoch > 0;

    final statusColor = err != null
        ? AppColors.critical
        : isOnline
            ? const Color(0xFF22c55e)
            : hasData
                ? AppColors.critical
                : AppColors.warning;
    final statusLabel = err != null
        ? 'Firebase Error'
        : isOnline
            ? 'ESP32 Connected'
            : hasData
                ? 'ESP32 Offline'
                : 'Awaiting ESP32';

    String syncText;
    if (err != null) {
      syncText = err.length > 80 ? '${err.substring(0, 80)}...' : err;
    } else if (!hasData) {
      syncText = 'Waiting for sensor data...';
    } else {
      final t = ss.lastUpdated;
      final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
      final ampm = t.hour >= 12 ? 'PM' : 'AM';
      final m = t.minute.toString().padLeft(2, '0');
      final s = t.second.toString().padLeft(2, '0');
      syncText = 'Last sync: $h:$m:$s $ampm';
    }

    final bgColor = err != null
        ? const Color(0xFFFEF2F2)
        : isOnline
            ? const Color(0xFFF0FDF0)
            : hasData
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFFFFBEb);

    final borderColor = err != null
        ? AppColors.critical.withValues(alpha: 0.3)
        : isOnline
            ? const Color(0xFF22c55e).withValues(alpha: 0.15)
            : hasData
                ? AppColors.critical.withValues(alpha: 0.15)
            : AppColors.warning.withValues(alpha: 0.3);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            err != null
                ? const Icon(Icons.error_outline, size: 14, color: AppColors.critical)
                : isOnline
                    ? AnimatedBuilder(
                        animation: _pulseController,
                        builder: (_, _) {
                          final p = _pulseController.value;
                          return Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.1 + p * 0.4),
                                  blurRadius: 1 + p * 5,
                                  spreadRadius: p * 2,
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    syncText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (isOnline)
              AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, _) {
                  final p = _pulseController.value;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85 + p * 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF22c55e).withValues(alpha: 0.2 + p * 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22c55e).withValues(alpha: 0.05 + p * 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22c55e).withValues(alpha: 0.6 + p * 0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF22c55e).withValues(alpha: 0.7 + p * 0.3),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
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
                  value: ss.hasSensorData('temp') ? ss.getLatestValue('temp').toStringAsFixed(1) : '--',
                  unit: '\u00B0C',
                  ideal: _getIdealText('temp'),
                  iconPath: 'assets/images/temperature.png',
                  status: _getStatus('temp'),
                  statusColor: _getStatusColor('temp'),
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
                  value: ss.hasSensorData('ph') ? ss.getLatestValue('ph').toStringAsFixed(1) : '--',
                  unit: 'pH',
                  ideal: _getIdealText('ph'),
                  iconPath: 'assets/images/pH.png',
                  status: _getStatus('ph'),
                  statusColor: _getStatusColor('ph'),
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
                  value: ss.hasSensorData('do') ? ss.getLatestValue('do').toStringAsFixed(1) : '--',
                  unit: 'mg/L',
                  ideal: _getIdealText('do'),
                  iconPath: 'assets/images/DO.png',
                  status: _getStatus('do'),
                  statusColor: _getStatusColor('do'),
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
                  value: ss.isTurbidityAir ? '--' : (ss.hasSensorData('turb') ? ss.getLatestValue('turb').toStringAsFixed(0) : '--'),
                  unit: ss.isTurbidityAir ? '' : 'NTU',
                  ideal: ss.isTurbidityAir ? '' : _getIdealText('turb'),
                  iconPath: 'assets/images/Turbidity.png',
                  status: ss.isTurbidityAir ? 'NO WATER' : _getStatus('turb'),
                  statusColor: ss.isTurbidityAir ? AppColors.warning : _getStatusColor('turb'),
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
      case 'temp': return '\u00B0C';
      case 'ph': return 'pH';
      case 'do': return 'mg/L';
      case 'turb': return 'NTU';
      case 'waterlevel': return 'cm';
      default: return '';
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
    if (zone == 'CRITICAL') return AppColors.critical;
    return AppColors.darkWith(0.4);
  }

  Widget _buildGaugeCard({
    required String title,
    required String value,
    required String unit,
    required String ideal,
    required String iconPath,
    required String status,
    required Color statusColor,
    VoidCallback? onTap,
  }) {
    return _GaugeCard(
      title: title,
      value: value,
      unit: unit,
      ideal: ideal,
      iconPath: iconPath,
      status: status,
      statusColor: statusColor,
      onTap: onTap,
    );
  }

  Widget _buildWaterLevelGauge(BuildContext context) {
    final ss = SensorService.instance;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _buildGaugeCard(
        title: 'Water Level',
        value: ss.hasSensorData('waterlevel') ? ss.getLatestValue('waterlevel').toStringAsFixed(0) : '--',
        unit: 'cm',
          ideal: _getIdealText('waterlevel'),
        iconPath: 'assets/images/waterLevel.png',
        status: _getStatus('waterlevel'),
        statusColor: _getStatusColor('waterlevel'),
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
    final nav = widget.onNavigate;
    final tank = widget.onTankTab;
    final actions = [
      _QuickActionData('Aerator', Icons.air, 'Active', onTap: nav != null ? () => nav(3) : null),
      _QuickActionData('Pump', Icons.water_drop, 'Idle', onTap: nav != null ? () => nav(3) : null),
      _QuickActionData('Feed', Icons.bubble_chart, 'Auto', onTap: nav != null ? () => nav(3) : null),
      _QuickActionData('Inventory', Icons.inventory_2_outlined, null, onTap: tank != null ? () => tank(0) : null),
      _QuickActionData('Sampling', Icons.speed_rounded, null, onTap: tank != null ? () => tank(1) : null),
      _QuickActionData('Growth Trends', Icons.trending_up_rounded, null, onTap: tank != null ? () => tank(2) : null),
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
                Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Tank Status',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
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
                    '68',
                    'Initial Population',
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    'assets/images/SurvivalRate.png',
                    '92.6%',
                    'Survival Rate',
                  ),
                ),
                Expanded(
                  child: _buildStatColumn('assets/images/AliveNo.png', '63', 'Alive'),
                ),
                Expanded(
                  child: _buildStatColumn('assets/images/mortalityNo.png', '5', 'Mortality'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.darkWith(0.02),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                _buildDetailRow(
                  Icons.hourglass_bottom,
                  'Days in Culture',
                  '45',
                ),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.history, 'Last Sampling', 'May 12, 2026'),
                const SizedBox(height: 8),
                _buildDetailRow(
                  Icons.calendar_today,
                  'Next Sampling',
                  'May 19, 2026',
                ),
              ],
            ),
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
      final sMin = _toScheduleMinutes(s);
      if (sMin <= nowMin) {
        lastFed = s;
        completed++;
      } else if (nextFeed == null) {
        nextFeed = s;
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
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: AppColors.darkWith(0.1),
                  ),
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
                      ],
                    ),
                  ),
                ],
              ),
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
    final legends = [
      _LegendItem(
        'Optimal',
        rMax >= 999
            ? '> ${rMin.toStringAsFixed(1)}$rUnit'
            : '${rMin.toStringAsFixed(1)}$rUnit \u2013 ${_formatMax(rMax)}$rUnit',
        'Within optimal range for current stage.',
        AppColors.success,
      ),
      _LegendItem(
        'Critical',
        rMax >= 999
            ? '< ${rMin.toStringAsFixed(1)}$rUnit'
            : 'Outside ${rMin.toStringAsFixed(1)}$rUnit \u2013 ${_formatMax(rMax)}$rUnit',
        'Outside optimal range.',
        AppColors.critical,
      ),
    ];

    showModalBottomSheet(
      context: context,
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
            final isTurbAir = sensorKey == 'turb' && ss.isTurbidityAir;
            final status = isTurbAir ? 'NO WATER' : _getStatus(sensorKey);
            final statusColor = isTurbAir ? AppColors.warning : _getStatusColor(sensorKey);
            final formattedValue = isTurbAir
                ? '--'
                : !hasData
                ? '--'
                : sensorKey == 'turb' || sensorKey == 'waterlevel'
                ? value.toStringAsFixed(0)
                : value.toStringAsFixed(1);

            return SafeArea(
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
                      child: Row(
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
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        ideal,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkWith(0.5),
                        ),
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
                              _formatTimestamp(
                                SensorService.instance.lastUpdated,
                              ),
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
  final VoidCallback? onTap;

  const _GaugeCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.ideal,
    required this.iconPath,
    required this.status,
    required this.statusColor,
    this.onTap,
  });

  @override
  State<_GaugeCard> createState() => _GaugeCardState();
}

class _GaugeCardState extends State<_GaugeCard> {
  bool _isPressed = false;

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
