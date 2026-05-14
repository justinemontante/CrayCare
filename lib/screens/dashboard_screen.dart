import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  final VoidCallback? onViewGraph;

  const DashboardScreen({super.key, this.onViewGraph});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildGreeting(),
            _buildSectionHeader('Water Quality Overview'),
            _buildGaugeGrid(context),
            _buildSectionHeader('Physical Parameters'),
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
        boxShadow: [BoxShadow(color: const Color(0xFF0B3C49).withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 23, 20, 23),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFf8ffff), Color(0xFFf2fdfd), Color(0xFFe8fafa), Color(0xFFdaf4f5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 50,
                  decoration: BoxDecoration(color: const Color(0xFF1FA5A5), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Good Afternoon, Justine!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1e293b))),
                      const SizedBox(height: 3),
                      const Text('Monday, May 12, 2026', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: Color(0xFF94a3b8))),
                      const SizedBox(height: 2),
                      const Text("Here's what's happening in your tank today.", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF64748b))),
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
                      const Color(0xFF1FA5A5).withOpacity(0.15),
                      const Color(0xFF1FA5A5).withOpacity(0.0),
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

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1FA5A5))),
          if (label != 'Quick Actions')
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: Color(0xFF22c55e), shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                const Text('Live Data', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1FA5A5))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildGaugeGrid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildGaugeCard(
                title: 'Temperature', value: '26.4', unit: '\u00B0C', ideal: 'Ideal: 24.0 \u2013 30.0\u00B0C',
                iconPath: 'assets/images/temperature.png', status: 'Optimal', statusColor: const Color(0xFF16a34a),
                onTap: () => _showGaugeDetail(context, title: 'Temperature', value: '26.4', unit: '\u00B0C', status: 'Optimal', statusColor: const Color(0xFF16a34a), ideal: '24.0 \u2013 30.0\u00B0C', iconPath: 'assets/images/temperature.png'),
              )),
              const SizedBox(width: 10),
              Expanded(child: _buildGaugeCard(
                title: 'pH Level', value: '7.8', unit: 'pH', ideal: 'Ideal: 7.0 \u2013 8.5',
                iconPath: 'assets/images/pH.png', status: 'Optimal', statusColor: const Color(0xFF16a34a),
                onTap: () => _showGaugeDetail(context, title: 'pH Level', value: '7.8', unit: 'pH', status: 'Optimal', statusColor: const Color(0xFF16a34a), ideal: '7.0 \u2013 8.5', iconPath: 'assets/images/pH.png'),
              )),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildGaugeCard(
                title: 'Dissolved O\u2082', value: '4.2', unit: 'mg/L', ideal: 'Ideal: >5.0 mg/L',
                iconPath: 'assets/images/DO.png', status: 'Warning', statusColor: const Color(0xFFd97706),
                onTap: () => _showGaugeDetail(context, title: 'Dissolved O\u2082', value: '4.2', unit: 'mg/L', status: 'Warning', statusColor: const Color(0xFFd97706), ideal: '>5.0 mg/L', iconPath: 'assets/images/DO.png'),
              )),
              const SizedBox(width: 10),
              Expanded(child: _buildGaugeCard(
                title: 'Turbidity', value: '45', unit: 'NTU', ideal: 'Ideal: 0 \u2013 25 NTU',
                iconPath: 'assets/images/Turbidity.png', status: 'Critical', statusColor: const Color(0xFFdc2626),
                onTap: () => _showGaugeDetail(context, title: 'Turbidity', value: '45', unit: 'NTU', status: 'Critical', statusColor: const Color(0xFFdc2626), ideal: '0 \u2013 25 NTU', iconPath: 'assets/images/Turbidity.png'),
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGaugeCard({
    required String title, required String value, required String unit, required String ideal,
    required String iconPath, required String status, required Color statusColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0B3C49).withOpacity(0.15), width: 1.5),
        boxShadow: [BoxShadow(color: const Color(0xFF0B3C49).withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.18),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49), letterSpacing: 0.3)),
                Container(
                  width: 28, height: 28,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(10)),
                  child: Image.asset(iconPath),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF0B3C49), height: 1)),
                const SizedBox(width: 3),
                Text(unit, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0B3C49))),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor, letterSpacing: 0.5)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(ideal, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF0B3C49))),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildWaterLevelGauge(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _buildGaugeCard(
        title: 'Water Level', value: '95', unit: 'cm', ideal: 'Ideal: 80 \u2013 120 cm',
        iconPath: 'assets/images/waterLevel.png', status: 'Optimal', statusColor: const Color(0xFF16a34a),
        onTap: () => _showGaugeDetail(context, title: 'Water Level', value: '95', unit: 'cm', status: 'Optimal', statusColor: const Color(0xFF16a34a), ideal: '80 \u2013 120 cm', iconPath: 'assets/images/waterLevel.png'),
      ),
    );
  }

  Widget _buildQuickActionsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Row(
        children: [
          Text('Quick Actions', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1FA5A5))),
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
                colors: [Color(0xFFf8ffff), Color(0xFFf2fdfd), Color(0xFFe8fafa), Color(0xFFdaf4f5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0xFF0B3C49).withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: const Color(0xFF0B3C49).withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1FA5A5).withValues(alpha: 0.2), width: 1.5),
                  ),
                  child: Icon(a.icon, size: 12, color: const Color(0xFF1FA5A5)),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49))),
                    if (a.status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(a.status!.isEmpty ? '--' : a.status!, style: const TextStyle(fontSize: 6, fontWeight: FontWeight.w600, color: Color(0xFF1FA5A5))),
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
        border: Border.all(color: const Color(0xFF0B3C49).withOpacity(0.08)),
        boxShadow: [BoxShadow(color: const Color(0xFF0B3C49).withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 18, color: const Color(0xFF0B3C49).withOpacity(0.7)),
              const SizedBox(width: 6),
              const Text('Tank Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49))),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildStatColumn(Icons.numbers, '63', 'LIVE COUNT')),
              _buildStatDivider(),
              Expanded(child: _buildStatColumn(Icons.shield_outlined, '92.6%', 'SURVIVAL')),
              _buildStatDivider(),
              Expanded(child: _buildStatColumn(Icons.pie_chart_outline, '68', 'INITIAL')),
              _buildStatDivider(),
              Expanded(child: _buildStatColumn(Icons.favorite_border, '5', 'MORTALITY')),
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
          _buildDetailRow(Icons.calendar_today, 'Next Sampling', 'May 19, 2026'),
        ],
      ),
    );
  }

  Widget _buildStatColumn(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF0B3C49).withOpacity(0.5)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0B3C49))),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFF0B3C49).withOpacity(0.6), letterSpacing: 0.3)),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 40, color: const Color(0xFF0B3C49).withOpacity(0.1));
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF0B3C49).withOpacity(0.5)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF0B3C49).withOpacity(0.7))),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0B3C49))),
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
        border: Border.all(color: const Color(0xFF0B3C49).withOpacity(0.08)),
        boxShadow: [BoxShadow(color: const Color(0xFF0B3C49).withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.egg_rounded, size: 18, color: const Color(0xFF0B3C49).withOpacity(0.7)),
              const SizedBox(width: 6),
              const Text('Feeding Schedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Icon(Icons.schedule, size: 20, color: const Color(0xFF0B3C49).withOpacity(0.5)),
                    const SizedBox(height: 6),
                    Text('LAST FED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF0B3C49).withOpacity(0.5), letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    const Text('8:00 AM', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0B3C49))),
                    const SizedBox(height: 2),
                    const Text('Today', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF0B3C49))),
                  ],
                ),
              ),
              Container(width: 1, height: 60, color: const Color(0xFF0B3C49).withOpacity(0.1)),
              Expanded(
                child: Column(
                  children: [
                    Icon(Icons.calendar_month, size: 20, color: const Color(0xFF0B3C49).withOpacity(0.5)),
                    const SizedBox(height: 6),
                    Text('NEXT FEEDING', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF0B3C49).withOpacity(0.5), letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    const Text('4:00 PM', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0B3C49))),
                    const SizedBox(height: 2),
                    const Text('In 2 hours', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF0B3C49))),
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
                Container(height: 8, decoration: BoxDecoration(color: const Color(0xFF0B3C49).withOpacity(0.08), borderRadius: BorderRadius.circular(6))),
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Container(height: 8, decoration: BoxDecoration(color: const Color(0xFF1FA5A5), borderRadius: BorderRadius.circular(6))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('1 of 2 feedings today completed', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF0B3C49))),
        ],
      ),
    );
  }

  void _showGaugeDetail(BuildContext context, {
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
                    const Text('Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49))),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        onViewGraph?.call();
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('View Graph', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1FA5A5))),
                          const SizedBox(width: 3),
                          Icon(Icons.chevron_right, size: 11, color: const Color(0xFF1FA5A5)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: const Color(0xFF1FA5A5).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.all(7),
                      child: Image.asset(iconPath),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49))),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor, letterSpacing: 0.5)),
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
                      Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF0B3C49), height: 1)),
                      const SizedBox(width: 4),
                      Text(unit, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF0B3C49).withOpacity(0.4))),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(ideal, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF0B3C49).withOpacity(0.5))),
                ),
                const SizedBox(height: 6),
                ...legends.map((l) => Padding(
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
                          width: 8, height: 8,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(color: l.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49))),
                              Text(l.range, style: TextStyle(fontSize: 9, color: const Color(0xFF0B3C49).withOpacity(0.75))),
                              Text(l.desc, style: TextStyle(fontSize: 9, color: const Color(0xFF0B3C49).withOpacity(0.65), height: 1.3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF1FA5A5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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

class _LegendItem {
  final String label;
  final String range;
  final String desc;
  final Color color;
  const _LegendItem(this.label, this.range, this.desc, this.color);
}

const Map<String, List<_LegendItem>> _gaugeLegends = {
  'Temperature': [
    _LegendItem('Normal', '24\u201330\u00B0C', 'Optimal range for crayfish growth and molting.', Color(0xFF52c283)),
    _LegendItem('Warning', '20\u201323\u00B0C or 31\u201333\u00B0C', 'May slow metabolism and cause stress to crayfish.', Color(0xFFf59e0b)),
    _LegendItem('Critical', 'below 20\u00B0C or above 33\u00B0C', 'Can cause death. Alert notification will be sent.', Color(0xFFE63946)),
  ],
  'pH Level': [
    _LegendItem('Normal', '7.0\u20138.5', 'Ideal acidity for healthy molting and shell formation.', Color(0xFF52c283)),
    _LegendItem('Warning', '6.5\u20136.9 or 8.6\u20139.0', 'May irritate gills and weaken immune system.', Color(0xFFf59e0b)),
    _LegendItem('Critical', 'below 6.5 or above 9.0', 'Highly toxic. Can cause rapid death of crayfish.', Color(0xFFE63946)),
  ],
  'Dissolved O\u2082': [
    _LegendItem('Normal', '5.0+ mg/L', 'Sufficient oxygen for active and healthy crayfish.', Color(0xFF52c283)),
    _LegendItem('Low', '3.0\u20134.9 mg/L', 'Crayfish may become inactive and lose appetite.', Color(0xFFf59e0b)),
    _LegendItem('Critical', 'below 3.0 mg/L', 'Dangerously low. Triggers aerator pump automatically.', Color(0xFFE63946)),
  ],
  'Turbidity': [
    _LegendItem('Normal', '0\u201325 NTU', 'Clean water with good visibility and low bacteria risk.', Color(0xFF52c283)),
    _LegendItem('Cloudy', '26\u201350 NTU', 'Suspended particles may clog gills over time.', Color(0xFFf59e0b)),
    _LegendItem('Dirty', 'above 50 NTU', 'Severely dirty water. Triggers filtration alert immediately.', Color(0xFFE63946)),
  ],
  'Water Level': [
    _LegendItem('Normal', '80\u2013120 cm', 'Ideal water level for crayfish growth and oxygen exchange.', Color(0xFF52c283)),
    _LegendItem('Warning', '60\u201379 cm or 121\u2013140 cm', 'May affect water quality and circulation.', Color(0xFFf59e0b)),
    _LegendItem('Critical', 'below 60 cm or above 140 cm', 'Extreme water level. Can stress or kill crayfish.', Color(0xFFE63946)),
  ],
};

class _QuickActionData {
  final String name;
  final IconData icon;
  final String? status;
  const _QuickActionData(this.name, this.icon, this.status);
}
