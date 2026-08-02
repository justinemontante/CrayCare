import 'package:flutter/material.dart';

void showBeautifulSnackbar(
  BuildContext context,
  String message,
  bool isSuccess, {
  String? title,
}) {
  _showSnack(ScaffoldMessenger.of(context), message, isSuccess, title: title);
}

/// Same as [showBeautifulSnackbar] but uses an already-captured
/// [ScaffoldMessengerState]. Use this AFTER `Navigator.pop(context)` when the
/// original context is no longer valid (e.g. forms inside bottom sheets).
void showBeautifulSnackbarWithMessenger(
  ScaffoldMessengerState messenger,
  String message,
  bool isSuccess, {
  String? title,
}) {
  _showSnack(messenger, message, isSuccess, title: title);
}

void _showSnack(
  ScaffoldMessengerState messenger,
  String message,
  bool isSuccess, {
  String? title,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSuccess
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title ?? (isSuccess ? 'Success' : 'Error'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                Text(
                  message,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => messenger.hideCurrentSnackBar(),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: isSuccess
          ? const Color(0xFF059669)
          : const Color(0xFFDC2626),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 12,
      duration: const Duration(seconds: 3),
    ),
  );
}
