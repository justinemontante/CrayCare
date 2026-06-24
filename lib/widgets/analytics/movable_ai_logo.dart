import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
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

  Color _statusColor(String? status) {
    switch (status) {
      case 'OPTIMAL': return const Color(0xFF22c55e);
      case 'WARNING': return const Color(0xFFf59e0b);
      case 'CRITICAL': return const Color(0xFFef4444);
      default: return AppColors.dark.withValues(alpha: 0.3);
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
      child: ListenableBuilder(
        listenable: MlService.instance,
        builder: (context, _) {
          final loading = MlService.instance.loading;
          final error = MlService.instance.error;
          final mlRaw = MlService.instance.latestPrediction;
          final hasFresh = MlService.instance.hasFreshData;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
              if (!loading && mlRaw != null && hasFresh) ...[
                const SizedBox(height: 12),
                _buildOverallStatusBadge(mlRaw),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: loading
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
                    : error != null || !hasFresh
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
                                    error ?? 'CrayAI is waiting for sensor data...',
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
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 24),
                            children: [
                              _buildOverallSummaryCard(
                                icon: Icons.lightbulb_outline,
                                label: 'Insight',
                                text: mlRaw?['insight'] as String? ?? '',
                                color: AppColors.primary,
                              ),
                              _buildOverallSummaryCard(
                                icon: Icons.build_circle_outlined,
                                label: 'Recommendation',
                                text: mlRaw?['recommendation'] as String? ?? '',
                                color: const Color(0xFFE67E22),
                              ),
                              _buildOverallSummaryCard(
                                icon: Icons.trending_up,
                                label: 'Prediction',
                                text: mlRaw?['prediction'] as String? ?? '',
                                color: const Color(0xFF8E44AD),
                              ),
                            ],
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverallStatusBadge(Map<String, dynamic> mlData) {
    final status = mlData['predictedStatus'] as String? ?? 'UNKNOWN';
    final confidence = (mlData['confidence'] as num?)?.toDouble() ?? 0.0;
    final stage = mlData['stage'] as String? ?? '';
    final statusColor = _statusColor(status);
    final confPct = (confidence * 100).toInt();
    final stageLabelText = stage.isNotEmpty ? _stageLabel(stage) : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.dark.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (stageLabelText.isNotEmpty)
                  RichText(
                    text: TextSpan(
                      text: 'Current Stage: ',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: stageLabelText,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (stageLabelText.isNotEmpty) const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$confPct% confidence',
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
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

  String _stageLabel(String stage) {
    const labels = {
      'early_juvenile': 'Early Juvenile',
      'advanced_juvenile': 'Advanced Juvenile',
      'pre_adult': 'Pre-Adult',
      'market_size': 'Market Size',
    };
    return labels[stage] ?? stage.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  Widget _buildOverallSummaryCard({
    required IconData icon,
    required String label,
    required String text,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.dark.withValues(alpha: 0.08),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16,
                        color: AppColors.dark.withValues(alpha: 0.5)),
                    const SizedBox(width: 6),
                    Text(
                      label,
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
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
