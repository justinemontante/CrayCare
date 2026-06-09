import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../theme/app_colors.dart';

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



  StreamSubscription<DatabaseEvent>? _mlSub;
  Map<String, dynamic>? _mlData;
  bool _mlLoading = true;
  String? _mlError;

  final DatabaseReference _mlPredictionRef = FirebaseDatabase.instance.ref(
    'ml_predictions/latest',
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mlSub ??= _mlPredictionRef.onValue.listen((e) {
      if (!e.snapshot.exists || e.snapshot.value == null) {
        _mlData = null;
        _mlError = 'No ML prediction available yet.';
      } else {
        _mlData = _deepConvert(e.snapshot.value);
        _mlError = null;
      }
      _mlLoading = false;
      if (mounted) setState(() {});
    });
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
    _mlSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _deepConvert(Object? value) {
    if (value is Map) {
      return value.map<String, dynamic>((k, v) => MapEntry(
        k.toString(),
        _deepConvertValue(v),
      ));
    }
    return {};
  }

  dynamic _deepConvertValue(Object? v) {
    if (v is Map) return _deepConvert(v);
    if (v is List) return v.map((e) => _deepConvertValue(e)).toList();
    return v;
  }

  static const _sensorDisplayInfo = {
    'temperature': {'title': 'Temperature', 'icon': 'assets/icons/temperature.png', 'color': Color(0xFFf59e0b)},
    'phLevel': {'title': 'pH Level', 'icon': 'assets/icons/pH.png', 'color': Color(0xFF1FA5A5)},
    'dissolvedOxygen': {'title': 'Dissolved Oxygen', 'icon': 'assets/icons/DO.png', 'color': Color(0xFF52c283)},
    'turbidity': {'title': 'Turbidity', 'icon': 'assets/icons/Turbidity.png', 'color': Color(0xFFE63946)},
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

        final sensorStatus = s['status'] as String? ?? 'OPTIMAL';
        final isCritical = sensorStatus == 'CRITICAL';

        return _buildSmartInsightCard(
          title: display['title'] as String,
          iconPath: display['icon'] as String,
          iconColor: display['color'] as Color,
          status: isCritical ? 'Critical' : 'Optimal',
          statusColor: isCritical ? AppColors.critical : AppColors.success,
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
    required Color iconColor,
    required String status,
    required Color statusColor,
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
          // TITLE AND STATUS ROW
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
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 0.3,
                  ),
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
