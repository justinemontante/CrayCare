import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GradientButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final double borderRadius;
  final double verticalPadding;
  final double? width;
  final List<Color>? gradient;
  final List<BoxShadow>? boxShadow;

  const GradientButton({
    super.key,
    this.onTap,
    required this.child,
    this.borderRadius = 14,
    this.verticalPadding = 12,
    this.width,
    this.gradient,
    this.boxShadow,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width ?? double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _pressed
                    ? (widget.gradient != null
                        ? widget.gradient!.reversed.toList()
                        : AppColors.primaryGradientDark)
                    : (widget.gradient ?? AppColors.primaryGradient),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: widget.boxShadow ?? [
                BoxShadow(
                  color: AppColors.darkWith(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(vertical: widget.verticalPadding),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
