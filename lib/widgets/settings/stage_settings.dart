import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/crayfish_stage.dart';
import '../../services/settings_service.dart';
import '../../services/database_service.dart';

class StageSettings extends StatefulWidget {
  const StageSettings({super.key});

  @override
  State<StageSettings> createState() => _StageSettingsState();
}

class _SensorMeta {
  final String label;
  final String unit;
  final String iconPath;
  final Color color;
  const _SensorMeta({
    required this.label,
    required this.unit,
    required this.iconPath,
    required this.color,
  });
}

class _StageSettingsState extends State<StageSettings> {
  static Map<String, dynamic> _convertMap(Object? value) {
    if (value is Map) {
      return value.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  final List<String> sensors = const ['temp', 'ph', 'do', 'turb', 'waterlevel'];

  final Map<String, _SensorMeta> sensorMeta = const {
    'temp': _SensorMeta(
      label: 'Temperature', unit: '\u00B0C',
      iconPath: 'assets/images/temperature.png', color: Color(0xFFF59E0B),
    ),
    'ph': _SensorMeta(
      label: 'pH Level', unit: 'pH',
      iconPath: 'assets/images/pH.png', color: Color(0xFF8B5CF6),
    ),
    'do': _SensorMeta(
      label: 'Dissolved Oxygen', unit: 'mg/L',
      iconPath: 'assets/images/DO.png', color: Color(0xFF3B82F6),
    ),
    'turb': _SensorMeta(
      label: 'Turbidity', unit: 'NTU',
      iconPath: 'assets/images/Turbidity.png', color: Color(0xFF64748B),
    ),
    'waterlevel': _SensorMeta(
      label: 'Water Level', unit: 'cm',
      iconPath: 'assets/images/waterLevel.png', color: AppColors.primary,
    ),
  };

  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadConfigFromFirebase();
  }

  Future<void> _loadConfigFromFirebase() async {
    try {
      final data = await DatabaseService.instance.getGrowthStageConfig();
      if (data == null) {
        await _saveConfigToFirebase(showMessage: false);
        if (mounted) setState(() => _loading = false);
        return;
      }

      final svc = SettingsService.instance;

      final stage = data['currentStage'];
      if (stage is String &&
          stage.isNotEmpty &&
          CrayfishStage.all.any((s) => s.name == stage)) {
        svc.setCurrentStage(stage);
      }

      final allRaw = data['allRanges'];
      if (allRaw is Map) {
        final all = _convertMap(allRaw);
        for (final stageEntry in all.entries) {
          final stageName = stageEntry.key;
          if (!CrayfishStage.all.any((s) => s.name == stageName)) continue;
          if (stageEntry.value is! Map) continue;

          final stageData = _convertMap(stageEntry.value as Map);
          for (final sensorKey in sensors) {
            final sRaw = stageData[sensorKey];
            if (sRaw is! Map) continue;
            final sMap = _convertMap(sRaw);
            final min = _toDouble(sMap['min']);
            final max = _toDouble(sMap['max']);
            if (min == null || max == null) continue;
            svc.updateRange(stageName, sensorKey, min, max);
          }
        }
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Using local settings (Firebase: $e)'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double? _toDouble(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  void _showSuccessModal(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF22c55e).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF22c55e),
                size: 50,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Updated Successfully!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.dark.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveConfigToFirebase({
    String? changedKey,
    bool showMessage = true,
  }) async {
    if (mounted) setState(() => _saving = true);
    try {
      final svc = SettingsService.instance;

      await Future.wait([
        DatabaseService.instance.saveGrowthStageConfig(
          currentStage: svc.currentStage,
          allRanges: svc.allRanges,
          changedKey: changedKey,
        ),
        DatabaseService.instance.saveSensorThresholds(
          currentStage: svc.currentStage,
          currentRanges: svc.currentRanges,
          changedKey: changedKey,
        ),
      ]);

      if (!mounted) return;
      setState(() => _saving = false);
      if (showMessage) {
        final msg = changedKey != null
            ? 'Threshold updated!'
            : 'Stage and thresholds saved!';
        _showSuccessModal(msg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save to Firebase: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _formatMax(double max) {
    if (max >= 999) return '\u221E';
    return max.toStringAsFixed(1);
  }

  void _showRangeEditor(
    String stageName,
    String sensorKey,
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
                color: sensorMeta[sensorKey]!.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset(
                sensorMeta[sensorKey]!.iconPath,
                width: 20, height: 20,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.dark,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adjust the ideal range for ${CrayfishStage.fromName(stageName).label}.',
              style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.5)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildModalField('Minimum', minCtrl, unit)),
                const SizedBox(width: 12),
                Expanded(child: _buildModalField('Maximum', maxCtrl, unit)),
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
                fontSize: 13, fontWeight: FontWeight.w700,
                color: AppColors.darkWith(0.4),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final min = double.tryParse(minCtrl.text.trim()) ?? currentMin;
              final max =
                  double.tryParse(maxCtrl.text.trim()) ??
                  (currentMax >= 999 ? 999.0 : currentMax);
              if (min >= max) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Minimum must be lower than maximum'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              SettingsService.instance.updateRange(stageName, sensorKey, min, max);
              Navigator.pop(ctx);
              setState(() {});
              await _saveConfigToFirebase(changedKey: sensorKey);
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

  Widget _buildModalField(String label, TextEditingController ctrl, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.dark,
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
              fontSize: 10, fontWeight: FontWeight.w600,
              color: AppColors.darkWith(0.4),
            ),
            filled: true,
            fillColor: AppColors.darkWith(0.04),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 14,
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

  Widget _buildSensorRow(String stageName, String sensorKey) {
    final svc = SettingsService.instance;
    final stageRanges = svc.allRanges[stageName] ?? {};
    final range = stageRanges[sensorKey] ?? {'min': 0.0, 'max': 0.0};
    final info = sensorMeta[sensorKey]!;
    final min = (range['min'] ?? 0.0).toDouble();
    final max = (range['max'] ?? 0.0).toDouble();

    return Container(
      height: 52,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.04)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _saving
              ? null
              : () => _showRangeEditor(
                  stageName, sensorKey, info.label, info.unit, min, max,
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: info.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.asset(
                    info.iconPath, width: 16, height: 16,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    info.label,
                    style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark,
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${min.toStringAsFixed(1)} \u2013 ${_formatMax(max)}',
                      style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      info.unit,
                      style: TextStyle(
                        fontSize: 8, fontWeight: FontWeight.w800,
                        color: AppColors.darkWith(0.3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stages = CrayfishStage.all;
    final svc = SettingsService.instance;
    final activeStage = svc.currentStageObj;

    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_saving)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Syncing to Firebase...',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                ],
              ),
            ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'Select current stage of your crayfish',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
            ),
            ...() {
              final cards = stages.map((stage) {
                final isActive = stage.name == svc.currentStage;
                return Container(
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? AppColors.primary.withValues(alpha: 0.3)
                          : AppColors.dark.withValues(alpha: 0.06),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: isActive
                        ? null
                        : () {
                            svc.setCurrentStage(stage.name);
                            setState(() {});
                            DatabaseService.instance.saveGrowthStageConfig(
                              currentStage: stage.name,
                              allRanges: svc.allRanges,
                            );
                            DatabaseService.instance.saveSensorThresholds(
                              currentStage: stage.name,
                              currentRanges: svc.allRanges[stage.name] ?? {},
                            );
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isActive
                                        ? AppColors.primary
                                        : AppColors.darkWith(0.25),
                                    width: isActive ? 5 : 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  stage.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isActive ? AppColors.primary : AppColors.dark,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _showStageInfo(stage),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    size: 13,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            stage.description,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.darkWith(0.5),
                            ),
                          ),

                        ],
                      ),
                    ),
                  ),
                );
              }).toList();
              return [
                SizedBox(
                  height: 210,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 6),
                            Expanded(child: cards[1]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: cards[2]),
                            const SizedBox(width: 6),
                            Expanded(child: cards[3]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ];
            }(),
          ],
          const SizedBox(height: 8),
          Container(height: 1, color: AppColors.dark.withValues(alpha: 0.06), margin: const EdgeInsets.symmetric(vertical: 4)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
                        child: Text(
                          'Sensor Thresholds for ${activeStage.label}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dark,
                          ),
                        ),
                      ),
                      ...sensors.map((key) => _buildSensorRow(activeStage.name, key)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _showStageInfo(CrayfishStage stage) {
    final ranges = SettingsService.instance.allRanges[stage.name] ?? {};
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    stage.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Text(
                  stage.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.darkWith(0.6),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Text(
                  'Optimal Sensor Ranges',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkWith(0.7),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Column(
                  children: sensors.map((key) {
                    final info = sensorMeta[key]!;
                    final range = ranges[key] ?? {'min': 0.0, 'max': 0.0};
                    final min = (range['min'] ?? 0.0).toDouble();
                    final max = (range['max'] ?? 0.0).toDouble();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.darkWith(0.03),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: info.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Image.asset(
                              info.iconPath, width: 12, height: 12,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              info.label,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.dark,
                              ),
                            ),
                          ),
                          Text(
                            '${min.toStringAsFixed(1)} \u2013 ${_formatMax(max)} ${info.unit}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}
