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
  final double _logoSize = 46.0;

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

  Widget _buildAIInsightsSheet(BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CrayAI Insights',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                  Text(
                    'Smart recommendations for your tank',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildInsightItem(
            'Temperature',
            'Currently stable at 28.5\u00B0C. AI predicts no stress for the next 4 hours.',
            Icons.thermostat,
            AppColors.warning,
          ),
          _buildInsightItem(
            'pH Level',
            'pH is at 7.2. Optimal for molting. Keep water parameters consistent.',
            Icons.science,
            AppColors.primary,
          ),
          _buildInsightItem(
            'Dissolved O\u2082',
            'Oxygen levels are high. Aeration system is performing efficiently.',
            Icons.air,
            const Color(0xFF52c283),
          ),
          _buildInsightItem(
            'Turbidity',
            'Water clarity is slightly low. Consider checking the filtration sponge.',
            Icons.water,
            AppColors.critical,
          ),
          _buildInsightItem(
            'Water Level',
            'Level is 150cm. Sufficient for adult crayfish population.',
            Icons.height,
            AppColors.primary,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Got it, thanks!',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightItem(
      String title, String desc, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.darkWith(0.6),
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

  bool _isInitialized = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    // Initial position logic (sa kanang ibaba)
    if (!_isInitialized) {
      _position = Offset(size.width - _logoSize - 20, size.height - 200);
      _isInitialized = true;
    }

    final maxW = size.width - _logoSize - 16;
    final maxH = size.height - _logoSize - 100; // Offset para sa bottom nav
    const minW = 16.0;
    const minH = 100.0; // Offset para sa header

    return Positioned(
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
                    color: AppColors.primary.withValues(
                      alpha: 0.3 * _pulseController.value,
                    ),
                    blurRadius: 12,
                    spreadRadius: 4 * _pulseController.value,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: AppColors.primary.withValues(
                    alpha: 0.2 + (0.3 * _pulseController.value),
                  ),
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/AI_InsightLogo.png',
                  fit: BoxFit.cover,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
