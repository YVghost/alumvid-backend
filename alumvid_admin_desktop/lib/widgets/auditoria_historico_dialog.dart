import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/despacho.dart';
import '../models/ruta.dart';
import '../theme/app_theme.dart';
import 'epod_dialog.dart';

class AuditoriaHistoricoDialog extends StatefulWidget {
  final List<Ruta> todasLasRutas;
  final DateTimeRange rangoInicial;
  final Function(DateTimeRange nuevoRango) onRangoCambiado;
  final Function(Ruta ruta)? onVerEnMapa;

  const AuditoriaHistoricoDialog({
    super.key,
    required this.todasLasRutas,
    required this.rangoInicial,
    required this.onRangoCambiado,
    this.onVerEnMapa,
  });

  @override
  State<AuditoriaHistoricoDialog> createState() => _AuditoriaHistoricoDialogState();
}

class _AuditoriaHistoricoDialogState extends State<AuditoriaHistoricoDialog> {
  late DateTimeRange _rango;
  bool _ordenAscendente = false; // Por defecto: más recientes primero
  String _filtroTexto = '';
  final Set<String> _rutasExpandidas = {};

  @override
  void initState() {
    super.initState();
    _rango = widget.rangoInicial;
  }

  bool _estaEnRango(DateTime? dt, DateTimeRange range) {
    if (dt == null) return false;
    final start = DateTime(range.start.year, range.start.month, range.start.day, 0, 0, 0);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    return dt.isAfter(start.subtract(const Duration(seconds: 1))) &&
        dt.isBefore(end.add(const Duration(seconds: 1)));
  }

  List<Ruta> _obtenerRutasFiltradas() {
    final list = widget.todasLasRutas.where((r) {
      final bool enFecha = _estaEnRango(r.fechaCreacion, _rango);
      if (!enFecha) return false;

      if (_filtroTexto.trim().isEmpty) return true;
      final q = _filtroTexto.toLowerCase();
      final matchCodigo = r.codigoRuta.toLowerCase().contains(q);
      final matchChofer = (r.choferNombre ?? '').toLowerCase().contains(q);
      final matchParada = r.paradas.any((p) =>
          (p.pedido?.cliente ?? '').toLowerCase().contains(q) ||
          (p.pedido?.direccionTexto ?? '').toLowerCase().contains(q));
      return matchCodigo || matchChofer || matchParada;
    }).toList();

    list.sort((a, b) {
      final fa = a.fechaCreacion ?? DateTime.fromMillisecondsSinceEpoch(0);
      final fb = b.fechaCreacion ?? DateTime.fromMillisecondsSinceEpoch(0);
      return _ordenAscendente ? fa.compareTo(fb) : fb.compareTo(fa);
    });

    return list;
  }

