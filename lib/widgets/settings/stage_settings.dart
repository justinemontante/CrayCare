import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/crayfish_stage.dart';
import '../../services/settings_service.dart';

class StageSettings extends StatefulWidget {
  const StageSettings({super.key});

  @override
  State<StageSettings> createState() => _StageSettingsState();
}

class _StageSettingsState extends State<StageSettings> {
  final sensors = ['temp', 'ph', 'do', 'turb', 'waterlevel'];

  Color _getSensorColor(String key) {
    switch (key) {
      case 'temp':
        return const Color(0xFFF59E0B);
      case 'ph':
        return const Color(0xFF8B5CF6);
      case 'do':
        return const Color(0xFF3B82F6);
      case 'turb':
        return const Color(0xFF64748B);
      case 'waterlevel':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  String _getSensorIconPath(String key) {
    switch (key) {
      case 'temp':
        return 'assets/images/temperature.png';
      case 'ph':
        return 'assets/images/pH.png';
      case 'do':
        return 'assets/images/DO.png';
      case 'turb':
        return 'assets/images/Turbidity.png';
      case 'waterlevel':
        return 'assets/images/waterLevel.png';
      default:
        return 'assets/images/logo.png';
    }
  }

  void _showRangeEditor(
    String key,
    String label,
    String unit,
    double currentMin,
    double currentMax,
  ) {
    final minCtrl = TextEditingController(text: currentMin.toStringAsFixed(1));
    final maxCtrl = TextEditingController(
      text: currentMax >= 999 ? '' : currentMax.toStringAsFixed(1),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getSensorColor(key).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset(
                _getSensorIconPath(key),
                width: 20,
                height: 20,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adjust the ideal range for this stage.',
              style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.5)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildModalField('Minimum', minCtrl, unit),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildModalField('Maximum', maxCtrl, unit),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.darkWith(0.4),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final min = double.tryParse(minCtrl.text) ?? currentMin;
              final max = double.tryParse(maxCtrl.text) ??
                  (currentMax >= 999 ? 999.0 : currentMax);
              SettingsService.instance.updateRange(
                SettingsService.instance.currentStage,
                key,
                min,
                max,
              );
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Update',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalField(
    String label,
    TextEditingController ctrl,
    String unit,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.dark,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          decoration: InputDecoration(
            suffixText: unit,
            suffixStyle: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.darkWith(0.4),
            ),
            filled: true,
            fillColor: AppColors.darkWith(0.04),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = SettingsService.instance;
    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Selecting a stage automatically updates the ideal sensor thresholds for your crayfish\'s development.',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.dark.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.dark.withValues(alpha: 0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.dark.withValues(alpha: 0.03),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Growth Stage',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.dark.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: svc.currentStage,
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      items: CrayfishStage.all
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.name,
                              child: Text(s.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) svc.setCurrentStage(v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 12,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      svc.currentStageObj.description,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'THRESHOLD PARAMETERS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: AppColors.dark.withValues(alpha: 0.4),
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: sensors.length,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final key = sensors[index];
                final range =
                    svc.currentRanges[key] ?? {'min': 0.0, 'max': 0.0};
                final info = sensorInfo[key]!;
                return Container(
                  height: 60,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.dark.withValues(alpha: 0.04),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _showRangeEditor(
                        key,
                        info.label,
                        info.unit,
                        range['min']!,
                        range['max']!,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.dark.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Image.asset(
                                _getSensorIconPath(key),
                                width: 20,
                                height: 20,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    info.label,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.dark,
                                    ),
                                  ),
                                  Text(
                                    'Standard Range',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: AppColors.dark.withValues(
                                        alpha: 0.4,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${range['min']!.toStringAsFixed(1)} \u2013 ${range['max']! >= 999 ? '\u221E' : range['max']!.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  info.unit,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.dark.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                SettingsService.instance.resetToDefaults();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ranges reset to defaults'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(
                Icons.refresh_rounded,
                size: 14,
                color: AppColors.dark,
              ),
              label: Text(
                'RESET TO DEFAULTS',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  color: AppColors.dark.withValues(alpha: 0.5),
                  letterSpacing: 0.5,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.dark.withValues(alpha: 0.03),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
