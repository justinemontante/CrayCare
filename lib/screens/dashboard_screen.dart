import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/section_label.dart';
import '../services/sensor_service.dart';
import '../services/settings_service.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onViewGraph;

  const DashboardScreen({super.key, this.onViewGraph});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    SensorService.instance.addListener(_refreshUI);
    SettingsService.instance.addListener(_refreshUI);
  }

  @override
  void dispose() {
    SensorService.instance.removeListener(_refreshUI);
    SettingsService.instance.removeListener(_refreshUI);
    super.dispose();
  }

  void _refreshUI() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildGreeting(),
            const SectionLabel(
              label: 'Water Quality Overview',
              showLiveData: true,
            ),
            _buildGaugeGrid(context),
            const SectionLabel(
              label: 'Physical Parameters',
              showLiveData: true,
            ),
            _buildWaterLevelGauge(context),
            _buildQuickActionsHeader(),
            _buildQuickActions(),
            _buildTankStatusCard(),
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
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: AppColors.headerGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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
                      const Text(
                        'Good Afternoon, Justine!',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Monday, May 12, 2026',
                        style: TextStyle(
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
            bottom: 0,
            right: 0,
            width: 200,
            height: 150,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.bottomRight,
                    radius: 1.5,
                    colors: [
                      AppColors.primaryWith(0.15),
                      AppColors.primaryWith(0.0),
                    ],
                  ),
                ),
              ),
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

  Widget _buildGaugeGrid(BuildContext context) {
    final temp = SensorService.instance.getLatestValue('temp');
    final ph = SensorService.instance.getLatestValue('ph');
    final dO2 = SensorService.instance.getLatestValue('do');
    final turb = SensorService.instance.getLatestValue('turb');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
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
                    title: 'Temperature',
                    value: temp.toStringAsFixed(1),
                    unit: '\u00B0C',
                    status: _getStatus('temp', temp),
                    statusColor: _getStatusColor('temp', temp),
                    ideal: '25 \u2013 30\u00B0C',
                    iconPath: 'assets/images/temperature.png',
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                    title: 'pH Level',
                    value: ph.toStringAsFixed(1),
                    unit: 'pH',
                    status: _getStatus('ph', ph),
                    statusColor: _getStatusColor('ph', ph),
                    ideal: '7.0 \u2013 8.5',
                    iconPath: 'assets/images/pH.png',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                    title: 'Dissolved O\u2082',
                    value: dO2.toStringAsFixed(1),
                    unit: 'mg/L',
                    status: _getStatus('do', dO2),
                    statusColor: _getStatusColor('do', dO2),
                    ideal: '>5.0 mg/L',
                    iconPath: 'assets/images/DO.png',
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                    title: 'Turbidity',
                    value: turb.toStringAsFixed(0),
                    unit: 'NTU',
                    status: _getStatus('turb', turb),
                    statusColor: _getStatusColor('turb', turb),
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
    final range = SettingsService.instance.currentRanges[key];
    if (range == null) return 'Normal';
    if (val < range['min']! || val > range['max']!) return 'Critical';
    final padding = (range['max']! - range['min']!) * 0.1;
    if (val < range['min']! + padding || val > range['max']! - padding)
      return 'Warning';
    return 'Optimal';
  }

  Color _getStatusColor(String key, double val) {
    final status = _getStatus(key, val);
    if (status == 'Critical') return AppColors.critical;
    if (status == 'Warning') return AppColors.warning;
    return AppColors.successLight;
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
          title: 'Water Level',
          value: wl.toStringAsFixed(0),
          unit: 'cm',
          status: _getStatus('waterlevel', wl),
          statusColor: _getStatusColor('waterlevel', wl),
          ideal: '130 \u2013 180 cm',
          iconPath: 'assets/images/waterLevel.png',
        ),
      ),
    );
  }

  Widget _buildQuickActionsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Row(
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _QuickActionData('Aerator', Icons.air, ''),
      _QuickActionData('Pump', Icons.water_drop, ''),
      _QuickActionData('Feed Now', Icons.egg_rounded, ''),
      _QuickActionData('Inventory', Icons.inventory_2_outlined, null),
      _QuickActionData('Sampling', Icons.speed_rounded, null),
      _QuickActionData('Trends', Icons.trending_up_rounded, null),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(
        children: actions.map((a) {
          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.fromLTRB(6, 10, 10, 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFf8ffff),
                  Color(0xFFf2fdfd),
                  Color(0xFFe8fafa),
                  Color(0xFFdaf4f5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: AppColors.darkWith(0.06)),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkWith(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryWith(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(a.icon, size: 12, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    if (a.status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          a.status!.isEmpty ? '--' : a.status!,
                          style: const TextStyle(
                            fontSize: 6,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
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
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: AppColors.darkWith(0.7),
              ),
              const SizedBox(width: 6),
              const Text(
                'Tank Status',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildStatColumn(Icons.numbers, '63', 'LIVE COUNT'),
              ),
              _buildStatDivider(),
              Expanded(
                child: _buildStatColumn(
                  Icons.shield_outlined,
                  '92.6%',
                  'SURVIVAL',
                ),
              ),
              _buildStatDivider(),
              Expanded(
                child: _buildStatColumn(
                  Icons.pie_chart_outline,
                  '68',
                  'INITIAL',
                ),
              ),
              _buildStatDivider(),
              Expanded(
                child: _buildStatColumn(
                  Icons.favorite_border,
                  '5',
                  'MORTALITY',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0x150B3C49)),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.hourglass_bottom, 'Days in Culture', '45'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0x150B3C49)),
          ),
          _buildDetailRow(Icons.history, 'Last Sampling', 'May 12, 2026'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0x150B3C49)),
          ),
          _buildDetailRow(
            Icons.calendar_today,
            'Next Sampling',
            'May 19, 2026',
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
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.egg_rounded, size: 18, color: AppColors.darkWith(0.7)),
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
    required String title,
    required String value,
    required String unit,
    required String status,
    required Color statusColor,
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
                        widget.onViewGraph?.call();
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
                        value,
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
                          _formatTimestamp(DateTime.now()),
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
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return 'Captured: $h:${dt.minute.toString().padLeft(2, '0')} $ampm';
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: Ink(
          decoration: BoxDecoration(
            color: _isPressed ? AppColors.darkWith(0.03) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isPressed
                  ? AppColors.darkWith(0.25)
                  : AppColors.darkWith(0.15),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _isPressed
                    ? AppColors.darkWith(0.12)
                    : AppColors.darkWith(0.08),
                blurRadius: _isPressed ? 8 : 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: widget.statusColor.withValues(alpha: 0.18),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 28,
                      height: 28,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Image.asset(widget.iconPath),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.value,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      widget.unit,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.dark,
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
                  color: widget.statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: widget.statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      widget.status,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: widget.statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Text(
                  widget.ideal,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark,
                  ),
                ),
              ),
            ],
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
      'Optimal range for crayfish growth and molting.',
      AppColors.success,
    ),
    _LegendItem(
      'Warning',
      '22\u201324\u00B0C or 31\u201333\u00B0C',
      'May slow metabolism and cause stress to crayfish.',
      AppColors.warning,
    ),
    _LegendItem(
      'Critical',
      'below 22\u00B0C or above 33\u00B0C',
      'Can cause death. Alert notification will be sent.',
      AppColors.critical,
    ),
  ],
  'pH Level': [
    _LegendItem(
      'Normal',
      '7.0\u20138.5',
      'Ideal acidity for healthy molting and shell formation.',
      AppColors.success,
    ),
    _LegendItem(
      'Warning',
      '6.5\u20136.9 or 8.6\u20139.0',
      'May irritate gills and weaken immune system.',
      AppColors.warning,
    ),
    _LegendItem(
      'Critical',
      'below 6.5 or above 9.0',
      'Highly toxic. Can cause rapid death of crayfish.',
      AppColors.critical,
    ),
  ],
  'Dissolved O\u2082': [
    _LegendItem(
      'Normal',
      '5.0+ mg/L',
      'Sufficient oxygen for active and healthy crayfish.',
      AppColors.success,
    ),
    _LegendItem(
      'Low',
      '3.0\u20134.9 mg/L',
      'Crayfish may become inactive and lose appetite.',
      AppColors.warning,
    ),
    _LegendItem(
      'Critical',
      'below 3.0 mg/L',
      'Dangerously low. Triggers aerator pump automatically.',
      AppColors.critical,
    ),
  ],
  'Turbidity': [
    _LegendItem(
      'Normal',
      '0\u201325 NTU',
      'Clean water with good visibility and low bacteria risk.',
      AppColors.success,
    ),
    _LegendItem(
      'Cloudy',
      '26\u201350 NTU',
      'Suspended particles may clog gills over time.',
      AppColors.warning,
    ),
    _LegendItem(
      'Dirty',
      'above 50 NTU',
      'Severely dirty water. Triggers filtration alert immediately.',
      AppColors.critical,
    ),
  ],
  'Water Level': [
    _LegendItem(
      'Normal',
      '130\u2013180 cm',
      'Ideal pond depth for Australian Redclaw in tropical climate.',
      AppColors.success,
    ),
    _LegendItem(
      'Warning',
      '100\u2013129 cm or 181\u2013200 cm',
      'May affect water quality and circulation.',
      AppColors.warning,
    ),
    _LegendItem(
      'Critical',
      'below 100 cm or above 200 cm',
      'Extreme water level. Can stress or kill crayfish.',
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
