import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Added for Firebase integration
import '../theme/app_colors.dart';
import '../widgets/section_label.dart';
import '../services/sensor_service.dart';
import '../services/settings_service.dart';

class DashboardScreen extends StatefulWidget {
  final ValueChanged<String>? onViewGraph;

  const DashboardScreen({super.key, this.onViewGraph});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _quickActionsController = ScrollController();

  @override
  void initState() {
    super.initState();
    SensorService.instance.addListener(_refreshUI);
    SettingsService.instance.addListener(_refreshUI);
  }

  @override
  void dispose() {
    _quickActionsController.dispose();
    SensorService.instance.removeListener(_refreshUI);
    SettingsService.instance.removeListener(_refreshUI);
    super.dispose();
  }

  void _refreshUI() {
    if (mounted) setState(() {});
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                _buildGreeting(),
                Positioned(bottom: -20, right: 12, child: _buildLiveTag()),
              ],
            ),
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

  Widget _buildLiveTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF22c55e).withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildMiniGraphBar(4),
              _buildMiniGraphBar(7),
              _buildMiniGraphBar(5),
            ],
          ),
          const SizedBox(width: 6),
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: Color(0xFF22c55e),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: Color(0xFF22c55e),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniGraphBar(double height) {
    return Container(
      width: 2,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
      decoration: BoxDecoration(
        color: const Color(0xFF22c55e).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildGaugeGrid(BuildContext context) {
    final temp = SensorService.instance.getLatestValue('temp');
    final ph = SensorService.instance.getLatestValue('ph');
    final dO2 = SensorService.instance.getLatestValue('do');
    final turb = SensorService.instance.getLatestValue('turb');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildGaugeCard(
                  title: 'Temperature',
                  value: temp.toStringAsFixed(1),
                  unit: '\u00B0C',
                  ideal: 'Ideal: 25 \u2013 30\u00B0C',
                  iconPath: 'assets/images/temperature.png',
                  status: _getStatus('temp', temp),
                  statusColor: _getStatusColor('temp', temp),
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
                  value: ph.toStringAsFixed(1),
                  unit: 'pH',
                  ideal: 'Ideal: 7.0 \u2013 8.5',
                  iconPath: 'assets/images/pH.png',
                  status: _getStatus('ph', ph),
                  statusColor: _getStatusColor('ph', ph),
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
                  value: dO2.toStringAsFixed(1),
                  unit: 'mg/L',
                  ideal: 'Ideal: >5.0 mg/L',
                  iconPath: 'assets/images/DO.png',
                  status: _getStatus('do', dO2),
                  statusColor: _getStatusColor('do', dO2),
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
                  value: turb.toStringAsFixed(0),
                  unit: 'NTU',
                  ideal: 'Ideal: 0 \u2013 25 NTU',
                  iconPath: 'assets/images/Turbidity.png',
                  status: _getStatus('turb', turb),
                  statusColor: _getStatusColor('turb', turb),
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

  String _getStatus(String key, double val) {
    final zone = SensorService.instance.getZone(key);
    return zone;
  }

  Color _getStatusColor(String key, double val) {
    final zone = SensorService.instance.getZone(key);
    if (zone == 'SENSOR ERROR' || zone == 'PLACEHOLDER') {
      return AppColors.mutedText;
    }
    if (zone == 'CRITICAL LOW' ||
        zone == 'CRITICAL HIGH' ||
        zone == 'NO WATER') {
      return AppColors.critical;
    }
    if (zone == 'WARNING' || zone == 'HIGH TURBIDITY') {
      return AppColors.warning;
    }
    if (zone == 'OPTIMAL' || zone == 'CLEAR WATER') {
      return AppColors.successLight;
    }
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
    final wl = SensorService.instance.getLatestValue('waterlevel');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _buildGaugeCard(
        title: 'Water Level',
        value: wl.toStringAsFixed(0),
        unit: 'cm',
        ideal: 'Ideal: 130 \u2013 180 cm',
        iconPath: 'assets/images/waterLevel.png',
        status: _getStatus('waterlevel', wl),
        statusColor: _getStatusColor('waterlevel', wl),
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
    final actions = [
      _QuickActionData('Aerator', Icons.air, 'Active'),
      _QuickActionData('Pump', Icons.water_drop, 'Idle'),
      _QuickActionData('Feed', Icons.egg_rounded, 'Auto'),
      _QuickActionData('Stock', Icons.inventory_2_outlined, null),
      _QuickActionData('Test', Icons.speed_rounded, null),
      _QuickActionData('Trends', Icons.trending_up_rounded, null),
    ];

    return SingleChildScrollView(
      controller: _quickActionsController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: actions.map((a) {
          return Container(
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
                  child: _buildStatColumn(Icons.numbers, '63', 'LIVE COUNT'),
                ),
                Expanded(
                  child: _buildStatColumn(
                    Icons.shield_outlined,
                    '92.6%',
                    'SURVIVAL',
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    Icons.pie_chart_outline,
                    '68',
                    'INITIAL',
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    Icons.favorite_border,
                    '5',
                    'MORTALITY',
                  ),
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

  Widget _buildStatColumn(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppColors.darkWith(0.5)),
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

  Widget _buildStatDivider() {
    return Container(width: 1, height: 40, color: AppColors.darkWith(0.1));
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
              Icon(Icons.egg_rounded, size: 18, color: AppColors.primary),
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
                    const Text(
                      '8:00 AM',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.dark,
                      ),
                    ),
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
                    const Text(
                      '4:00 PM',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'In 2 hours',
                      style: TextStyle(
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
                  widthFactor: 0.5,
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
          const Text(
            '1 of 2 feedings today completed',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.dark,
            ),
          ),
        ],
      ),
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
    final legends = _gaugeLegends[title] ?? [];

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
            final value = SensorService.instance.getLatestValue(sensorKey);
            final status = _getStatus(sensorKey, value);
            final statusColor = _getStatusColor(sensorKey, value);
            final formattedValue =
                sensorKey == 'turb' || sensorKey == 'waterlevel'
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
                                'View Graph',
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

  void _showAlertsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 24),
                const Text(
                  'Tank Alerts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 16),
                ListView(
                  shrinkWrap: true,
                  children: [
                    _buildAlertItem(
                      Icons.error_rounded,
                      'Low DO Level',
                      'Critical',
                      AppColors.critical,
                    ),
                    _buildAlertItem(
                      Icons.warning_rounded,
                      'High Temperature',
                      'Warning',
                      AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 13,
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
  }

  Widget _buildAlertItem(
    IconData icon,
    String title,
    String status,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppColors.dark,
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
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

const Map<String, List<_LegendItem>> _gaugeLegends = {
  'Temperature': [
    _LegendItem(
      'Normal',
      '25\u201330\u00B0C',
      'Optimal range for crayfish growth.',
      AppColors.success,
    ),
    _LegendItem(
      'Warning',
      '22\u201324\u00B0C or 31\u201333\u00B0C',
      'Metabolic stress risk.',
      AppColors.warning,
    ),
    _LegendItem(
      'Critical',
      'below 22\u00B0C or above 33\u00B0C',
      'Immediate death risk.',
      AppColors.critical,
    ),
  ],
  'pH Level': [
    _LegendItem(
      'Normal',
      '7.0\u20138.5',
      'Ideal for shell formation.',
      AppColors.success,
    ),
    _LegendItem(
      'Warning',
      '6.5\u20136.9 or 8.6\u20139.0',
      'Irritates gills.',
      AppColors.warning,
    ),
    _LegendItem(
      'Critical',
      'below 6.5 or above 9.0',
      'Highly toxic.',
      AppColors.critical,
    ),
  ],
  'Dissolved O\u2082': [
    _LegendItem(
      'Normal',
      '5.0+ mg/L',
      'Healthy oxygen levels.',
      AppColors.success,
    ),
    _LegendItem(
      'Low',
      '3.0\u20134.9 mg/L',
      'Loss of appetite.',
      AppColors.warning,
    ),
    _LegendItem(
      'Critical',
      'below 3.0 mg/L',
      'Dangerously low.',
      AppColors.critical,
    ),
  ],
  'Turbidity': [
    _LegendItem('Normal', '0\u201325 NTU', 'Clean water.', AppColors.success),
    _LegendItem(
      'Cloudy',
      '26\u201350 NTU',
      'Risk of bacteria.',
      AppColors.warning,
    ),
    _LegendItem(
      'Dirty',
      'above 50 NTU',
      'Severe contamination.',
      AppColors.critical,
    ),
  ],
  'Water Level': [
    _LegendItem(
      'Normal',
      '130\u2013180 cm',
      'Ideal pond depth.',
      AppColors.success,
    ),
    _LegendItem(
      'Warning',
      '100\u2013129 cm or 181\u2013200 cm',
      'Poor circulation.',
      AppColors.warning,
    ),
    _LegendItem(
      'Critical',
      'below 100 cm or above 200 cm',
      'Life-threatening.',
      AppColors.critical,
    ),
  ],
};

class _QuickActionData {
  final String name;
  final IconData icon;
  final String? status;
  const _QuickActionData(this.name, this.icon, this.status);
}
