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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NextSamplingPanel(),
          const SizedBox(height: 16),
          const GrowthOverviewPanel(),
          const SizedBox(height: 16),
          const SamplingFormPanel(),
          const SizedBox(height: 16),
          GrowthStagePanel(onInfoTap: onShowGrowthStageReferenceModal),
          const SizedBox(height: 16),
          const SamplingHistoryPanel(),
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
    // For demonstration, let's assume a 7-day cycle
    final daysInCycle = 7;
    final currentDay = (service.daysInCulture % daysInCycle) + 1;
    final daysRemaining = daysInCycle - currentDay;

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
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
              Text(
                'Week ${((currentDay - 1) / 7).floor() + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkWith(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 16),
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

/// A widget that displays the "Growth Overview" with three key metrics.
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
                'Growth Overview',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'View Details',
                  style: TextStyle(color: AppColors.primary, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMiniCard(
                'Initial',
                '${service.stockingDate.month}/${service.stockingDate.day}',
                initialW,
                initialL,
                AppColors.primaryWith(0.1),
              ),
              const SizedBox(width: 8),
              _buildMiniCard(
                'Latest',
                latest != null
                    ? '${latest.date.month}/${latest.date.day}'
                    : '${service.stockingDate.month}/${service.stockingDate.day}',
                latestW,
                latestL,
                AppColors.successWith(0.1),
              ),
              const SizedBox(width: 8),
              _buildGrowthDiffCard(diffW, diffL),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCard(String title, String date, double weight, double length, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.faintBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
              ),
            ),
            Text(
              date,
              style: TextStyle(
                fontSize: 8,
                color: AppColors.darkWith(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${weight.toStringAsFixed(1)}g',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            Text(
              '${length.toStringAsFixed(1)}cm',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrowthDiffCard(double diffW, double diffL) {
    final isPositiveW = diffW >= 0;
    final isPositiveL = diffL >= 0;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.warningWith(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.faintBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Growth',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Text(
              '${isPositiveW ? '+' : ''}${diffW.toStringAsFixed(1)}g',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isPositiveW ? AppColors.success : AppColors.critical,
              ),
            ),
            Text(
              '${isPositiveL ? '+' : ''}${diffL.toStringAsFixed(1)}cm',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isPositiveL ? AppColors.success : AppColors.critical,
              ),
            ),
          ],
        ),
      ),
    );
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
      {'name': 'Juvenile', 'threshold': '5g'},
      {'name': 'Early', 'threshold': '15g'},
      {'name': 'Mid', 'threshold': '30g'},
      {'name': 'Late', 'threshold': '50g'},
      {'name': 'Market', 'threshold': '100g'},
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
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
              GestureDetector(
                onTap: onInfoTap,
                child: const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.lightBg,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(stages.length, (i) => Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: i <= 2 ? AppColors.primary : AppColors.lightBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                )),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: stages.map((s) => Text(
              s['name']!,
              style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.5)),
            )).toList(),
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
                'Sampling History',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              if (history.isNotEmpty)
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    'View All',
                    style: TextStyle(color: AppColors.primary, fontSize: 11),
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
                style: TextStyle(fontSize: 12, color: AppColors.subtitleText),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = history[index];
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
                          Text(
                            'Sampling',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.dark,
                            ),
                          ),
                          Text(
                            '${entry.date.month}/${entry.date.day}/${entry.date.year}',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.darkWith(0.5),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${entry.abw.toStringAsFixed(1)}g | ${entry.avgLength.toStringAsFixed(1)}cm | ${entry.sampleSize} samples',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
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
