import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF1FA5A5);
  static const Color dark = Color(0xFF0B3C49);

  // Status
  static const Color success = Color(0xFF2d9f2d);
  static const Color successLight = Color(0xFF16a34a);
  static const Color warning = Color(0xFFf59e0b);
  static const Color warningDark = Color(0xFFd97706);
  static const Color critical = Color(0xFFE63946);
  static const Color criticalDark = Color(0xFFdc2626);

  // Neutrals
  static const Color white = Colors.white;
  static const Color darkText = Color(0xFF0B3C49);
  static const Color subtitleText = Color(0xFF64748b);
  static const Color mutedText = Color(0xFF94a3b8);
  static Color get faintBorder => const Color(0xFF0B3C49).withValues(alpha: 0.08);
  static Color get lightBg => const Color(0xFF0B3C49).withValues(alpha: 0.04);

  // Gradient
  static const Color gradientStart = Color(0xFF0B3C49);
  static const Color gradientEnd = Color(0xFF1FA5A5);
  static const List<Color> primaryGradient = [gradientStart, gradientEnd];
  static const Color gradientStartDark = Color(0xFF09404d);
  static const Color gradientEndDark = Color(0xFF167a7a);
  static const List<Color> primaryGradientDark = [gradientStartDark, gradientEndDark];

  // Header gradient
  static const Color headerStart = Color(0xFF1FA5A5); // Represents rgba(31, 165, 165, 1)
  static const Color headerEnd = Color(0xFF52C283); // Represents rgba(82, 194, 131, 1)
  static const List<Color> headerGradient = [
    Color(0x0F1FA5A5), // 0.06 opacity
    Color(0x0A52C283), // 0.04 opacity
  ];

  // Opacity helpers
  static Color primaryWith(double opacity) => primary.withValues(alpha: opacity);
  static Color darkWith(double opacity) => dark.withValues(alpha: opacity);
  static Color successWith(double opacity) => success.withValues(alpha: opacity);
  static Color warningWith(double opacity) => warning.withValues(alpha: opacity);
  static Color criticalWith(double opacity) => critical.withValues(alpha: opacity);
  static Color whiteWith(double opacity) => white.withValues(alpha: opacity);
}
