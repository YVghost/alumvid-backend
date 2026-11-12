import 'package:flutter/material.dart';

import '../../services/api_negocio.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import '../bodega/traslado.dart';

/// Detalle de una pieza física (retazo o unidad completa con medida).
class FichaPieza extends StatefulWidget {
  const FichaPieza({super.key, required this.piezaId, required this.permisos});
  final String piezaId;
  final Permisos permisos;

  @override
  State<FichaPieza> createState() => _FichaPiezaState();
}

class _FichaPiezaState extends State<FichaPieza> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _cambio = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final d = await Api.fichaPieza(widget.piezaId);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    }
  }

  Map<String, dynamic> get _pieza => Map<String, dynamic>.from(_d!['piece'] as Map);
  Map<String, dynamic> get _producto => Map<String, dynamic>.from(_d!['product'] as Map);

  Future<void> _trasladar() async {
    final ok = await trasladarMaterial(
      context,
      productoId: '${_producto['id']}',
      descripcion: '${_producto['name']} · ${medidas(_pieza['lengthM'], _pieza['widthCm'], _pieza['heightCm'])}',
      piezas: [widget.piezaId],
      origen: aTexto(_pieza['location']),
    );
    if (ok) {
      _cambio = true;
      _cargar();
    }
  }

  Future<void> _descartar() async {
    final motivo = await pedirTexto(context,
        titulo: 'Descartar pieza', etiqueta: 'Motivo (rotura, defecto, merma…)', accion: 'Descartar', peligro: true);
    if (motivo == null) return;
    try {
      await Api.descartarPieza('${_producto['id']}', widget.piezaId, motivo);
      if (!mounted) return;
      avisoOk(context, 'Pieza descartada');
      _cambio = true;
      _cargar();
    } catch (e) {
      if (mounted) avisoError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pieza')),
        body: _error != null ? VistaError(mensaje: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator()),
      );
    }
    final pz = _pieza, prod = _producto;
    final estado = aTexto(pz['state']);
    final disponible = estado == 'DISPONIBLE';
    final medida = medidas(pz['lengthM'], pz['widthCm'], pz['heightCm']);
    final porcentaje = aNum(pz['percentage']);
    final pedido = _d!['order'] == null ? null : Map<String, dynamic>.from(_d!['order'] as Map);
    final hijos = ((_d!['children'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final historial = ((_d!['history'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final padre = _d!['parent'] == null ? null : Map<String, dynamic>.from(_d!['parent'] as Map);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _cambio);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(medida.isEmpty ? 'Pieza' : 'Pieza $medida')),
        bottomNavigationBar: widget.permisos.bodega && {'DISPONIBLE', 'PREPARADO'}.contains(estado)
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(onPressed: _trasladar, icon: const Icon(Icons.move_up), label: const Text('Trasladar')),
                      ),
                      if (disponible) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _descartar,
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: const Text('Descartar'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            : null,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('${prod['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                        EstadoChip(estado),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(medida, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1)),
                        Text(pz['fullPiece'] == true ? 'Unidad completa' : 'Retazo',
                            style: const TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (porcentaje / 100).clamp(0, 1),
                        minHeight: 8,
                        color: pz['fullPiece'] == true ? AppColors.success : AppColors.violet,
                        backgroundColor: AppColors.border,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${fmtNum(porcentaje)} % de una unidad completa · equivale a ${fmtNum(aNum(pz['equivalentUnits']))} unid.',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    DatoFila('Ubicación', aTexto(pz['location'], 'Sin ubicación'), icono: Icons.shelves),
                    DatoFila('Código', '${prod['code']}', icono: Icons.qr_code_2),
                    if (pz['areaCm2'] != null) DatoFila('Área', '${fmtNum(aNum(pz['areaCm2']))} cm²', icono: Icons.square_foot),
                    DatoFila('Registrada', fmtFecha(aFecha(pz['createdAt'])), icono: Icons.event_outlined),
                    DatoFila('Identificador', '${pz['id']}'.substring(0, 8), icono: Icons.tag),
                  ],
                ),
              ),
            ),
            if (pedido != null) ...[
              const SeccionTitulo('Reservada para'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long, color: AppColors.warning),
                  title: Text('Pedido #${pedido['number']} · ${pedido['client_name']}'),
                  trailing: EstadoChip(aTexto(pedido['state'])),
                ),
              ),
            ],
            if (padre != null) ...[
              const SeccionTitulo('Se obtuvo de'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.call_split),
                  title: Text(medidas(padre['lengthM'], padre['widthCm'], padre['heightCm'])),
                  subtitle: Text(humanizar(aTexto(padre['state']))),
                ),
              ),
            ],
            if (hijos.isNotEmpty) ...[
              SeccionTitulo('Cortes derivados (${hijos.length})'),
              Card(
                child: Column(
                  children: [
                    for (final h in hijos)
                      ListTile(
                        leading: const Icon(Icons.content_cut),
                        title: Text(medidas(h['lengthM'], h['widthCm'], h['heightCm'])),
                        subtitle: Text(aTexto(h['location'], 'Sin ubicación')),
                        trailing: EstadoChip(aTexto(h['state'])),
                      ),
                  ],
                ),
              ),
            ],
            if (historial.isNotEmpty) ...[
              const SeccionTitulo('Historial'),
              Card(
                child: Column(
                  children: [
                    for (final h in historial)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.history, size: 20),
                        title: Text(humanizar(aTexto(h['action']))),
                        subtitle: Text('${aTexto(h['reason'])} · ${aTexto(h['actor_name'])} · ${fmtFecha(aFecha(h['created_at']))}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
