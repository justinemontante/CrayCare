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
      ('LIVE', 'live', Icons.sensors),
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
          final isActive = f.$2 == 'custom' ? widget.showCustom : widget.activeFilter == f.$2;
          final color = isActive ? AppColors.primary : AppColors.darkWith(0.45);
          
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (f.$2 == 'custom') {
                  widget.onToggleCustom();
                } else {
                  widget.onFilterChanged(f.$2);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.primaryWith(0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(f.$3, size: 11, color: color),
                    const SizedBox(width: 4),
                    Text(
                      f.$1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
