import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/movimiento.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

class AuditoriaInventarioDialog extends StatefulWidget {
  final DateTimeRange rangoInicial;
  final Function(DateTimeRange nuevoRango)? onRangoCambiado;

  const AuditoriaInventarioDialog({
    super.key,
    required this.rangoInicial,
    this.onRangoCambiado,
  });

  @override
  State<AuditoriaInventarioDialog> createState() => _AuditoriaInventarioDialogState();
}

class _AuditoriaInventarioDialogState extends State<AuditoriaInventarioDialog> {
  late DateTimeRange _rango;
  bool _cargando = true;
  String? _error;
  List<MovimientoInventario> _movimientos = [];

  String _filtroTexto = '';
  String _tipoFiltro = 'TODOS'; // 'TODOS', 'INGRESO', 'SALIDA', 'AJUSTE'
  bool _ordenAscendente = false; // Más recientes primero por defecto
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _rango = widget.rangoInicial;
    _cargarMovimientos();
  }

  Future<void> _cargarMovimientos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final from = DateTime(_rango.start.year, _rango.start.month, _rango.start.day, 0, 0, 0);
      final to = DateTime(_rango.end.year, _rango.end.month, _rango.end.day, 23, 59, 59);

      final list = await ApiService.obtenerMovimientosInventarioGlobal(
        from: from,
        to: to,
        type: _tipoFiltro == 'TODOS' ? '' : _tipoFiltro,
        q: _filtroTexto.trim(),
        page: 0,
        size: 250,
      );

      if (!mounted) return;
      setState(() {
        _movimientos = list;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _cargando = false;
      });
    }
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
      widget.onRangoCambiado?.call(picked);
      _cargarMovimientos();
    }
  }

  List<MovimientoInventario> _obtenerMovimientosFiltrados() {
    final q = _filtroTexto.trim().toLowerCase();
    final list = _movimientos.where((m) {
      if (_tipoFiltro != 'TODOS' && m.type != _tipoFiltro) {
        return false;
      }
      if (q.isEmpty) return true;
      final matchProd = m.productName.toLowerCase().contains(q);
      final matchCode = m.productCode.toLowerCase().contains(q);
      final matchActor = m.actorName.toLowerCase().contains(q);
      final matchReason = m.reason.toLowerCase().contains(q);
      final matchRef = m.reference.toLowerCase().contains(q);
      return matchProd || matchCode || matchActor || matchReason || matchRef;
    }).toList();

    list.sort((a, b) {
      final fa = a.occurredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final fb = b.occurredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return _ordenAscendente ? fa.compareTo(fb) : fb.compareTo(fa);
    });

    return list;
  }

  String _formatearRango(DateTimeRange r) {
    final f = DateFormat('dd MMM yyyy');
    if (r.start.year == r.end.year && r.start.month == r.end.month && r.start.day == r.end.day) {
      return f.format(r.start);
    }
    return '${DateFormat('dd MMM').format(r.start)} - ${f.format(r.end)}';
  }

  Future<void> _exportarAExcel(List<MovimientoInventario> lista) async {
    if (lista.isEmpty) {
      AppToast.warning(context, 'No hay movimientos en el periodo seleccionado para exportar.');
      return;
    }

    setState(() => _exportando = true);

    try {
      final buffer = StringBuffer();
      // UTF-8 BOM para compatibilidad directa y acentos en Microsoft Excel
      buffer.write('\uFEFF');

      // Cabecera CSV
      buffer.writeln(
        'FECHA Y HORA;'
        'RESPONSABLE / USUARIO;'
        'CODIGO PRODUCTO;'
        'PRODUCTO;'
        'TIPO MOVIMIENTO;'
        'CANTIDAD;'
        'DELTA;'
        'UNIDAD;'
        'SALDO ANTERIOR;'
        'SALDO RESULTANTE;'
        'MOTIVO;'
        'REFERENCIA',
      );

      final df = DateFormat('yyyy-MM-dd HH:mm:ss');

      for (final m in lista) {
        final fecha = m.occurredAt != null ? df.format(m.occurredAt!) : 'N/A';
        final responsable = m.actorName.replaceAll(';', ',');
        final codigo = m.productCode.replaceAll(';', ',');
        final nombre = m.productName.replaceAll(';', ',');
        final tipo = m.type;
        final cantidad = m.quantity.toString();
        final delta = (m.delta > 0 ? '+${m.delta}' : '${m.delta}');
        final unidad = m.unit;
        final saldoAnt = m.stockBefore.toString();
        final saldoPost = m.stockAfter.toString();
        final motivo = m.reason.replaceAll(';', ',').replaceAll('\n', ' ');
        final referencia = m.reference.replaceAll(';', ',').replaceAll('\n', ' ');

        buffer.writeln('$fecha;$responsable;$codigo;$nombre;$tipo;$cantidad;$delta;$unidad;$saldoAnt;$saldoPost;$motivo;$referencia');
      }

      // Guardar en la carpeta de Descargas del usuario de Windows
      String basePath = Directory.current.path;
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final downloads = Directory('$userProfile\\Downloads');
        if (downloads.existsSync()) {
          basePath = downloads.path;
        }
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '$basePath\\Kardex_Inventario_AlumVid_$timestamp.csv';
      final file = File(filePath);
      await file.writeAsString(buffer.toString());

      if (!mounted) return;
      AppToast.success(context, 'Kardex exportado exitosamente en: $filePath');

      // Intentar abrir el archivo exportado directamente en Excel / visor del sistema
      try {
        final uri = Uri.file(filePath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Error al exportar Kardex a Excel: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _obtenerMovimientosFiltrados();

    int totalIngresos = 0;
    int totalSalidas = 0;
    int totalAjustes = 0;

    for (final m in filtrados) {
      if (m.type == 'INGRESO') totalIngresos++;
      if (m.type == 'SALIDA') totalSalidas++;
      if (m.type == 'AJUSTE') totalAjustes++;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 1080,
        height: 720,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E293B), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Column(
          children: [
            // Cabecera del Diálogo
            _buildDialogHeader(),

            // Barra de Filtros, Rango de Fecha y Búsqueda
            _buildFilterToolbar(),

            // Tarjetas de Métricas de Auditoría
            _buildKpiMetrics(filtrados.length, totalIngresos, totalSalidas, totalAjustes),

            const Divider(color: Color(0xFF1E293B), height: 1),

            // Contenido Principal (Lista de Movimientos de Kardex)
            Expanded(
              child: _cargando
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppTheme.primaryLight),
                          SizedBox(height: 12),
                          Text('Consultando movimientos de inventario...', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: AppTheme.statusAlerta, size: 40),
                              const SizedBox(height: 10),
                              Text('Error al consultar movimientos: $_error', style: const TextStyle(color: AppTheme.statusAlerta, fontSize: 13)),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Reintentar'),
                                onPressed: _cargarMovimientos,
                              ),
                            ],
                          ),
                        )
                      : filtrados.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.inventory_2_outlined, color: AppTheme.textDim, size: 48),
                                  const SizedBox(height: 12),
                                  const Text('No se encontraron movimientos en este periodo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Modifique el rango de fechas (${_formatearRango(_rango)}) o el criterio de búsqueda.',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              itemCount: filtrados.length,
                              itemBuilder: (ctx, idx) => _buildMovimientoCard(filtrados[idx]),
                            ),
            ),

            // Pie del Diálogo con botón de Exportar y Cerrar
            _buildDialogFooter(filtrados),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF131D2E),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.history_edu, color: AppTheme.primaryLight, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auditoría e Histórico de Movimientos de Inventario (Kardex)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Registro cronológico de ingresos, salidas, ajustes de stock y retazos con trazabilidad por responsable',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Cerrar Ventana',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFF0D1527),
      child: Row(
        children: [
          // Selector de Rango de Fechas
          InkWell(
            onTap: _abrirSelectorRango,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: AppTheme.primaryLight, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Periodo: ${_formatearRango(_rango)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Buscador rápido
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: (val) => setState(() => _filtroTexto = val),
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar por producto, código, usuario, motivo o referencia...',
                  hintStyle: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                  prefixIcon: const Icon(Icons.search, size: 16, color: AppTheme.textMuted),
                  filled: true,
                  fillColor: const Color(0xFF131D2E),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Selector de Tipo de Movimiento
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF131D2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _tipoFiltro,
                dropdownColor: const Color(0xFF131D2E),
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 'TODOS', child: Text('Todos los Tipos')),
                  DropdownMenuItem(value: 'INGRESO', child: Text('Solo Ingresos')),
                  DropdownMenuItem(value: 'SALIDA', child: Text('Solo Salidas')),
                  DropdownMenuItem(value: 'AJUSTE', child: Text('Solo Ajustes')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _tipoFiltro = val);
                    _cargarMovimientos();
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Alternar orden ascendente / descendente
          IconButton(
            tooltip: _ordenAscendente ? 'Orden cronológico (más antiguos primero)' : 'Orden cronológico (más recientes primero)',
            icon: Icon(
              _ordenAscendente ? Icons.arrow_upward : Icons.arrow_downward,
              color: AppTheme.primaryLight,
              size: 18,
            ),
            onPressed: () => setState(() => _ordenAscendente = !_ordenAscendente),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiMetrics(int total, int ingresos, int salidas, int ajustes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFF0F172A),
      child: Row(
        children: [
          _buildChipKpi('Total Movimientos', '$total', AppTheme.primaryLight, Icons.sync_alt),
          const SizedBox(width: 12),
          _buildChipKpi('Ingresos de Stock', '$ingresos', AppTheme.statusCompletada, Icons.add_circle_outline),
          const SizedBox(width: 12),
          _buildChipKpi('Salidas / Despachos', '$salidas', AppTheme.statusAlerta, Icons.remove_circle_outline),
          const SizedBox(width: 12),
          _buildChipKpi('Ajustes Físicos / Retazos', '$ajustes', const Color(0xFFF59E0B), Icons.tune),
        ],
      ),
    );
  }

  Widget _buildChipKpi(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildMovimientoCard(MovimientoInventario m) {
    final Color color;
    final IconData icon;
    if (m.type == 'INGRESO') {
      color = AppTheme.statusCompletada;
      icon = Icons.add_circle;
    } else if (m.type == 'SALIDA') {
      color = AppTheme.statusAlerta;
      icon = Icons.remove_circle;
    } else {
      color = const Color(0xFFF59E0B);
      icon = Icons.tune;
    }

    final fechaStr = m.occurredAt != null ? DateFormat('dd MMM yyyy, HH:mm:ss').format(m.occurredAt!) : 'Fecha no registrada';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icono y Badge de Tipo
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 14),

          // Detalles Principales
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: color),
                          ),
                          child: Text(m.type, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          m.productName.isNotEmpty ? m.productName : 'Producto (${m.productId})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                        ),
                        if (m.productCode.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m.productCode,
                              style: const TextStyle(color: AppTheme.primaryLight, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      fechaStr,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Saldo y Variación
                Row(
                  children: [
                    Text(
                      'Variación: ${m.delta > 0 ? "+" : ""}${m.delta} ${m.unit}',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Saldo: ${m.stockBefore} → ${m.stockAfter} ${m.unit}',
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                    ),
                    const SizedBox(width: 14),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 13, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Text('Por: ${m.actorName}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Motivo y Referencia
                Row(
                  children: [
                    if (m.reason.isNotEmpty)
                      Expanded(
                        child: Text(
                          'Motivo: ${m.reason}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textDim, fontStyle: FontStyle.italic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (m.reference.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        'Ref: ${m.reference}',
                        style: const TextStyle(fontSize: 10, color: AppTheme.primaryLight),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogFooter(List<MovimientoInventario> lista) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF131D2E),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Mostrando ${lista.length} movimiento(s) del periodo filtrado.',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          Row(
            children: [
              // Botón Exportar a Excel (.csv UTF-8 BOM)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: _exportando
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.table_view, size: 16),
                label: const Text('Exportar a Excel (.csv)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: _exportando ? null : () => _exportarAExcel(lista),
              ),
              const SizedBox(width: 10),

              // Botón Cerrar
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF334155)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar Ventana', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
