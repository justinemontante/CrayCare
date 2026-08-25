import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/settings_service.dart';
import '../../services/database_service.dart';

class SensorThresholdSettings extends StatefulWidget {
  const SensorThresholdSettings({super.key});

  @override
  State<SensorThresholdSettings> createState() =>
      _SensorThresholdSettingsState();
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

class _SensorThresholdSettingsState extends State<SensorThresholdSettings> {
  final List<String> sensors = const [
    'temp',
    'ph',
    'do',
    'turb',
    'waterlevel',
    'feedlevel',
  ];

  final Map<String, _SensorMeta> sensorMeta = const {
    'temp': _SensorMeta(
      label: 'Temperature',
      unit: '°C',
      iconPath: 'assets/images/temperature.png',
      color: Color(0xFFF59E0B),
    ),
    'ph': _SensorMeta(
      label: 'pH Level',
      unit: 'pH',
      iconPath: 'assets/images/pH.png',
      color: Color(0xFF8B5CF6),
    ),
    'do': _SensorMeta(
      label: 'Dissolved Oxygen',
      unit: 'mg/L',
      iconPath: 'assets/images/DO.png',
      color: Color(0xFF3B82F6),
    ),
    'turb': _SensorMeta(
      label: 'Turbidity',
      unit: 'NTU',
      iconPath: 'assets/images/Turbidity.png',
      color: Color(0xFF64748B),
    ),
    'waterlevel': _SensorMeta(
      label: 'Water Level',
      unit: 'cm',
      iconPath: 'assets/images/waterLevel.png',
      color: AppColors.primary,
    ),
    'feedlevel': _SensorMeta(
      label: 'Feed Level',
      unit: '%',
      iconPath: 'assets/images/FeedingImage.png',
      color: Color(0xFF14B8A6),
    ),
  };

  bool _saving = false;

  // Safety limits — mirror firestore.rules isSafeThreshold(). The app
  // validates BEFORE saving so users get a clear message instead of a
  // Firestore permission-denied error. Keys are the short sensor keys
  // used by SettingsService ('temp','ph','do','turb','waterlevel').
  static const Map<String, Map<String, double>> _safeBounds = {
    'temp': {'minLow': 10.0, 'minHigh': 32.0, 'maxLow': 15.0, 'maxHigh': 38.0},
    'ph': {'minLow': 4.0, 'minHigh': 7.5, 'maxLow': 6.5, 'maxHigh': 10.0},
    'do': {'minLow': 1.0, 'minHigh': 8.0, 'maxLow': 3.0, 'maxHigh': 15.0},
    'turb': {'minLow': 0.0, 'minHigh': 100.0, 'maxLow': 5.0, 'maxHigh': 1000.0},
    'waterlevel': {
      'minLow': 0.0,
      'minHigh': 95.0,
      'maxLow': 5.0,
      'maxHigh': 100.0,
    },
    'feedlevel': {
      'minLow': 1.0,
      'minHigh': 50.0,
      'maxLow': 100.0,
      'maxHigh': 100.0,
    },
  };

  static const Map<String, String> _safeUnits = {
    'temp': '°C',
    'ph': 'pH',
    'do': 'mg/L',
    'turb': 'NTU',
    'waterlevel': 'cm',
    'feedlevel': '%',
  };

