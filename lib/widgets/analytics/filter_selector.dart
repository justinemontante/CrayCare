import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class FilterSelector extends StatefulWidget {
  final String activeFilter;
  final bool showCustom;
  final Function(String) onFilterChanged;
  final VoidCallback onToggleCustom;

  const FilterSelector({
    super.key,
    required this.activeFilter,
    required this.showCustom,
    required this.onFilterChanged,
    required this.onToggleCustom,
  });

  @override
  State<FilterSelector> createState() => _FilterSelectorState();
}

class _FilterSelectorState extends State<FilterSelector> {

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('Live', 'live', Icons.wifi_tethering),
      ('24H', '24h', Icons.history),
      ('7D', '7d', Icons.date_range),
      ('30D', '30d', Icons.calendar_month),
      ('Custom', 'custom', Icons.tune),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: filters.map((f) {
          final isActive = widget.showCustom
              ? f.$2 == 'custom'
              : widget.activeFilter == f.$2;
          const animationDuration = Duration.zero;

          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () {
                  if (f.$2 == 'custom') {
                    widget.onToggleCustom();
                  } else {
                    widget.onFilterChanged(f.$2);
                  }
                },
                child: AnimatedContainer(
                  duration: animationDuration,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppColors.primaryWith(0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder<Color?>(
                        tween: ColorTween(
                          end: isActive
                              ? AppColors.primary
                              : AppColors.darkWith(0.45),
                        ),
                        duration: animationDuration,
                        builder: (context, color, _) =>
                            Icon(f.$3, size: 12, color: color),
                      ),
                      const SizedBox(width: 5),
                      AnimatedDefaultTextStyle(
                        duration: animationDuration,
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.darkWith(0.45),
                        ),
                        child: Text(f.$1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
