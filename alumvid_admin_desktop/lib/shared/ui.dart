import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tema.dart';

// ---------------------------------------------------------------------------
// Formato
// ---------------------------------------------------------------------------

final _num = NumberFormat.decimalPatternDigits(locale: 'es', decimalDigits: 2);
final _dinero = NumberFormat.currency(locale: 'es', symbol: r'$', decimalDigits: 2);
final _fecha = DateFormat('dd/MM/yyyy HH:mm');
final _fechaCorta = DateFormat('dd MMM', 'es');

String fmtNum(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : _num.format(v);
String fmtDinero(num v) => _dinero.format(v);
String fmtFecha(DateTime? d) => d == null ? '—' : _fecha.format(d.toLocal());
String fmtFechaCorta(DateTime? d) {
  if (d == null) return '—';
  try {
    return _fechaCorta.format(d.toLocal());
  } catch (_) {
    return DateFormat('dd/MM').format(d.toLocal());
  }
}

/// Conversores tolerantes para datos JSON del backend (números como texto, fechas ISO).
double aNum(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double? aNumONulo(dynamic v) => v == null ? null : v is num ? v.toDouble() : double.tryParse('$v');
DateTime? aFecha(dynamic v) => v == null ? null : DateTime.tryParse('$v');
String aTexto(dynamic v, [String vacio = '']) => v == null || '$v'.trim().isEmpty ? vacio : '$v';

/// Medidas de una pieza o línea: "3,2 m" o "40 × 244 cm".
String medidas(dynamic largoM, dynamic anchoCm, dynamic altoCm) {
  final l = aNumONulo(largoM), w = aNumONulo(anchoCm), h = aNumONulo(altoCm);
  if (l != null && l > 0) return '${fmtNum(l)} m';
  if (w != null && h != null) return '${fmtNum(w)} × ${fmtNum(h)} cm';
  return '';
}

String limpiarError(Object e) => e
    .toString()
    .replaceAll('ApiError: ', '')
    .replaceAll('Exception: ', '')
    .replaceAll('Consulta no disponible: ', '');

String humanizar(String s) {
  if (s.isEmpty) return s;
  final t = s.replaceAll('_', ' ').toLowerCase();
  return t[0].toUpperCase() + t.substring(1);
}

// ---------------------------------------------------------------------------
// Estados (mismo significado de colores que el administrador)
// ---------------------------------------------------------------------------

Color colorEstado(String estado) {
  switch (estado.toUpperCase()) {
    case 'ENTREGADO':
    case 'COMPLETADA':
    case 'LISTO':
    case 'DISPONIBLE':
    case 'ACTIVO':
      return AppColors.success;
    case 'EN_CURSO':
    case 'EN_REPARTO':
    case 'EN_RUTA':
    case 'PREPARADO':
      return AppColors.warning;
    case 'PENDIENTE':
    case 'RESERVADO':
    case 'BORRADOR':
      return AppColors.info;
    case 'PARCIAL':
    case 'TRANSFORMADO':
      return AppColors.violet;
    case 'RETRASADO':
    case 'PENDIENTE_MATERIAL':
    case 'NO_ENTREGADO':
    case 'AGOTADO':
      return AppColors.danger;
    case 'CANCELADA':
    case 'CANCELADO':
    case 'VENCIDO':
    case 'CONSUMIDO':
    case 'DESCARTADO':
    case 'INACTIVO':
    default:
      return AppColors.neutral;
  }
}

class EstadoChip extends StatelessWidget {
  const EstadoChip(this.estado, {super.key, this.texto, this.color});
  final String estado;
  final String? texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? colorEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        texto ?? humanizar(estado),
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estados de pantalla: carga, vacío, error
// ---------------------------------------------------------------------------

class CargandoLista extends StatelessWidget {
  const CargandoLista({super.key, this.items = 6});
  final int items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: items,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Container(
        height: 76,
        decoration: BoxDecoration(
          color: AppColors.card.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class VistaVacia extends StatelessWidget {
  const VistaVacia({
    super.key,
    required this.icono,
    required this.titulo,
    this.mensaje,
    this.accion,
  });
  final IconData icono;
  final String titulo;
  final String? mensaje;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icono, size: 36, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (mensaje != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      mensaje!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                  if (accion != null) ...[const SizedBox(height: 20), accion!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VistaError extends StatelessWidget {
  const VistaError({super.key, required this.mensaje, required this.onReintentar});
  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return VistaVacia(
      icono: Icons.cloud_off_rounded,
      titulo: 'No se pudo cargar la información',
      mensaje: mensaje,
      accion: FilledButton.icon(
        onPressed: onReintentar,
        icon: const Icon(Icons.refresh),
        label: const Text('Reintentar'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bloques reutilizables
// ---------------------------------------------------------------------------

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.titulo,
    required this.valor,
    required this.icono,
    this.color = AppColors.primaryLight,
    this.onTap,
  });
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icono, color: color, size: 20),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textDim,
                      size: 20,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SeccionTitulo extends StatelessWidget {
  const SeccionTitulo(this.texto, {super.key, this.accion});
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              texto.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?accion,
        ],
      ),
    );
  }
}

/// Fila "etiqueta: valor" para fichas de detalle.
class DatoFila extends StatelessWidget {
  const DatoFila(this.etiqueta, this.valor, {super.key, this.icono});
  final String etiqueta;
  final String valor;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 112,
            child: Text(
              etiqueta,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              valor.isEmpty ? '—' : valor,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo de búsqueda con espera de 350 ms para no saturar el backend.
class CampoBusqueda extends StatefulWidget {
  const CampoBusqueda({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<CampoBusqueda> createState() => _CampoBusquedaState();
}

class _CampoBusquedaState extends State<CampoBusqueda> {
  final _ctrl = TextEditingController();
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _cambio(String v) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), () => widget.onChanged(v.trim()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: _cambio,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _ctrl.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _ctrl.clear();
                  _cambio('');
                },
              ),
      ),
    );
  }
}

/// Fila horizontal de filtros (chips) con selección única.
class FiltrosChips<T> extends StatelessWidget {
  const FiltrosChips({
    super.key,
    required this.opciones,
    required this.seleccion,
    required this.onSeleccion,
  });
  final Map<T, String> opciones;
  final T seleccion;
  final ValueChanged<T> onSeleccion;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final e in opciones.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: e.key == seleccion,
                showCheckmark: false,
                onSelected: (_) => onSeleccion(e.key),
              ),
            ),
        ],
      ),
    );
  }
}