  /// Returns a human-readable error message if any current range is outside
  /// the safe bounds, or null when everything is valid.
  String? _validateRanges() {
    final ranges = SettingsService.instance.currentRanges;
    for (final entry in ranges.entries) {
      final key = entry.key;
      final bounds = _safeBounds[key];
      if (bounds == null) continue;
      final min = entry.value['min'];
      final max = entry.value['max'];
      if (min == null || max == null) continue;
      final unit = _safeUnits[key] ?? '';
      final label = sensorMeta[key]?.label ?? key;
      if (key == 'feedlevel') {
        final critical = entry.value['critical'] ?? 10.0;
        final capacity = entry.value['capacity_grams'] ?? 1000.0;
        if (critical < 0 || critical >= min) {
          return 'Feed Level: critical threshold must be below the low threshold.';
        }
        if (capacity < 100 || capacity > 50000) {
          return 'Feed Level: hopper capacity must be 100–50,000 g.';
        }
      }
      if (min >= max) {
        return '$label: minimum must be lower than maximum.';
      }
      if (min < bounds['minLow']! || min > bounds['minHigh']!) {
        return '$label minimum ($min $unit) is outside the safe range '
            '${bounds['minLow']}–${bounds['minHigh']} $unit.';
      }
      if (max < bounds['maxLow']! || max > bounds['maxHigh']!) {
        return '$label maximum ($max $unit) is outside the safe range '
            '${bounds['maxLow']}–${bounds['maxHigh']} $unit.';
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
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

  Future<bool> _saveConfigToFirebase({
    String? changedKey,
    bool showMessage = true,
  }) async {
    // Block unsafe values client-side before hitting Firestore (which also
    // enforces the same bounds in rules).
    final validationError = _validateRanges();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ $validationError'),
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }
    if (mounted) setState(() => _saving = true);
    try {
      await DatabaseService.instance.saveSensorThresholds(
        currentRanges: SettingsService.instance.currentRanges,
        changedKey: changedKey,
      );
      if (!mounted) return true;
      setState(() => _saving = false);
      if (showMessage) {
        _showSuccessModal(
          changedKey != null ? 'Threshold updated!' : 'Thresholds saved!',
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save to Firebase: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  String _formatMax(double max) {
    if (max >= 999) return '∞';
    return max.toStringAsFixed(1);
  }

  void _showRangeEditor(
    String sensorKey,
    String label,
    String unit,
    double currentMin,
    double currentMax,
  ) {
    if (sensorKey == 'feedlevel') {
      _showFeedLevelEditor();
      return;
    }
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
                width: 20,
                height: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.dark,
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
              'Adjust the ideal sensor range.',
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
                fontSize: 13,
                fontWeight: FontWeight.w700,
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
              final bounds = _safeBounds[sensorKey];
              final unitText = _safeUnits[sensorKey] ?? '';
              String? candidateError;
              if (min >= max) {
                candidateError = 'Minimum must be lower than maximum.';
              } else if (bounds != null &&
                  (min < bounds['minLow']! || min > bounds['minHigh']!)) {
                candidateError =
                    'Minimum must be ${bounds['minLow']}–${bounds['minHigh']} $unitText.';
              } else if (bounds != null &&
                  (max < bounds['maxLow']! || max > bounds['maxHigh']!)) {
                candidateError =
                    'Maximum must be ${bounds['maxLow']}–${bounds['maxHigh']} $unitText.';
              }
              if (candidateError != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(candidateError),
                    duration: const Duration(seconds: 3),
                  ),
                );
                return;
              }

              await SettingsService.instance.updateRange(sensorKey, min, max);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) setState(() {});
              final saved = await _saveConfigToFirebase(changedKey: sensorKey);
              if (!saved) {
                await SettingsService.instance.updateRange(
                  sensorKey,
                  currentMin,
                  currentMax,
                );
              }
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
    ).whenComplete(() {
      minCtrl.dispose();
      maxCtrl.dispose();
    });
  }

  void _showFeedLevelEditor() {
    final config = SettingsService.instance.currentRanges['feedlevel']!;
    final previousCritical = config['critical'] ?? 10.0;
    final previousLow = config['min'] ?? 20.0;
    final previousCapacity = config['capacity_grams'] ?? 1000.0;
    final criticalCtrl = TextEditingController(
      text: (config['critical'] ?? 10).toStringAsFixed(0),
    );
    final lowCtrl = TextEditingController(
      text: (config['min'] ?? 20).toStringAsFixed(0),
    );
    final capacityCtrl = TextEditingController(
      text: (config['capacity_grams'] ?? 1000).toStringAsFixed(0),
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 21,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Feed Level Settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Warnings use percentage. Feeding is blocked only when empty or the estimated grams are insufficient.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: AppColors.darkWith(0.55),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildModalField(
                    'Critical at/below',
                    criticalCtrl,
                    '%',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildModalField('Low at/below', lowCtrl, '%')),
              ],
            ),
            const SizedBox(height: 12),
            _buildModalField('Hopper capacity', capacityCtrl, 'g'),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.darkWith(0.65),
                        side: BorderSide(color: AppColors.darkWith(0.12)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final critical = double.tryParse(
                          criticalCtrl.text.trim(),
                        );
                        final low = double.tryParse(lowCtrl.text.trim());
                        final capacity = double.tryParse(
                          capacityCtrl.text.trim(),
                        );
                        if (critical == null ||
                            low == null ||
                            capacity == null ||
                            critical < 0 ||
                            critical >= low ||
                            low > 50 ||
                            capacity < 100 ||
                            capacity > 50000) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Use Critical < Low ≤ 50%, and capacity 100–50,000 g.',
                              ),
                            ),
                          );
                          return;
                        }
                        await SettingsService.instance.updateFeedLevelConfig(
                          critical: critical,
                          low: low,
                          capacityGrams: capacity,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        final saved = await _saveConfigToFirebase(
                          changedKey: 'feedlevel',
                        );
                        if (!saved) {
                          await SettingsService.instance.updateFeedLevelConfig(
                            critical: previousCritical,
                            low: previousLow,
                            capacityGrams: previousCapacity,
                          );
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text(
                        'Update',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      criticalCtrl.dispose();
      lowCtrl.dispose();
      capacityCtrl.dispose();
    });
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

  Widget _buildSensorRow(String sensorKey) {
    final svc = SettingsService.instance;
    final range = svc.currentRanges[sensorKey] ?? {'min': 0.0, 'max': 0.0};
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
                  sensorKey,
                  info.label,
                  info.unit,
                  min,
                  max,
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
                  child: Image.asset(info.iconPath, width: 16, height: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    info.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      sensorKey == 'feedlevel'
                          ? 'Critical ≤${(range['critical'] ?? 10).toStringAsFixed(0)}% • Low ≤${min.toStringAsFixed(0)}%'
                          : '${min.toStringAsFixed(1)} – ${_formatMax(max)}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      sensorKey == 'feedlevel'
                          ? 'Capacity ${(range['capacity_grams'] ?? 1000).toStringAsFixed(0)} g'
                          : info.unit,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
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
    return Container(
      color: Colors.white,
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
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Syncing to Firebase...',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Sensor Thresholds',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              'Ideal sensor ranges for your tank',
              style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.45)),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: sensors.map((key) => _buildSensorRow(key)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
