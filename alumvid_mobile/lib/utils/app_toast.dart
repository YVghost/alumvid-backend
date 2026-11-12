import 'package:flutter/material.dart';

class AppToast {
  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      icon: Icons.check_circle_outline_rounded,
      iconColor: const Color(0xFF10B981),
      borderColor: const Color(0xFF059669).withValues(alpha: 0.5),
    );
  }

  static void error(BuildContext context, String message) {
    _show(
      context,
      message,
      icon: Icons.error_outline_rounded,
      iconColor: const Color(0xFFEF4444),
      borderColor: const Color(0xFFDC2626).withValues(alpha: 0.5),
    );
  }

  static void info(BuildContext context, String message) {
    _show(
      context,
      message,
      icon: Icons.info_outline_rounded,
      iconColor: const Color(0xFF38BDF8),
      borderColor: const Color(0xFF0284C7).withValues(alpha: 0.5),
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
