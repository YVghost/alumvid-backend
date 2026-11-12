import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AppToastType {
  success,
  error,
  info,
  warning,
}

/// Sistema de alertas discretas flotantes para AlumVid Desktop.
/// Se posiciona en la zona inferior izquierda de la pantalla, sin estorbar
/// ni abarcar todo el ancho, adaptándose al contenido exacto del mensaje.
class AppToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        message: message,
        type: type,
        onDismiss: () {
          _dismissTimer?.cancel();
          if (_currentEntry == entry) {
            entry.remove();
            _currentEntry = null;
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      if (_currentEntry == entry) {
        entry.remove();
        _currentEntry = null;
      }
    });
  }

  static void success(BuildContext context, String message) =>
      show(context, message, type: AppToastType.success);

  static void error(BuildContext context, String message) =>
      show(context, message, type: AppToastType.error, duration: const Duration(seconds: 5));

  static void info(BuildContext context, String message) =>
      show(context, message, type: AppToastType.info);

  static void warning(BuildContext context, String message) =>
      show(context, message, type: AppToastType.warning);
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final AppToastType type;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(-0.08, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.type) {
      case AppToastType.success:
        return AppTheme.statusCompletada;
      case AppToastType.error:
        return AppTheme.statusAlerta;
      case AppToastType.warning:
        return AppTheme.statusEnCurso;
      case AppToastType.info:
        return AppTheme.primaryLight;
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case AppToastType.success:
        return Icons.check_circle_rounded;
      case AppToastType.error:
        return Icons.error_outline_rounded;
      case AppToastType.warning:
        return Icons.warning_amber_rounded;
      case AppToastType.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // Zona inferior izquierda, con separación estética de los bordes
      bottom: 28,
      left: 28,
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 460,
                minWidth: 160,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF20F172A), // Slate oscuro elegante
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _accentColor.withValues(alpha: 0.65),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_icon, color: _accentColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Color(0xFFF1F5F9),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _animController.reverse().then((_) => widget.onDismiss());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(3.0),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
