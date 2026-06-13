import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/sensor_service.dart';
import '../../services/settings_service.dart';
import '../../services/ml_service.dart';

class MovableAiLogo extends StatefulWidget {
  const MovableAiLogo({super.key});

  @override
  State<MovableAiLogo> createState() => _MovableAiLogoState();
}

class _MovableAiLogoState extends State<MovableAiLogo>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(300, 500);
  late AnimationController _pulseController;
  final double _logoSize = 60.0;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  void _showAIInsights() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildAIInsightsSheet(ctx),
    );
  }



  Map<String, dynamic>? _mlData;
  bool _mlLoading = true;
  String? _mlError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SensorService.instance.addListener(_onSensorOrSettingsChanged);
    SettingsService.instance.addListener(_onSensorOrSettingsChanged);
    MlService.instance.addListener(_onMlChanged);
    _refreshInsights();
  }

  void _onSensorOrSettingsChanged() {
    _generateLocalInsights();
  }

  void _onMlChanged() {
    if (MlService.instance.hasData) {
      _useMlData(MlService.instance.latestPrediction!);
    } else {
      _generateLocalInsights();
    }
  }

  Widget _buildAIInsightsSheet(BuildContext ctx) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER NG BOTTOM SHEET
          Row(
            children: [
              // PINALITAN NATIN YUNG ICON NG IMAGE.ASSET PARA SA CRAY AI LOGO
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/images/AI_InsightLogo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'CrayAI Analytics',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const Spacer(),
              // CLOSE BUTTON
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.pop(ctx),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.dark.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // FIREBASE-DRIVEN ML INSIGHTS: No more HTTP call
          Expanded(
            child: _mlLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.primary),
                        SizedBox(height: 16),
                        Text(
                          'CrayAI is analyzing your tank data...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.dark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : _mlError != null || _mlData == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud_off_rounded,
                                size: 40,
                                color: AppColors.critical.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _mlError ?? 'No ML data available',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.dark.withValues(alpha: 0.6),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildMLResults(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    SensorService.instance.removeListener(_onSensorOrSettingsChanged);
    SettingsService.instance.removeListener(_onSensorOrSettingsChanged);
    MlService.instance.removeListener(_onMlChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _refreshInsights() {
    if (MlService.instance.hasData) {
      _useMlData(MlService.instance.latestPrediction!);
    } else {
      _generateLocalInsights();
    }
  }

  void _useMlData(Map<String, dynamic> mlData) {
    final rawSensors = mlData['sensors'] as List<dynamic>?;
    if (rawSensors == null || rawSensors.isEmpty) {
      _generateLocalInsights();
      return;
    }

    final sensors = rawSensors.map((s) {
      final map = s as Map<String, dynamic>;
      final key = map['key'] as String? ?? '';
      final fbKey = _localKeyToFbKey(key);
      return {
        'key': fbKey,
        'status': map['status'] as String? ?? 'UNKNOWN',
        'insight': map['insight'] as String? ?? '',
        'prediction': map['prediction'] as String? ?? '',
        'recommendation': map['recommendation'] as String? ?? '',
      };
    }).toList();

    _mlData = {'sensors': sensors};
    _mlError = null;
    _mlLoading = false;
    if (mounted) setState(() {});
  }

  String _localKeyToFbKey(String mlKey) {
    switch (mlKey) {
      case 'temperature': return 'temperature';
      case 'phLevel': return 'phLevel';
      case 'dissolvedOxygen': return 'dissolvedOxygen';
      case 'turbidity': return 'turbidity';
      case 'waterLevel': return 'waterLevel';
      default: return mlKey;
    }
  }

  void _generateLocalInsights() {
    final ss = SensorService.instance;
    final ranges = SettingsService.instance.currentRanges;
    final sensorKeys = [
      {'key': 'temperature', 'sensorKey': 'temp', 'unit': '°C'},
      {'key': 'phLevel', 'sensorKey': 'ph', 'unit': ''},
      {'key': 'dissolvedOxygen', 'sensorKey': 'do', 'unit': 'mg/L'},
      {'key': 'turbidity', 'sensorKey': 'turb', 'unit': 'NTU'},
      {'key': 'waterLevel', 'sensorKey': 'waterlevel', 'unit': 'cm'},
    ];

    final sensors = <Map<String, dynamic>>[];
    for (final info in sensorKeys) {
      final sensorKey = info['sensorKey'] as String;
      final hasData = ss.hasSensorData(sensorKey);
      final value = ss.getLatestValue(sensorKey);
      final range = ranges[sensorKey];
      final min = range?['min'] ?? 0.0;
      final max = range?['max'] ?? 999.0;

      String status;
      if (!hasData) {
        status = 'UNKNOWN';
      } else if (value >= min && value <= max) {
        status = 'OPTIMAL';
      } else {
        status = 'CRITICAL';
      }

      String insight, prediction, recommendation;
      if (!hasData) {
        insight = 'No sensor data available.';
        prediction = 'Unable to predict.';
        recommendation = 'Check sensor connection.';
      } else {
        final valStr = value.toStringAsFixed(2);
        final minStr = min.toStringAsFixed(1);
        final maxStr = max.toStringAsFixed(1);
        final unit = info['unit'] as String;

        if (status == 'OPTIMAL') {
          insight = 'Current reading: $valStr$unit. Within optimal range ($minStr–$maxStr$unit).';
          final midpoint = (min + max) / 2;
          prediction = value > midpoint
              ? 'Slightly above midpoint. Monitor for upward trend.'
              : 'Stable within range. No immediate action needed.';
          recommendation = 'Maintain current tank conditions.';
        } else if (value < min) {
          insight = 'Reading at $valStr$unit is below the minimum threshold ($minStr$unit).';
          prediction = 'May cause stress if not addressed.';
          recommendation = _recommendationFor(sensorKey, 'low');
        } else {
          insight = 'Reading at $valStr$unit exceeds the maximum threshold ($maxStr$unit).';
          prediction = 'Risk of adverse effects if prolonged.';
          recommendation = _recommendationFor(sensorKey, 'high');
        }
      }

      sensors.add({
        'key': info['key'],
        'status': status,
        'insight': insight,
        'prediction': prediction,
        'recommendation': recommendation,
      });
    }

    _mlData = {'sensors': sensors};
    _mlError = null;
    _mlLoading = false;
    if (mounted) setState(() {});
  }

  String _recommendationFor(String sensorKey, String direction) {
    switch (sensorKey) {
      case 'temp':
        return direction == 'low'
            ? 'Check heater. Gradually increase temperature.'
            : 'Check cooler/aeration. Reduce temperature gradually.';
      case 'ph':
        return direction == 'low'
            ? 'Add pH buffer. Check water source.'
            : 'Add pH reducer. Check for contaminants.';
      case 'do':
        return direction == 'low'
            ? 'Increase aeration. Check water surface agitation.'
            : 'Reduce aeration. Check for algae bloom.';
      case 'turb':
        return direction == 'low'
            ? 'Normal clarity. Monitor regularly.'
            : 'Check filtration. Consider water change.';
      case 'waterlevel':
        return direction == 'low'
            ? 'Add water. Check for leaks.'
            : 'Drain excess water. Check drainage.';
      default:
        return 'Check sensor and tank conditions.';
    }
  }

  static const _sensorDisplayInfo = {
    'temperature': {'title': 'Temperature', 'icon': 'assets/icons/temperature.png', 'color': Color(0xFFf59e0b)},
    'phLevel': {'title': 'pH Level', 'icon': 'assets/icons/pH.png', 'color': Color(0xFF1FA5A5)},
    'dissolvedOxygen': {'title': 'Dissolved Oxygen', 'icon': 'assets/icons/DO.png', 'color': Color(0xFF52c283)},
    'turbidity': {'title': 'Turbidity', 'icon': 'assets/icons/Turbidity.png', 'color': Color(0xFFE63946)},
    'waterLevel': {'title': 'Water Level', 'icon': 'assets/images/waterLevel.png', 'color': Color(0xFF1FA5A5)},
  };

  Widget _buildMLResults() {
    final data = _mlData!;
    final rawSensors = data['sensors'] as List<dynamic>? ?? [];
    if (rawSensors.isEmpty) {
      return const Center(child: Text('No sensor data available.'));
    }

    final sensorsData = rawSensors.cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: sensorsData.map((s) {
        final key = s['key'] as String? ?? '';
        final display = _sensorDisplayInfo[key];
        if (display == null) return const SizedBox.shrink();

        return _buildSmartInsightCard(
          title: display['title'] as String,
          iconPath: display['icon'] as String,
          insight: s['insight'] as String? ?? '',
          prediction: s['prediction'] as String? ?? '',
          recommendation: s['recommendation'] as String? ?? '',
        );
      }).toList(),
    );
  }

  Widget _buildSmartInsightCard({
    required String title,
    required String iconPath,
    required String insight,
    required String prediction,
    required String recommendation,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.dark.withValues(alpha: 0.08),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TITLE ROW (no status badge)
          Row(
            children: [
              Image.asset(iconPath, width: 22, height: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(
              color: AppColors.dark.withValues(alpha: 0.05),
              thickness: 1,
            ),
          ),

          // ML OUTPUTS
          _buildDetailRow(
            'Insight',
            insight,
            Icons.lightbulb_outline,
            AppColors.primary,
          ),
          const SizedBox(height: 10),
          _buildDetailRow(
            'Prediction',
            prediction,
            Icons.trending_up,
            const Color(0xFF8E44AD),
          ),
          const SizedBox(height: 10),
          _buildDetailRow(
            'Recommendation',
            recommendation,
            Icons.build_circle_outlined,
            const Color(0xFFE67E22),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String text,
    IconData icon,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.dark.withValues(alpha: 0.7),
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth - _logoSize - 16;
        final maxH = constraints.maxHeight - _logoSize - 16;
        const minW = 16.0;
        const minH = 16.0;

        if (!_isInitialized) {
          _position = Offset(maxW, maxH - 40);
          _isInitialized = true;
        }

        return Stack(
          children: [
            Positioned(
              left: _position.dx,
              top: _position.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _position = Offset(
                      (_position.dx + details.delta.dx).clamp(minW, maxW),
                      (_position.dy + details.delta.dy).clamp(minH, maxH),
                    );
                  });
                },
                onTap: _showAIInsights,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: _logoSize,
                      height: _logoSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      child: ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.asset(
                            'assets/images/AI_InsightLogo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
