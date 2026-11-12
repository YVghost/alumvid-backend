import 'package:flutter/material.dart';

import 'tema.dart';

/// Ancho a partir del cual se usa el diseño de escritorio.
const double anchoEscritorio = 900;

bool esEscritorio(BuildContext context) => MediaQuery.sizeOf(context).width >= anchoEscritorio;

/// Abre una pantalla de detalle o formulario:
/// en teléfono como página completa; en escritorio como panel lateral derecho.
/// En ambos casos `Navigator.pop(context, resultado)` la cierra y devuelve el resultado.
Future<T?> abrirPanel<T>(BuildContext context, WidgetBuilder builder, {double ancho = 600}) {
  if (!esEscritorio(context)) {
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: builder));
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Theme(
        data: TemaAlumVid.oscuro,
        child: Material(
          color: AppColors.background,
          elevation: 12,
          child: SizedBox(width: ancho, height: double.infinity, child: builder(ctx)),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Envuelve un módulo con el tema común (lo usa el escritorio, que tiene su propio tema).
class ConTemaAlumVid extends StatelessWidget {
  const ConTemaAlumVid({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(data: TemaAlumVid.oscuro, child: child);
}

/// Contenido centrado con ancho máximo legible en pantallas grandes.
class AnchoLegible extends StatelessWidget {
  const AnchoLegible({super.key, required this.child, this.max = 1100});
  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
  );
}
