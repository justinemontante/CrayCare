import 'package:flutter/material.dart';

class DashboardSkeleton extends StatefulWidget {
  const DashboardSkeleton({super.key});

  @override
  State<DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Color(0xFFD6D6D6),
                Color(0xFFF0F0F0),
                Color(0xFFD6D6D6),
              ],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value.clamp(0.0, 1.0),
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ].map((s) => s.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: child!,
        );
      },
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildGreetingSkeleton(),
          _buildSectionLabelSkeleton(),
          _buildGaugeGridSkeleton(),
          _buildSectionLabelSkeleton(),
          _buildWaterLevelGaugeSkeleton(),
          const SizedBox(height: 12),
          _buildQuickActionsSkeleton(),
          _buildSectionLabelSkeleton(),
          _buildTankStatusSkeleton(),
          _buildSectionLabelSkeleton(),
          _buildFeedingScheduleSkeleton(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static const _baseColor = Color(0xFFEEEEEE);
  static const _cornerRadius = 16.0;

  Widget _shimmerContainer({
    double? width,
    double? height,
    double borderRadius = 12,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: _baseColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  Widget _buildGreetingSkeleton() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 23, 20, 23),
      decoration: BoxDecoration(
        color: _baseColor,
        borderRadius: BorderRadius.circular(_cornerRadius),
      ),
      child: Row(
        children: [
          _shimmerContainer(width: 3, height: 50, borderRadius: 2),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _shimmerContainer(width: 180, height: 14, borderRadius: 4),
                const SizedBox(height: 7),
                _shimmerContainer(width: 140, height: 10, borderRadius: 4),
                const SizedBox(height: 6),
                _shimmerContainer(width: 200, height: 10, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabelSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          _shimmerContainer(width: 16, height: 16, borderRadius: 8),
          const SizedBox(width: 8),
          _shimmerContainer(width: 160, height: 13, borderRadius: 4),
        ],
      ),
    );
  }

  Widget _buildGaugeCardSkeleton() {
    return Container(
      decoration: BoxDecoration(
        color: _baseColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                _shimmerContainer(width: 32, height: 32, borderRadius: 10),
                const SizedBox(width: 10),
                Expanded(child: _shimmerContainer(height: 11, borderRadius: 4)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _shimmerContainer(width: 60, height: 26, borderRadius: 6),
                const SizedBox(width: 3),
                _shimmerContainer(width: 24, height: 13, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _shimmerContainer(width: 70, height: 10, borderRadius: 4),
          const SizedBox(height: 6),
          _shimmerContainer(
            width: 80,
            height: 22,
            borderRadius: 20,
          ),
          const SizedBox(height: 8),
          _shimmerContainer(
            width: 100,
            height: 14,
            borderRadius: 4,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildGaugeGridSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildGaugeCardSkeleton()),
              const SizedBox(width: 12),
              Expanded(child: _buildGaugeCardSkeleton()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildGaugeCardSkeleton()),
              const SizedBox(width: 12),
              Expanded(child: _buildGaugeCardSkeleton()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWaterLevelGaugeSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _buildGaugeCardSkeleton(),
    );
  }

  Widget _buildQuickActionsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(
            children: [
              _shimmerContainer(width: 16, height: 16, borderRadius: 8),
              const SizedBox(width: 8),
              _shimmerContainer(width: 120, height: 13, borderRadius: 4),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: List.generate(
              5,
              (i) => Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _baseColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _shimmerContainer(width: 28, height: 28, borderRadius: 14),
                    const SizedBox(width: 10),
                    _shimmerContainer(width: 60, height: 11, borderRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTankStatusSkeleton() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _baseColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _shimmerContainer(width: 18, height: 18, borderRadius: 9),
              const SizedBox(width: 10),
              _shimmerContainer(width: 100, height: 13, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: Column(
                  children: [
                    _shimmerContainer(width: 32, height: 32, borderRadius: 10),
                    const SizedBox(height: 6),
                    _shimmerContainer(width: 40, height: 16, borderRadius: 4),
                    const SizedBox(height: 4),
                    _shimmerContainer(width: 50, height: 8, borderRadius: 4),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shimmerContainer(width: 120, height: 11, borderRadius: 4),
              _shimmerContainer(width: 60, height: 11, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _shimmerContainer(width: 100, height: 11, borderRadius: 4),
                  _shimmerContainer(width: 60, height: 11, borderRadius: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedingScheduleSkeleton() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _baseColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _shimmerContainer(width: 18, height: 18, borderRadius: 9),
              const SizedBox(width: 6),
              _shimmerContainer(width: 120, height: 13, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _shimmerContainer(width: 20, height: 20, borderRadius: 4),
                    const SizedBox(height: 6),
                    _shimmerContainer(width: 50, height: 9, borderRadius: 4),
                    const SizedBox(height: 4),
                    _shimmerContainer(width: 40, height: 16, borderRadius: 4),
                    const SizedBox(height: 2),
                    _shimmerContainer(width: 30, height: 10, borderRadius: 4),
                  ],
                ),
              ),
              _shimmerContainer(width: 1, height: 60, borderRadius: 0),
              Expanded(
                child: Column(
                  children: [
                    _shimmerContainer(width: 20, height: 20, borderRadius: 4),
                    const SizedBox(height: 6),
                    _shimmerContainer(width: 60, height: 9, borderRadius: 4),
                    const SizedBox(height: 4),
                    _shimmerContainer(width: 40, height: 16, borderRadius: 4),
                    const SizedBox(height: 2),
                    _shimmerContainer(width: 40, height: 10, borderRadius: 4),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _shimmerContainer(height: 8, borderRadius: 6),
          const SizedBox(height: 8),
          _shimmerContainer(width: 140, height: 10, borderRadius: 4),
        ],
      ),
    );
  }
}
