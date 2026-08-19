import 'package:flutter/material.dart';

/// Keeps the destination fully opaque while it gently covers the splash.
/// This avoids the washed-out flash caused by fading two full-screen pages.
Route<T> splashExitPageRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final position = Tween<Offset>(
        begin: const Offset(0, 0.035),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

      return SlideTransition(position: position, child: child);
    },
  );
}

/// A restrained fade-and-scale transition for top-level app navigation.
Route<T> smoothPageRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curvedAnimation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.992, end: 1).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}
