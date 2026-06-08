import 'package:flutter/material.dart';
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

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _showAIInsights() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildAIInsightsSheet(ctx),
    );
  }

  // SIMULATED PYTHON ML API FETCHING
  Future<List<Map<String, dynamic>>> _fetchMLData() async {
    // Naghihintay ng 2 seconds para makita ang "Analyzing..." animation
    await Future.delayed(const Duration(seconds: 2));

    return [
      {
        'title': 'Temperature',
        'iconPath': 'assets/icons/temperature.png',
        'color': AppColors.warning,
        'status': 'Warning',
        'statusColor': AppColors.warning,
        'insight':
            'Currently at 29.5°C. Temperature is rising faster than usual.',
        'prediction':
            'AI predicts it will reach the critical level of 32°C in the next 3 hours.',
        'recommendation':
            'Turn on the cooling fans immediately and block direct sunlight to the tank.',
      },
      {
        'title': 'pH Level',
        'iconPath': 'assets/icons/pH.png',
        'color': AppColors.primary,
        'status': 'Stable',
        'statusColor': AppColors.success,
        'insight': 'pH is at 7.2. Water chemistry is highly optimal.',
        'prediction':
            'AI predicts pH will remain stable between 7.1 and 7.3 for the next 24 hours.',
        'recommendation': 'No action needed. Keep current feeding routine.',
      },
      {
        'title': 'Dissolved Oxygen',
        'iconPath': 'assets/icons/DO.png',
        'color': const Color(0xFF52c283),
        'status': 'Stable',
        'statusColor': AppColors.success,
        'insight': 'DO is at 5.5 mg/L. Aeration is performing efficiently.',
        'prediction':
            'AI predicts DO will drop slightly at night but will stay above safe limits.',
        'recommendation': 'Ensure air pump remains plugged in overnight.',
      },
      {
        'title': 'Turbidity',
        'iconPath': 'assets/icons/Turbidity.png',
        'color': AppColors.critical,
        'status': 'Action Needed',
        'statusColor': AppColors.critical,
        'insight':
            'Water clarity is decreasing (45 NTU). High suspended solids detected.',
        'prediction':
            'AI predicts a possible ammonia spike in 12 hours due to accumulated waste.',
        'recommendation':
            'Perform a 20% water change and clean the mechanical filtration sponge.',
      },
    ];
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

          // FUTURE BUILDER: Dito ginagawa ang Loading at List ng Data
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchMLData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'CrayAI is analyzing your tank data...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.dark.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return const Center(
                    child: Text(
                      'Failed to load ML Insights',
                      style: TextStyle(color: AppColors.critical),
                    ),
                  );
                }

                final mlData = snapshot.data!;

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: mlData.length,
                  itemBuilder: (context, index) {
                    final item = mlData[index];
                    return _buildSmartInsightCard(
                      title: item['title'],
                      iconPath: item['iconPath'],
                      iconColor: item['color'],
                      status: item['status'],
                      statusColor: item['statusColor'],
                      insight: item['insight'],
                      prediction: item['prediction'],
                      recommendation: item['recommendation'],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
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
