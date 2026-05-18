import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../services/tank_service.dart';

class TanksScreen extends StatefulWidget {
  const TanksScreen({super.key});

  @override
  State<TanksScreen> createState() => _TanksScreenState();
}

class _TanksScreenState extends State<TanksScreen> {
  int _activeTab = 0;
  final bool _hasSetup = true;
  DateTime _lastEdited = DateTime.now();
  final _sampleCountController = TextEditingController();
  final _sampleWeightController = TextEditingController();
  final _sampleLengthController = TextEditingController();

  @override
  void initState() {
    super.initState();
    TankService.instance.addListener(_refreshUI);
  }

  @override
  void dispose() {
    _sampleCountController.dispose();
    _sampleWeightController.dispose();
    _sampleLengthController.dispose();
    TankService.instance.removeListener(_refreshUI);
    super.dispose();
  }

  void _refreshUI() {
    if (mounted) setState(() => _lastEdited = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: IndexedStack(
              index: _activeTab,
              children: [
                _buildInventoryTab(),
                _buildSamplingTab(),
                _buildTrendsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
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
            width: 170,
            height: 100,
            child: Image.asset(
              'assets/images/crayfish_seaweed_tank.png',
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
                      'Tank — Grow-out',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Crayfish Growth Tracker',
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

  Widget _buildTabBar() {
    final tabs = [
      (
        _activeTab == 0 ? Icons.inventory_2 : Icons.inventory_2_outlined,
        'Inventory',
      ),
      (_activeTab == 1 ? Icons.speed : Icons.speed_outlined, 'Sampling'),
      (
        _activeTab == 2 ? Icons.trending_up : Icons.trending_up_outlined,
        'Trends',
      ),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = _activeTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.primaryWith(0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tabs[i].$1,
                      size: 12,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.darkWith(0.45),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      tabs[i].$2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? AppColors.primary
                            : AppColors.darkWith(0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildInventoryTab() {
    if (!_hasSetup) return _buildEmptyState();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildSurvivalCard(),
          const SizedBox(height: 10),
          _buildWarningBanner(),
          const SizedBox(height: 10),
          _buildActionButtons(),
          const SizedBox(height: 10),
          _buildInfoCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: AppColors.darkWith(0.15),
            ),
            const SizedBox(height: 16),
            Text(
              'No Grow-Out Setup Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.darkWith(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Initialize your grow-out to start tracking crayfish growth and survival.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.4)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _showInitModal(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Initialize Grow-Out Setup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurvivalCard() {
    final service = TankService.instance;
    final survivalPct = service.survivalRate;

    Color statusColor = AppColors.success;
    if (survivalPct < 70) {
      statusColor = AppColors.critical;
    } else if (survivalPct < 85) {
      statusColor = AppColors.warning;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'SURVIVAL RATE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Stocking Health',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Overall survival performance based on initial stocking data.',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkWith(0.5),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildDonutChart(survivalPct / 100, statusColor),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _buildStatItem(Icons.numbers, '${service.liveCount}', 'LIVE'),
              _buildStatDivider(),
              _buildStatItem(
                Icons.pie_chart_outline,
                '${service.initialCount}',
                'INITIAL',
              ),
              _buildStatDivider(),
              _buildStatItem(
                Icons.favorite_border,
                '${service.mortality}',
                'MORTALITY',
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatItem(
                Icons.monitor_weight_outlined,
                '${service.initialWeight.toStringAsFixed(1)} g',
                'AVG WEIGHT',
              ),
              _buildStatDivider(),
              _buildStatItem(
                Icons.straighten_outlined,
                '${service.initialLength.toStringAsFixed(1)} cm',
                'AVG LENGTH',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDonutChart(double fraction, Color color) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CustomPaint(
        painter: _DonutPainter(
          fraction: fraction,
          color: color,
          bgColor: color.withValues(alpha: 0.12),
        ),
        child: Center(
          child: Text(
            '${(fraction * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 14, color: AppColors.darkWith(0.5)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: AppColors.darkWith(0.5),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 36, color: AppColors.darkWith(0.08));
  }

  Widget _buildWarningBanner() {
    final survivalPct = TankService.instance.survivalRate;
    if (survivalPct >= 85) return const SizedBox.shrink();
    final isCritical = survivalPct < 70;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCritical
            ? AppColors.criticalWith(0.1)
            : AppColors.warningWith(0.1),
        border: Border.all(
          color: isCritical
              ? AppColors.criticalWith(0.25)
              : AppColors.warningWith(0.25),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isCritical ? Icons.warning : Icons.info_outline,
            size: 16,
            color: isCritical ? AppColors.critical : AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isCritical
                  ? 'Critical: Survival dropped below 70%. Immediate action required.'
                  : 'Warning: Survival below 85%. Consider reviewing water quality and feeding.',
              style: TextStyle(
                fontSize: 11,
                color: isCritical ? AppColors.critical : AppColors.warningDark,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildActionBtn(
            'Log Mortality',
            Icons.warning_rounded,
            AppColors.critical,
            () => _showMortalityModal(),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildActionBtn(
            'Edit Setup',
            Icons.edit_outlined,
            AppColors.primary,
            () => _showEditModal(),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildActionBtn(
            'View Logs',
            Icons.menu_book,
            AppColors.warning,
            () => _showLogsModal(),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final service = TankService.instance;
    final stockingDate = service.stockingDate;
    final days = service.daysInCulture;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkWith(0.08)),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            Icons.calendar_today,
            'Stocking Date',
            '${stockingDate.month}/${stockingDate.day}/${stockingDate.year}',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.hourglass_bottom,
            'Days in Culture',
            '$days days',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.history,
            'Last Edited',
            '${_lastEdited.month}/${_lastEdited.day}/${_lastEdited.year}',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
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
              style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.7)),
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

  Widget _buildSamplingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNextSamplingPanel(),
          const SizedBox(height: 16),
          _buildStepper(),
          const SizedBox(height: 16),
          _buildGrowthOverviewPanel(),
          const SizedBox(height: 16),
          _buildSamplingFormPanel(),
          const SizedBox(height: 16),
          _buildGrowthStagePanel(),
          const SizedBox(height: 16),
          _buildSamplingHistoryPanel(),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    final int currentDay = (TankService.instance.daysInCulture % 7) + 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(7, (index) {
              final day = index + 1;
              final isActive = day == currentDay;
              final isPast = day < currentDay;
              final isConnected = index < 6;

              return Expanded(
                child: Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.primary
                                : (isPast
                                      ? AppColors.primary
                                      : AppColors.lightBg),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 11,
                                color: isActive || isPast
                                    ? Colors.white
                                    : AppColors.darkWith(0.5),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isConnected)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: isPast || day < currentDay
                              ? AppColors.primary
                              : AppColors.lightBg,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            currentDay == 7
                ? 'Sampling Day!'
                : 'Day $currentDay of 7-day Cycle',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: currentDay == 7 ? AppColors.primary : AppColors.dark,
            ),
          ),
        ],
      ),
    );
  }

  void _showGrowthStageReferenceModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Growth Classification Reference',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                const Text(
                  'Based on Average Body Length (ABL) and Average Body Weight (ABW)',
                  style: TextStyle(fontSize: 12, color: AppColors.subtitleText),
                ),
                const SizedBox(height: 16),
                Table(
                  border: TableBorder.all(color: AppColors.faintBorder),
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.5),
                    2: FlexColumnWidth(1.5),
                  },
                  children: const [
                    TableRow(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Stage',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Length',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Weight',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Juvenile'),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('2 – 4 cm'),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('1 – 5 g'),
                        ),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Early Grow-out'),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('4 – 6 cm'),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('5 – 15 g'),
                        ),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Mid Grow-out'),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('6 – 8 cm'),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('15 – 30 g'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrowthStagePanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Growth Stage',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              Row(
                children: [
                  Text(
                    'Mid Grow-out',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showGrowthStageReferenceModal,
                    child: const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.lightBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              widthFactor: 0.6,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Juvenile', style: TextStyle(fontSize: 10)),
              Text('Market', style: TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNextSamplingPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryWith(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_today,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Next Sampling',
                style: TextStyle(fontSize: 12, color: AppColors.subtitleText),
              ),
              Text(
                '3 days remaining',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthOverviewPanel() {
    final history = TankService.instance.samplingHistory;
    final latest = history.isNotEmpty ? history.last : null;
    final initialW = TankService.instance.initialWeight;
    final initialL = TankService.instance.initialLength;

    final latestW = latest?.abw ?? initialW;
    final latestL = latest?.avgLength ?? initialL;

    final diffW = latestW - initialW;
    final diffL = latestL - initialL;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Growth Overview',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'View Details',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGrowthColumn(
                'Initial',
                TankService.instance.stockingDate,
                initialW,
                initialL,
              ),
              _buildGrowthColumn(
                'Latest',
                latest?.date ?? TankService.instance.stockingDate,
                latestW,
                latestL,
              ),
              _buildGrowthDiffColumn('Growth', diffW, diffL),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthColumn(
    String title,
    DateTime date,
    double weight,
    double length,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          Text(
            '${date.month}/${date.day}',
            style: const TextStyle(fontSize: 9, color: AppColors.subtitleText),
          ),
          const SizedBox(height: 8),
          Text(
            '${weight.toStringAsFixed(1)}g',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          Text(
            '${length.toStringAsFixed(1)}cm',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthDiffColumn(String title, double diffW, double diffL) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '${diffW >= 0 ? '+' : ''}${diffW.toStringAsFixed(1)}g',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: diffW >= 0 ? AppColors.success : AppColors.critical,
            ),
          ),
          Text(
            '${diffL >= 0 ? '+' : ''}${diffL.toStringAsFixed(1)}cm',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: diffL >= 0 ? AppColors.success : AppColors.critical,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSamplingFormPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly Sampling',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          _buildSamplingInput(
            'Sample Count',
            'e.g. 10',
            _sampleCountController,
          ),
          _buildSamplingInput(
            'Total Weight (g)',
            'e.g. 150',
            _sampleWeightController,
          ),
          _buildSamplingInput(
            'Total Length (cm)',
            'e.g. 60',
            _sampleLengthController,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final count = int.tryParse(_sampleCountController.text);
                final weight = double.tryParse(_sampleWeightController.text);
                final length = double.tryParse(_sampleLengthController.text);

                if (count != null &&
                    weight != null &&
                    length != null &&
                    count > 0 &&
                    weight > 0 &&
                    length > 0) {
                  TankService.instance.addSamplingEntry(count, weight, length);
                  _sampleCountController.clear();
                  _sampleWeightController.clear();
                  _sampleLengthController.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sampling results recorded!')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Compute Results',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSamplingInput(
    String label,
    String hint,
    TextEditingController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
          ],
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.lightBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildTrendsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Growth Trends',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Visualize growth and biomass trends over time.',
            style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.5)),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primaryWith(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryWith(0.15)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.trending_up,
                    size: 40,
                    color: AppColors.primaryWith(0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Trends module coming soon',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSamplingHistoryPanel() {
    return ListenableBuilder(
      listenable: TankService.instance,
      builder: (context, child) {
        final history = TankService.instance.samplingHistory;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.faintBorder),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Sampling History',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  if (history.isNotEmpty)
                    TextButton(
                      onPressed: () {},
                      child: const Text(
                        'View All',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No sampling history yet.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.subtitleText,
                    ),
                  ),
                )
              else
                Column(
                  children: history.take(3).map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildHistoryItem(
                        'Sampling',
                        '${entry.date.month}/${entry.date.day}/${entry.date.year}',
                        '${entry.abw.toStringAsFixed(1)}g',
                        '${entry.avgLength.toStringAsFixed(1)}cm',
                        entry.sampleSize,
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(
    String title,
    String date,
    String weight,
    String length,
    int samples,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.subtitleText,
                ),
              ),
            ],
          ),
          Text(
            '$weight | $length | $samples samples',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // MODALS / BOTTOM SHEETS IMPLEMENTATION
  // =========================================================

  void _showInitModal() {
    _showSetupForm(isEdit: false);
  }

  void _showEditModal() {
    _showSetupForm(isEdit: true);
  }

  void _showSetupForm({required bool isEdit}) {
    final countCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.initialCount}' : '',
    );
    final weightCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.initialWeight}' : '',
    );
    final lengthCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.initialLength}' : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isEdit ? 'Edit Grow-Out Setup' : 'Initialize Grow-Out',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter the initial stocking details for this tank.',
                style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.5)),
              ),
              const SizedBox(height: 20),
              _buildModalInput('Initial Stock Count', 'e.g. 1000', countCtrl),
              _buildModalInput('Average Weight (g)', 'e.g. 2.5', weightCtrl),
              _buildModalInput('Average Length (cm)', 'e.g. 3.0', lengthCtrl),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TankService.instance.updateSetup(
                    //   int.parse(countCtrl.text),
                    //   double.parse(weightCtrl.text),
                    //   double.parse(lengthCtrl.text)
                    // );

                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEdit ? 'Setup updated!' : 'Setup initialized!',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save Setup',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showMortalityModal() {
    final countCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Log Mortality',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.critical,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Record the number of dead crayfish found in the tank.',
                style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.5)),
              ),
              const SizedBox(height: 20),
              _buildModalInput('Number of Dead Crayfish', 'e.g. 5', countCtrl),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (countCtrl.text.isNotEmpty) {
                      // TankService.instance.addMortality(int.parse(countCtrl.text));

                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mortality successfully logged.'),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.critical,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Confirm Logging',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showLogsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Activity Logs',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _buildLogItem(
                      Icons.water_drop,
                      'Water changed',
                      'Today, 8:00 AM',
                      AppColors.primary,
                    ),
                    _buildLogItem(
                      Icons.restaurant,
                      'Fed 500g pellets',
                      'Yesterday, 6:00 PM',
                      AppColors.success,
                    ),
                    _buildLogItem(
                      Icons.warning,
                      'Mortality: 2 recorded',
                      'Yesterday, 8:00 AM',
                      AppColors.critical,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalInput(
    String label,
    String hint,
    TextEditingController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: AppColors.darkWith(0.03),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.darkWith(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.darkWith(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkWith(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.darkWith(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color bgColor;

  _DonutPainter({
    required this.fraction,
    required this.color,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const strokeWidth = 8.0;

    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * fraction,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.fraction != fraction;
}