  Future<void> _abrirSelectorRango() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _rango,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: AppTheme.surface,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _rango = picked);
      widget.onRangoCambiado(picked);
    }
  }

  String _formatearRango(DateTimeRange r) {
    final f = DateFormat('dd MMM yyyy');
    if (r.start.year == r.end.year && r.start.month == r.end.month && r.start.day == r.end.day) {
      return f.format(r.start);
    }
    return '${DateFormat('dd MMM').format(r.start)} - ${f.format(r.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final rutasFiltradas = _obtenerRutasFiltradas();

    // Cálculos de métricas para el periodo seleccionado
    final int totalRutas = rutasFiltradas.length;
    int totalParadas = 0;
    int totalEntregadas = 0;
    int totalEnCurso = 0;
    int totalCanceladas = 0;
    final Set<String> choferesSet = {};

    for (final r in rutasFiltradas) {
      totalParadas += r.paradas.length;
      if (r.choferNombre != null && r.choferNombre!.isNotEmpty) {
        choferesSet.add(r.choferNombre!);
      }
      for (final p in r.paradas) {
        if (p.isEntregado) {
          totalEntregadas++;
        } else if (p.isEnCurso) {
          totalEnCurso++;
        } else if (p.estado == 'CANCELADA' || p.estado == 'CANCELADO' || r.estado == 'CANCELADA') {
          totalCanceladas++;
        }
      }
    }

    return Dialog(
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Container(
        width: 960,
        height: 720,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera del Diálogo
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.history_edu, color: AppTheme.primaryLight, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auditoría e Histórico de Rutas y Despachos',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          'Desglose cronológico detallado de hojas de ruta, choferes y paradas asignadas',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: AppTheme.border, height: 24),

            // Barra de Filtro de Rango de Fechas y Búsqueda
            Row(
              children: [
                // Selector de Rango de Fechas
                InkWell(
                  onTap: _abrirSelectorRango,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month, size: 16, color: AppTheme.primaryLight),
                        const SizedBox(width: 8),
                        Text(
                          'Periodo: ${_formatearRango(_rango)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit_calendar, size: 14, color: AppTheme.textMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Buscador por Texto
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => _filtroTexto = val),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Buscar por código de ruta, chofer o cliente...',
                      hintStyle: const TextStyle(color: AppTheme.textDim, fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 16, color: AppTheme.textMuted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.surfaceCard,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Botón de Orden Cronológico
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  icon: Icon(_ordenAscendente ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: AppTheme.primaryLight),
                  label: Text(
                    _ordenAscendente ? 'Más antiguas 1°' : 'Más recientes 1°',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  onPressed: () => setState(() => _ordenAscendente = !_ordenAscendente),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Fila de Métricas del Periodo Seleccionado
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricStat('Rutas Totales', '$totalRutas', AppTheme.primaryLight, Icons.alt_route),
                  _buildMetricDivider(),
                  _buildMetricStat('Paradas Totales', '$totalParadas', Colors.white, Icons.pin_drop),
                  _buildMetricDivider(),
                  _buildMetricStat('Entregas Exitosas', '$totalEntregadas', AppTheme.statusCompletada, Icons.check_circle),
                  _buildMetricDivider(),
                  _buildMetricStat('En Curso', '$totalEnCurso', AppTheme.statusEnCurso, Icons.local_shipping),
                  _buildMetricDivider(),
                  _buildMetricStat('Canceladas', '$totalCanceladas', AppTheme.statusCancelada, Icons.cancel),
                  _buildMetricDivider(),
                  _buildMetricStat('Choferes Activos', '${choferesSet.length}', const Color(0xFF38BDF8), Icons.people),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Lista Cronológica de Hojas de Ruta
            Expanded(
              child: rutasFiltradas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.event_busy, size: 48, color: AppTheme.textDim),
                          const SizedBox(height: 10),
                          Text(
                            'No se encontraron rutas para el periodo ${_formatearRango(_rango)}.',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Intente ampliando el rango de fechas con el selector superior.',
                            style: TextStyle(color: AppTheme.textDim, fontSize: 11),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: rutasFiltradas.length,
                      itemBuilder: (context, index) {
                        final r = rutasFiltradas[index];
                        final isExpanded = _rutasExpandidas.contains(r.id);
                        return _buildRutaAuditCard(r, isExpanded);
                      },
                    ),
            ),

            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mostrando ${rutasFiltradas.length} hojas de ruta en orden cronológico.',
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.surfaceCard,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar Auditoría', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricStat(String label, String value, Color color, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: color)),
            Text(label, style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricDivider() {
    return Container(width: 1, height: 26, color: AppTheme.border);
  }

  Widget _buildRutaAuditCard(Ruta r, bool isExpanded) {
    Color tagColor = AppTheme.statusPendiente;
    if (r.isEnCurso) tagColor = AppTheme.statusEnCurso;
    if (r.isCompletada) tagColor = AppTheme.statusCompletada;
    if (r.estado == 'CANCELADA' || r.estado == 'CANCELADO') tagColor = AppTheme.statusCancelada;

    final fechaStr = r.fechaCreacion != null
        ? DateFormat('dd MMM yyyy, HH:mm').format(r.fechaCreacion!)
        : 'Fecha no registrada';

    final int entregadas = r.paradasEntregadas;
    final int total = r.totalParadas;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isExpanded ? AppTheme.primaryLight : AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera de la Ruta
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _rutasExpandidas.remove(r.id);
                } else {
                  _rutasExpandidas.add(r.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tagColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tagColor.withValues(alpha: 0.4)),
                    ),
                    child: Icon(Icons.alt_route, color: tagColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              r.codigoRuta,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: tagColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: tagColor),
                              ),
                              child: Text(r.estado, style: TextStyle(color: tagColor, fontSize: 9.5, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.schedule, size: 12, color: AppTheme.textDim),
                            const SizedBox(width: 4),
                            Text(fechaStr, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                            const SizedBox(width: 14),
                            const Icon(Icons.person, size: 12, color: AppTheme.textDim),
                            const SizedBox(width: 4),
                            Text(
                              r.choferNombre != null && r.choferNombre!.isNotEmpty ? r.choferNombre! : 'Sin chofer asignado',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Avance y Acciones
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$entregadas / $total paradas (${(r.porcentajeAvance * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: total == 0 ? 0 : (entregadas / total),
                            backgroundColor: const Color(0xFF0F172A),
                            color: tagColor,
                            minHeight: 4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Desglose de Paradas al expandirse
          if (isExpanded) ...[
            const Divider(color: AppTheme.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Desglose Cronológico de Paradas (${r.paradas.length}):',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryLight),
                      ),
                      if (widget.onVerEnMapa != null)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.radar, size: 13),
                          label: const Text('Ver en Monitoreo en Vivo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onVerEnMapa!(r);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (r.paradas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Esta ruta no registró paradas.', style: TextStyle(fontSize: 11, color: AppTheme.textDim)),
                    )
                  else
                    ...r.paradas.map((p) => _buildParadaAuditItem(p)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParadaAuditItem(Despacho p) {
    Color col = AppTheme.statusPendiente;
    String txt = 'Pendiente';

    if (p.isEntregado) {
      col = AppTheme.statusCompletada;
      txt = 'Entregado';
    } else if (p.isEnCurso) {
      col = AppTheme.statusEnCurso;
      txt = 'En curso';
    } else if (p.estado == 'CANCELADA' || p.estado == 'CANCELADO') {
      col = AppTheme.statusCancelada;
      txt = 'Cancelado';
    }

    final horaEntregaStr = p.fechaEntrega != null
        ? DateFormat('HH:mm').format(p.fechaEntrega!)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('#${p.ordenParada}', style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 10.5)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      p.pedido?.cliente ?? 'Cliente no registrado',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                    ),
                    if (horaEntregaStr != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '• Entregado a las $horaEntregaStr',
                        style: const TextStyle(fontSize: 10, color: AppTheme.statusCompletada, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  p.pedido?.direccionTexto ?? 'Sin dirección',
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (p.comentarios != null && p.comentarios!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Entregado: ${p.comentarios}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.primaryLight, fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: col.withValues(alpha: 0.4)),
            ),
            child: Text(txt, style: TextStyle(color: col, fontSize: 9.5, fontWeight: FontWeight.bold)),
          ),
          if (p.isEntregado) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => EpodDialog(despacho: p),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.statusCompletada.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attachment, size: 10, color: AppTheme.statusCompletada),
                    SizedBox(width: 2),
                    Text('e-PoD', style: TextStyle(color: AppTheme.statusCompletada, fontSize: 9, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
