import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SectionLabel extends StatefulWidget {
  final String label;
  final bool showLiveData;
  final String liveLabel;
  final IconData? icon;
  final double topPadding;

  const SectionLabel({
    super.key,
    required this.label,
    this.showLiveData = false,
    this.liveLabel = 'Live Data',
    this.icon,
    this.topPadding = 12,
  });

  @override
  State<SectionLabel> createState() => _SectionLabelState();
}

class _SectionLabelState extends State<SectionLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _liveController;
  late final Animation<double> _livePulse;

  @override
  void initState() {
    super.initState();
    _liveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _livePulse = CurvedAnimation(
      parent: _liveController,
      curve: Curves.easeInOut,
    );
    if (widget.showLiveData) _liveController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SectionLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showLiveData && !oldWidget.showLiveData) {
      _liveController.repeat(reverse: true);
    } else if (!widget.showLiveData && oldWidget.showLiveData) {
      _liveController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _liveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, widget.topPadding, 14, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (widget.showLiveData)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _livePulse,
                  builder: (context, child) {
                    final progress = _livePulse.value;
                    return SizedBox(
                      width: 12,
                      height: 12,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.scale(
                            scale: 0.75 + (progress * 0.65),
                            child: Opacity(
                              opacity: 0.32 * (1 - progress),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xFF22c55e),
                                  shape: BoxShape.circle,
                                ),
                                child: SizedBox.expand(),
                              ),
                            ),
                          ),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22c55e),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 5),
                FadeTransition(
                  opacity: Tween<double>(
                    begin: 0.78,
                    end: 1,
                  ).animate(_livePulse),
                  child: Text(
                    widget.liveLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
