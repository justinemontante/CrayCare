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
  final List<String> sensors = const ['temp', 'ph', 'do', 'turb', 'waterlevel'];

  final Map<String, _SensorMeta> sensorMeta = const {
    'temp': _SensorMeta(
      label: 'Temperature', unit: '°C',
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
      label: 'Turbidity / Water Quality', unit: '%',
      iconPath: 'assets/images/Turbidity.png', color: Color(0xFF64748B),
    ),
    'waterlevel': _SensorMeta(
      label: 'Water Level', unit: '%',
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
        final all = Map<String, dynamic>.from(allRaw);
        for (final stageEntry in all.entries) {
          final stageName = stageEntry.key;
          if (!CrayfishStage.all.any((s) => s.name == stageName)) continue;
          if (stageEntry.value is! Map) continue;

          final stageData = Map<String, dynamic>.from(stageEntry.value as Map);
          for (final sensorKey in sensors) {
            final sRaw = stageData[sensorKey];
            if (sRaw is! Map) continue;
            final sMap = Map<String, dynamic>.from(sRaw);
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

  Future<void> _saveConfigToFirebase({
    String? changedKey,
    bool showMessage = true,
  }) async {
    if (mounted) setState(() => _saving = true);
    try {
      final svc = SettingsService.instance;
      await DatabaseService.instance.saveGrowthStageConfig(
        currentStage: svc.currentStage,
        allRanges: svc.allRanges,
        changedKey: changedKey,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All stage thresholds synced to Firebase'),
            duration: Duration(seconds: 2),
          ),
        );
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStagePanel(CrayfishStage stage) {
    final svc = SettingsService.instance;
    final isCurrent = stage.name == svc.currentStage;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.dark.withValues(alpha: 0.06),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          unselectedWidgetColor: AppColors.darkWith(0.2),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : AppColors.dark.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isCurrent ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 16,
              color: isCurrent ? AppColors.primary : AppColors.darkWith(0.3),
            ),
          ),
          title: Text(
            stage.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
              color: isCurrent ? AppColors.primary : AppColors.dark,
            ),
          ),
          subtitle: Text(
            stage.description,
            style: TextStyle(
              fontSize: 9,
              color: AppColors.darkWith(0.45),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 8, fontWeight: FontWeight.w900,
                      color: AppColors.primary, letterSpacing: 0.5,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Icon(
                Icons.expand_more_rounded,
                color: AppColors.darkWith(0.35),
                size: 18,
              ),
            ],
          ),
          children: [
            ...sensors.map((key) => _buildSensorRow(stage.name, key)),
            if (!isCurrent)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      svc.setCurrentStage(stage.name);
                      setState(() {});
                      await _saveConfigToFirebase(showMessage: false);
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 12),
                    label: const Text(
                      'Set as Active Stage',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stages = CrayfishStage.all;

    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _saving
                        ? 'Syncing all stage thresholds to Firebase...'
                        : 'Expand any stage below to view & edit its sensor thresholds. Changes sync automatically to Firebase.',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.dark.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                ),
                if (_loading || _saving)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      ...stages.map((stage) => _buildStagePanel(stage)),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      SettingsService.instance.resetToDefaults();
                      setState(() {});
                      await _saveConfigToFirebase();
                    },
              icon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.dark),
              label: Text(
                'RESET ALL TO DEFAULTS AND SYNC',
                style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 10,
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
