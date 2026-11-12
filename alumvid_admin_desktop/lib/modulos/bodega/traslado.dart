import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_negocio.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';

/// Material a trasladar: una cantidad (productos por unidad) o piezas concretas.
class ItemTraslado {
  ItemTraslado({required this.productoId, required this.nombre, this.cantidadMax, this.piezas});
  final String productoId;
  final String nombre;
  final double? cantidadMax;
  final List<String>? piezas;
}

/// Traslado de un solo material. Devuelve true si se movió.
Future<bool> trasladarMaterial(
  BuildContext context, {
  required String productoId,
  required String descripcion,
  List<String>? piezas,
  double? cantidadMax,
  String? origen,
  String? origenId,
}) =>
    trasladarVarios(
      context,
      items: [ItemTraslado(productoId: productoId, nombre: descripcion, cantidadMax: cantidadMax, piezas: piezas)],
      origenCodigo: origen,
      origenId: origenId,
    );

/// Traslado en masa: todos los ítems van al mismo espacio de destino.
Future<bool> trasladarVarios(
  BuildContext context, {
  required List<ItemTraslado> items,
  String? origenCodigo,
  String? origenId,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.88,
      child: _TrasladoSheet(items: items, origenCodigo: origenCodigo, origenId: origenId),
    ),
  );
  return r == true;
}

class _TrasladoSheet extends StatefulWidget {
  const _TrasladoSheet({required this.items, this.origenCodigo, this.origenId});
  final List<ItemTraslado> items;
  final String? origenCodigo;
  final String? origenId;

  @override
  State<_TrasladoSheet> createState() => _TrasladoSheetState();
}

class _TrasladoSheetState extends State<_TrasladoSheet> {
  late final Future<List<Map<String, dynamic>>> _espacios = Api.espacios();
  late final _cantidades = {
    for (final i in widget.items)
      if (i.piezas == null) i: TextEditingController(text: i.cantidadMax == null ? '' : fmtNum(i.cantidadMax!)),
  };
  final _motivo = TextEditingController(text: 'Reorganización de bodega');
  String? _destino;
  bool _enviando = false;
  int _hechos = 0;

  @override
  void dispose() {
    for (final c in _cantidades.values) {
      c.dispose();
    }
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _confirmar(List<Map<String, dynamic>> espacios) async {
    if (_destino == null) {
      avisoError(context, 'Elige el espacio de destino');
      return;
    }
    if (_motivo.text.trim().isEmpty) {
      avisoError(context, 'Indica el motivo');
      return;
    }
    String? origenId = widget.origenId;
    if (origenId == null && (widget.origenCodigo ?? '').isNotEmpty) {
      origenId = espacios
          .where((e) => '${e['code']}'.toLowerCase() == widget.origenCodigo!.toLowerCase())
          .map((e) => '${e['id']}')
          .firstOrNull;
    }
    setState(() {
      _enviando = true;
      _hechos = 0;
    });
    try {
      for (final i in widget.items) {
        double? cantidad;
        if (i.piezas == null) {
          cantidad = double.tryParse(_cantidades[i]!.text.replaceAll(',', '.'));
          if (cantidad == null || cantidad <= 0) throw ApiError(400, 'Indica la cantidad de ${i.nombre}');
          if (i.cantidadMax != null && cantidad > i.cantidadMax! + 1e-9) throw ApiError(400, '${i.nombre}: supera lo que hay en el origen');
        }
        await Api.trasladar(
          productoId: i.productoId,
          desdeEspacioId: origenId,
          haciaEspacioId: _destino!,
          cantidad: cantidad,
          piezas: i.piezas,
          motivo: _motivo.text.trim(),
        );
        setState(() => _hechos++);
      }
      if (!mounted) return;
      avisoOk(context, widget.items.length == 1 ? 'Material trasladado' : '${widget.items.length} materiales trasladados');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      avisoError(context, _hechos > 0 ? 'Se movieron $_hechos de ${widget.items.length}. ${limpiarError(e)}' : e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _espacios,
        builder: (ctx, snap) {
          if (snap.hasError) return Center(child: Text(limpiarError(snap.error!)));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final destinos = snap.data!
              .where((e) => e['active'] != false && '${e['id']}' != widget.origenId &&
                  '${e['code']}'.toLowerCase() != (widget.origenCodigo ?? '').toLowerCase())
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.items.length == 1 ? 'Trasladar material' : 'Trasladar ${widget.items.length} materiales',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if ((widget.origenCodigo ?? '').isNotEmpty)
                Text('Desde ${widget.origenCodigo}', style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (final i in widget.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: i.piezas != null
                            ? ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.content_cut),
                                title: Text(i.nombre),
                                subtitle: Text('${i.piezas!.length} pieza(s)'),
                              )
                            : TextField(
                                controller: _cantidades[i],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                                decoration: InputDecoration(
                                  labelText: i.nombre,
                                  helperText: i.cantidadMax == null ? 'Cantidad a trasladar' : 'Hay ${fmtNum(i.cantidadMax!)} en el origen',
                                ),
                              ),
                      ),
                    const SeccionTitulo('Destino'),
                    if (destinos.isEmpty) const Text('No hay otros espacios activos. Créalos en Bodega → Espacios.'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in destinos)
                          ChoiceChip(
                            avatar: const Icon(Icons.shelves, size: 18),
                            label: Text('${e['code']}'),
                            selected: _destino == '${e['id']}',
                            onSelected: (_) => setState(() => _destino = '${e['id']}'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(controller: _motivo, decoration: const InputDecoration(labelText: 'Motivo')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _enviando ? null : () => _confirmar(snap.data!),
                icon: _enviando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.move_up),
                label: Text(_enviando ? 'Trasladando $_hechos/${widget.items.length}…' : 'Trasladar'),
              ),
            ],
          );
        },
      ),
    );
  }
}
