import 'package:flutter/material.dart';

/// Keeps field controllers alive until the route's closing animation and
/// overlay removal finish, rather than just until Navigator.pop returns.
Future<T?> showThresholdEditorDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required List<TextEditingController> controllers,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    animationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 220),
      reverseDuration: Duration(milliseconds: 180),
    ),
    builder: builder,
  );
  try {
    final result = await navigator.push<T>(route);
    await route.completed;
    return result;
  } finally {
    for (final controller in controllers) {
      controller.dispose();
    }
  }
}