class AvatarIniciales extends StatelessWidget {
  const AvatarIniciales(this.nombre, {super.key, this.radio = 20, this.color});
  final String nombre;
  final double radio;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final ini = partes.take(2).map((p) => p[0].toUpperCase()).join();
    final c = color ?? AppColors.primary;
    return CircleAvatar(
      radius: radio,
      backgroundColor: c.withValues(alpha: 0.22),
      child: Text(
        ini.isEmpty ? '?' : ini,
        style: TextStyle(
          color: c == AppColors.primary ? AppColors.primaryLight : c,
          fontWeight: FontWeight.w800,
          fontSize: radio * 0.75,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogos y avisos
// ---------------------------------------------------------------------------

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String accion = 'Confirmar',
  bool peligro = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje, style: const TextStyle(color: AppColors.textMuted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: peligro
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return r == true;
}

/// Pide un texto obligatorio (p. ej. el motivo de una cancelación).
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  String accion = 'Aceptar',
  bool peligro = false,
}) async {
  final ctrl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          onChanged: (_) => setS(() {}),
          decoration: InputDecoration(labelText: etiqueta),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: peligro
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                : null,
            onPressed: ctrl.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(accion),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return r;
}

void avisoOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    );
}

void avisoError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(limpiarError(e))),
          ],
        ),
      ),
    );
}

Future<void> llamar(String telefono) =>
    launchUrl(Uri(scheme: 'tel', path: telefono));
