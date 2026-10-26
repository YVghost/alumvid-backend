import 'package:flutter/material.dart';
import '../models/despacho.dart';
import '../models/ruta.dart';
import '../theme/app_theme.dart';
import '../widgets/epod_dialog.dart';

class KanbanView extends StatefulWidget {
  final List<Ruta> rutas;
  final VoidCallback onRefresh;
  final Function(Ruta)? onVerEnMapa;

  const KanbanView({
    super.key,
    required this.rutas,
    required this.onRefresh,
    this.onVerEnMapa,
  });

  @override
  State<KanbanView> createState() => _KanbanViewState();
}

class _KanbanViewState extends State<KanbanView> {
  // IDs de las rutas que se encuentran desplegadas por el usuario
  final Set<String> _rutasExpandidas = {};

  void _toggleRuta(String id) {
    setState(() {
      if (_rutasExpandidas.contains(id)) {
        _rutasExpandidas.remove(id);
      } else {
        _rutasExpandidas.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Clasificar las Hojas de Ruta en las 4 columnas operativas
    final List<Ruta> pendientes = [];
    final List<Ruta> enCurso = [];
    final List<Ruta> completadas = [];
    final List<Ruta> canceladas = [];

    for (final r in widget.rutas) {
      if (r.estado == 'CANCELADA' || r.estado == 'CANCELADO') {
        canceladas.add(r);
      } else if (r.isCompletada || (r.paradas.isNotEmpty && r.paradas.every((p) => p.isEntregado))) {
        completadas.add(r);
      } else if (r.isEnCurso || r.paradas.any((p) => p.isEnCurso)) {
        enCurso.add(r);
      } else {
        pendientes.add(r);
      }
    }

    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tablero Despachos',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    'Control y seguimiento operativo de rutas por estado de avance',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_rutasExpandidas.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.unfold_less, size: 16, color: AppTheme.textMuted),
                      label: const Text('Colapsar todas', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      onPressed: () => setState(() => _rutasExpandidas.clear()),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppTheme.primaryLight),
                    tooltip: 'Actualizar Tablero',
                    onPressed: widget.onRefresh,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4 Columnas del Tablero Despachos
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildColumn('Pendientes', pendientes, AppTheme.statusPendiente, Icons.schedule)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildColumn('En Curso', enCurso, AppTheme.statusEnCurso, Icons.local_shipping)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildColumn('Completadas', completadas, AppTheme.statusCompletada, Icons.verified)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildColumn('Canceladas', canceladas, AppTheme.statusCancelada, Icons.cancel)),
                    ],
                  );
                } else {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 290, child: _buildColumn('Pendientes', pendientes, AppTheme.statusPendiente, Icons.schedule)),
                        const SizedBox(width: 12),
                        SizedBox(width: 290, child: _buildColumn('En Curso', enCurso, AppTheme.statusEnCurso, Icons.local_shipping)),
                        const SizedBox(width: 12),
                        SizedBox(width: 290, child: _buildColumn('Completadas', completadas, AppTheme.statusCompletada, Icons.verified)),
                        const SizedBox(width: 12),
                        SizedBox(width: 290, child: _buildColumn('Canceladas', canceladas, AppTheme.statusCancelada, Icons.cancel)),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(String title, List<Ruta> listaRutas, Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          // Header de la Columna
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${listaRutas.length}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Lista de Tarjetas de Rutas
          Expanded(
            child: listaRutas.isEmpty
                ? Center(
                    child: Text(
                      'Sin rutas en esta fase',
                      style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: listaRutas.length,
                    itemBuilder: (context, index) {
                      final r = listaRutas[index];
                      final isExpanded = _rutasExpandidas.contains(r.id);
                      return _buildRutaCard(r, isExpanded, color);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRutaCard(Ruta r, bool isExpanded, Color color) {
    final int total = r.totalParadas;
    final int entregadas = r.paradasEntregadas;
    final int enCamino = r.paradas.where((p) => p.isEnCurso).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isExpanded ? color : AppTheme.border,
          width: isExpanded ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CABECERA DE LA TARJETA (Siempre visible, minimizada por defecto)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _toggleRuta(r.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.alt_route, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.codigoRuta,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.person, size: 12, color: AppTheme.textDim),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                r.choferNombre != null && r.choferNombre!.isNotEmpty ? r.choferNombre! : 'Sin chofer asignado',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      '$total paradas',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // DETALLE DESPLEGADO (Solo visible al presionar la tarjeta)
          if (isExpanded) ...[
            const Divider(color: AppTheme.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Resumen de Avance y Botón a Monitoreo en Vivo
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$entregadas de $total entregadas ($enCamino en camino)',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: total == 0 ? 0 : (entregadas / total),
                                backgroundColor: const Color(0xFF0F172A),
                                color: color,
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onVerEnMapa != null) ...[
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.radar, size: 13),
                          label: const Text('Ver en Mapa', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                          onPressed: () => widget.onVerEnMapa!(r),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Lista de Paradas de la Ruta
                  const Text(
                    'Paradas en esta Ruta:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                  ),
                  const SizedBox(height: 6),

                  if (r.paradas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Esta ruta aún no tiene paradas registradas.', style: TextStyle(fontSize: 11, color: AppTheme.textDim)),
                    )
                  else
                    ...r.paradas.map((p) => _buildParadaItem(p)),

                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                      icon: const Icon(Icons.keyboard_arrow_up, size: 14, color: AppTheme.textDim),
                      label: const Text('Minimizar', style: TextStyle(fontSize: 10.5, color: AppTheme.textDim)),
                      onPressed: () => _toggleRuta(r.id),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParadaItem(Despacho p) {
    Color statusCol = AppTheme.statusPendiente;
    String statusTxt = 'Pendiente';

    if (p.isEntregado) {
      statusCol = AppTheme.statusCompletada;
      statusTxt = 'Entregado';
    } else if (p.isEnCurso) {
      statusCol = AppTheme.statusEnCurso;
      statusTxt = 'En camino';
    } else if (p.estado == 'CANCELADA' || p.estado == 'CANCELADO') {
      statusCol = AppTheme.statusCancelada;
      statusTxt = 'Cancelado';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: p.hasAlertaDesviacion ? AppTheme.statusAlerta : const Color(0xFF1E293B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusCol.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#${p.ordenParada}',
                        style: TextStyle(color: statusCol, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.pedido?.cliente ?? 'Cliente',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusCol.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusCol.withValues(alpha: 0.5)),
                ),
                child: Text(
                  statusTxt,
                  style: TextStyle(color: statusCol, fontSize: 9, fontWeight: FontWeight.bold),
                ),
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
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, size: 11, color: AppTheme.textDim),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  p.pedido?.direccionTexto ?? 'Dirección no especificada',
                  style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (p.comentarios != null && p.comentarios!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.inventory_2, size: 10, color: AppTheme.primaryLight),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    p.comentarios!,
                    style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (p.hasAlertaDesviacion) ...[
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.statusAlerta.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning, size: 10, color: AppTheme.statusAlerta),
                  const SizedBox(width: 4),
                  Text(
                    'Desvío detectado: ${p.desviacionMetros?.toStringAsFixed(0)}m',
                    style: const TextStyle(color: AppTheme.statusAlerta, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
