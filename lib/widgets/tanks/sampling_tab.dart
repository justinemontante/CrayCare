import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../services/tank_service.dart';

class SamplingTab extends StatelessWidget {
  final TextEditingController sampleCountController;
  final TextEditingController sampleWeightController;
  final TextEditingController sampleLengthController;
  final VoidCallback onShowGrowthStageReferenceModal;

  const SamplingTab({
    super.key,
    required this.sampleCountController,
    required this.sampleWeightController,
    required this.sampleLengthController,
    required this.onShowGrowthStageReferenceModal,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Reduced top padding to 8
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NextSamplingPanel(),
          const SizedBox(height: 12),
          const GrowthOverviewPanel(),
          const SizedBox(height: 12),
          const SamplingFormPanel(),
          const SizedBox(height: 12),
          GrowthStagePanel(onInfoTap: onShowGrowthStageReferenceModal),
          const SizedBox(height: 12),
          const SamplingHistoryPanel(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// A widget that displays the "Next Sampling" information,
/// including a countdown and a 7-day progress stepper.
class NextSamplingPanel extends StatelessWidget {
  const NextSamplingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final daysInCycle = 7;
    final currentDay = (service.daysInCulture % daysInCycle) + 1;
    final daysRemaining = daysInCycle - currentDay;

    return Container(
      padding: const EdgeInsets.all(16), // Reduced internal padding
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20), // Reduced corner radius
        border: Border.all(color: AppColors.faintBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.04),
            blurRadius: 10, // Reduced blur
            offset: const Offset(0, 2), // Reduced offset
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8), // Reduced padding
                decoration: BoxDecoration(
                  color: AppColors.primaryWith(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      daysRemaining == 0 ? 'Sampling Day!' : '$daysRemaining days remaining',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: daysRemaining == 0 ? AppColors.critical : AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Due on ${_formatDate(DateTime.now().add(Duration(days: daysRemaining)))}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkWith(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // Reduced padding
                decoration: BoxDecoration(
                  color: AppColors.lightBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Week ${((currentDay - 1) / 7).floor() + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkWith(0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12), // Reduced spacing
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 12), // Reduced spacing
          _buildStepTracker(currentDay, daysInCycle),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildStepTracker(int currentDay, int totalDays) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(totalDays, (index) {
            final day = index + 1;
            final isPast = day < currentDay;
            final isCurrent = day == currentDay;

            return Expanded(
              child: Row(
                children: [
                  _buildStepDot(day, isPast, isCurrent),
                  if (index < totalDays - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isPast ? AppColors.primary : AppColors.lightBg,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          'Day $currentDay',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.darkWith(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildStepDot(int day, bool isPast, bool isCurrent) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: isPast
            ? AppColors.primary
            : (isCurrent ? AppColors.warning : AppColors.white),
        shape: BoxShape.circle,
        border: Border.all(
          color: isPast
              ? AppColors.primary
              : (isCurrent ? AppColors.warning : AppColors.faintBorder),
          width: 2,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.warningWith(0.2),
                  blurRadius: 6,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Center(
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isPast || isCurrent ? Colors.white : AppColors.darkWith(0.5),
          ),
        ),
      ),
    );
  }
}

/// A widget that displays the "Growth Overview" with three mini cards.
class GrowthOverviewPanel extends StatelessWidget {
  const GrowthOverviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final history = service.samplingHistory;
    final latest = history.isNotEmpty ? history.last : null;
    final initialW = service.initialWeight;
    final initialL = service.initialLength;

    final latestW = latest?.abw ?? initialW;
    final latestL = latest?.avgLength ?? initialL;

    final diffW = latestW - initialW;
    final diffL = latestL - initialL;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Growth Overview',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
          ),
          const SizedBox(height: 16),
          // First Row: Initial and Latest
          Row(
            children: [
              _buildMiniCard(
                'Initial Baseline',
                _formatDate(service.stockingDate),
                initialW,
                initialL,
                AppColors.primaryWith(0.08),
                AppColors.primary,
                'Avg Weight',
                'Avg Length',
              ),
              const SizedBox(width: 12),
              _buildMiniCard(
                'Latest Sampling',
                latest != null ? _formatDate(latest.date) : _formatDate(service.stockingDate),
                latestW,
                latestL,
                AppColors.successWith(0.08),
                AppColors.success,
                'Avg Weight',
                'Avg Length',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Second Row: Growth (Full Width)
          _buildGrowthFullCard(diffW, diffL),
        ],
      ),
    );
  }

  Widget _buildMiniCard(
    String title,
    String subTitle,
    double weight,
    double length,
    Color bgColor,
    Color accentColor,
    String weightLabel,
    String lengthLabel,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subTitle,
              style: TextStyle(
                fontSize: 9,
                color: AppColors.darkWith(0.5),
              ),
            ),
            const SizedBox(height: 12),
            _buildDataRow(weightLabel, '${weight.toStringAsFixed(1)} g'),
            _buildDataRow(lengthLabel, '${length.toStringAsFixed(1)} cm'),
          ],
        ),
      ),
    );
  }

  Widget _buildGrowthFullCard(double weight, double length) {
    final isPosW = weight >= 0;
    final isPosL = length >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.warningWith(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warningWith(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Net Growth',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.warningDark),
          ),
          Row(
            children: [
              _buildGrowthMetric('Avg Weight', '${isPosW ? '+' : ''}${weight.toStringAsFixed(1)} g', isPosW),
              const SizedBox(width: 16),
              _buildGrowthMetric('Avg Length', '${isPosL ? '+' : ''}${length.toStringAsFixed(1)} cm', isPosL),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthMetric(String label, String value, bool isPos) {
    return Column(
      children: [
        Text('$label:', style: TextStyle(fontSize: 8, color: AppColors.darkWith(0.5))),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: isPos ? AppColors.success : AppColors.critical,
          ),
        ),
      ],
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.6))),
          Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// A widget that displays the "Weekly Sampling" form.
class SamplingFormPanel extends StatefulWidget {
  const SamplingFormPanel({super.key});

  @override
  State<SamplingFormPanel> createState() => _SamplingFormPanelState();
}

class _SamplingFormPanelState extends State<SamplingFormPanel> {
  final _countController = TextEditingController();
  final _weightController = TextEditingController();
  final _lengthController = TextEditingController();

  @override
  void dispose() {
    _countController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                'Weekly Sampling',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'Edit',
                  style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Input fields in a Row with absolutely uniform width
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildInputCard('Sample Count', '10', _countController)),
              const SizedBox(width: 8),
              Expanded(child: _buildInputCard('Total Weight (g)', '150', _weightController)),
              const SizedBox(width: 8),
              Expanded(child: _buildInputCard('Total Length (cm)', '60', _lengthController)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: AppColors.primaryGradient),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryWith(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () {
                  final count = int.tryParse(_countController.text);
                  final weight = double.tryParse(_weightController.text);
                  final length = double.tryParse(_lengthController.text);

                  if (count != null && weight != null && length != null && count > 0 && weight > 0 && length > 0) {
                    TankService.instance.addSamplingEntry(count, weight, length);
                    _countController.clear();
                    _weightController.clear();
                    _lengthController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sampling results recorded!')));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Compute Results',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard(String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.darkWith(0.5),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.lightBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            hintStyle: TextStyle(fontSize: 12, color: AppColors.darkWith(0.3)),
          ),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// A widget that displays the "Growth Stage" progress bar.
class GrowthStagePanel extends StatelessWidget {
  final VoidCallback onInfoTap;
  const GrowthStagePanel({super.key, required this.onInfoTap});

  @override
  Widget build(BuildContext context) {
    final stages = [
      {'name': 'Juvenile', 'threshold': 5.0},
      {'name': 'Early Grow-out', 'threshold': 15.0},
      {'name': 'Mid Grow-out', 'threshold': 30.0},
      {'name': 'Late Grow-out', 'threshold': 50.0},
      {'name': 'Market Size', 'threshold': 100.0},
    ];

    // Calculate current progress based on ABW
    final history = TankService.instance.samplingHistory;
    final currentAbw = history.isNotEmpty ? history.last.abw : TankService.instance.initialWeight;
    
    // Find active stage index
    int activeIndex = 0;
    for (int i = 0; i < stages.length; i++) {
      if (currentAbw >= (stages[i]['threshold'] as double)) {
        activeIndex = i;
      }
    }

    final double progress = (activeIndex + 1) / stages.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.04),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Growth Stage',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
                  ),
                  Text(
                    'Current: ${stages[activeIndex]['name']}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onInfoTap,
                child: const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Polished Progress Bar
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Background track
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.darkWith(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              // Animated Gradient Fill
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return FractionallySizedBox(
                    widthFactor: value,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF52c283), AppColors.primary],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryWith(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Step Markers (Ticks)
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(stages.length, (i) {
                    final isActive = i <= activeIndex;
                    return Container(
                      width: 2,
                      height: 8,
                      color: isActive ? Colors.white.withValues(alpha: 0.5) : Colors.transparent,
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stage Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(stages.length, (i) {
              final isActive = i == activeIndex;
              final isReached = i <= activeIndex;
              return Expanded(
                child: Text(
                  stages[i]['name'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive 
                        ? AppColors.primary 
                        : (isReached ? AppColors.darkWith(0.7) : AppColors.darkWith(0.3)),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// A widget that displays the "Sampling History" list.
class SamplingHistoryPanel extends StatelessWidget {
  const SamplingHistoryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final history = TankService.instance.samplingHistory;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sampling History',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
          ),
          const SizedBox(height: 16),
          if (history.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No sampling history yet.',
                  style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.4)),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = history[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          color: AppColors.primaryWith(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.history_rounded, size: 16, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.date.month}/${entry.date.day}/${entry.date.year}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.dark),
                            ),
                            Text(
                              '${entry.sampleSize} samples recorded',
                              style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.5)),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${entry.abw.toStringAsFixed(1)}g | ${entry.avgLength.toStringAsFixed(1)}cm',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
