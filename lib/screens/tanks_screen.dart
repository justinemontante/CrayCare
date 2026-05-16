import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class TanksScreen extends StatefulWidget {
  const TanksScreen({super.key});

  @override
  State<TanksScreen> createState() => _TanksScreenState();
}

class _TanksScreenState extends State<TanksScreen> {
  int _activeTab = 0;

  bool _hasSetup = false;
  int _initialCount = 68;
  int _mortality = 5;
  int _liveCount = 63;
  double _avgWeight = 45.2;
  double _avgLength = 12.8;
  DateTime _stockingDate = DateTime.now().subtract(const Duration(days: 45));
  DateTime _lastEdited = DateTime.now();

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
                      'Tank \u2014 Grow-out',
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
      (_activeTab == 0 ? Icons.inventory_2 : Icons.inventory_2_outlined, 'Inventory'),
      (_activeTab == 1 ? Icons.speed : Icons.speed_outlined, 'Sampling'),
      (_activeTab == 2 ? Icons.trending_up : Icons.trending_up_outlined, 'Trends'),
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
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: isActive
                      ? [BoxShadow(color: AppColors.primaryWith(0.12), blurRadius: 8, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tabs[i].$1, size: 12, color: isActive ? AppColors.primary : AppColors.darkWith(0.45)),
                    const SizedBox(width: 5),
                    Text(
                      tabs[i].$2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isActive ? AppColors.primary : AppColors.darkWith(0.45),
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
            Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.darkWith(0.15)),
            const SizedBox(height: 16),
            Text('No Grow-Out Setup Yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.darkWith(0.7))),
            const SizedBox(height: 8),
            Text('Initialize your grow-out to start tracking crayfish growth and survival.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.4))),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _showInitModal(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Initialize Grow-Out Setup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurvivalCard() {
    final survivalPct = _initialCount > 0 ? (_liveCount / _initialCount * 100) : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: [BoxShadow(color: AppColors.darkWith(0.06), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Survival Rate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5))),
                    const SizedBox(height: 4),
                    Text('${survivalPct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.success)),
                  ],
                ),
              ),
              _buildDonutChart(survivalPct / 100),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            _buildStatItem(Icons.numbers, '$_liveCount', 'LIVE'),
            _buildStatDivider(),
            _buildStatItem(Icons.pie_chart_outline, '$_initialCount', 'INITIAL'),
            _buildStatDivider(),
            _buildStatItem(Icons.favorite_border, '$_mortality', 'MORTALITY'),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(children: [
            _buildStatItem(Icons.monitor_weight_outlined, '${_avgWeight.toStringAsFixed(1)} g', 'AVG WEIGHT'),
            _buildStatDivider(),
            _buildStatItem(Icons.straighten_outlined, '${_avgLength.toStringAsFixed(1)} cm', 'AVG LENGTH'),
          ]),
        ],
      ),
    );
  }

  Widget _buildDonutChart(double fraction) {
    return SizedBox(
      width: 72, height: 72,
      child: CustomPaint(
        painter: _DonutPainter(fraction: fraction, color: AppColors.success, bgColor: AppColors.successWith(0.15)),
        child: Center(
          child: Text('${(fraction * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.success)),
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
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark)),
          Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5), letterSpacing: 0.3)),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 36, color: AppColors.darkWith(0.08));
  }

  Widget _buildWarningBanner() {
    final survivalPct = _initialCount > 0 ? (_liveCount / _initialCount * 100) : 0.0;
    if (survivalPct >= 85) return const SizedBox.shrink();
    final isCritical = survivalPct < 70;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCritical ? AppColors.criticalWith(0.1) : AppColors.warningWith(0.1),
        border: Border.all(color: isCritical ? AppColors.criticalWith(0.25) : AppColors.warningWith(0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(isCritical ? Icons.warning : Icons.info_outline, size: 16, color: isCritical ? AppColors.critical : AppColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(
            isCritical
              ? 'Critical: Survival dropped below 70%. Immediate action required.'
              : 'Warning: Survival below 85%. Consider reviewing water quality and feeding.',
            style: TextStyle(fontSize: 11, color: isCritical ? AppColors.critical : AppColors.warningDark, height: 1.3),
          )),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(child: _buildActionBtn('Log Mortality', Icons.warning_rounded, AppColors.critical, () => _showMortalityModal())),
        const SizedBox(width: 6),
        Expanded(child: _buildActionBtn('Edit Setup', Icons.edit_outlined, AppColors.primary, () => _showEditModal())),
        const SizedBox(width: 6),
        Expanded(child: _buildActionBtn('View Logs', Icons.menu_book, AppColors.warning, () {})),
      ],
    );
  }

  Widget _buildActionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
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
              Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final days = DateTime.now().difference(_stockingDate).inDays;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkWith(0.08)),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.calendar_today, 'Stocking Date', '${_stockingDate.month}/${_stockingDate.day}/${_stockingDate.year}'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.hourglass_bottom, 'Days in Culture', '$days days'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.history, 'Last Edited', '${_lastEdited.month}/${_lastEdited.day}/${_lastEdited.year}'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.darkWith(0.5)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.7))),
        ]),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.dark)),
      ],
    );
  }

  Widget _buildSamplingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sampling', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 10),
          Text('Record weekly sampling data to track growth performance.',
            style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.5))),
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
                  Icon(Icons.biotech_outlined, size: 40, color: AppColors.primaryWith(0.4)),
                  const SizedBox(height: 12),
                  Text('Sampling module coming soon', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.6))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Growth Trends', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 10),
          Text('Visualize growth and biomass trends over time.',
            style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.5))),
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
                  Icon(Icons.trending_up, size: 40, color: AppColors.primaryWith(0.4)),
                  const SizedBox(height: 12),
                  Text('Trends module coming soon', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.6))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInitModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    const Text('Initialize Grow-Out Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dark)),
                    const SizedBox(height: 20),
                    _buildFieldLabel('Initial Population'),
                    const SizedBox(height: 6),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'e.g. 68',
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.darkWith(0.12)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14, color: AppColors.dark),
                    ),
                    const SizedBox(height: 14),
                    _buildFieldLabel('Sample Count'),
                    const SizedBox(height: 6),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'e.g. 30',
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.darkWith(0.12)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14, color: AppColors.dark),
                    ),
                    const SizedBox(height: 14),
                    _buildFieldLabel('Total Sample Weight (g)'),
                    const SizedBox(height: 6),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'e.g. 45',
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.darkWith(0.12)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14, color: AppColors.dark),
                    ),
                    const SizedBox(height: 14),
                    _buildFieldLabel('Total Sample Length (cm)'),
                    const SizedBox(height: 6),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'e.g. 12',
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.darkWith(0.12)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14, color: AppColors.dark),
                    ),
                    const SizedBox(height: 14),
                    _buildFieldLabel('Stocking Date'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: TextEditingController(text: '${_stockingDate.month}/${_stockingDate.day}/${_stockingDate.year}'),
                      decoration: InputDecoration(
                        hintText: 'MM/DD/YYYY',
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.darkWith(0.12)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      readOnly: true,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _stockingDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(primary: AppColors.primary),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() => _stockingDate = picked);
                        }
                      },
                      style: const TextStyle(fontSize: 14, color: AppColors.dark),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _hasSetup = true);
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Initialize', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.dark),
    );
  }

  void _showMortalityModal() {
    int count = 1;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 12),
                  const Text('Log Mortality', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        color: AppColors.critical,
                        onPressed: count > 1 ? () => setDialogState(() => count--) : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.darkWith(0.15)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$count', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.dark)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        color: AppColors.critical,
                        onPressed: () => setDialogState(() => count++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _mortality += count;
                          _liveCount = _initialCount - _mortality;
                          _hasSetup = true;
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.critical,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Record Mortality', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _showEditModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 12),
                const Text('Edit Initial Stock', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark)),
                const SizedBox(height: 16),
                TextField(
                  decoration: InputDecoration(labelText: 'Initial Population'),
                  controller: TextEditingController(text: '$_initialCount'),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14, color: AppColors.dark),
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(labelText: 'Reason for edit'),
                  style: const TextStyle(fontSize: 14, color: AppColors.dark),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save Changes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color bgColor;

  _DonutPainter({required this.fraction, required this.color, required this.bgColor});

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
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2, 2 * pi * fraction, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.fraction != fraction;
}
