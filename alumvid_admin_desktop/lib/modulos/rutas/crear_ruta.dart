import 'package:flutter/material.dart';

import '../../services/api_negocio.dart';
import '../../shared/adaptable.dart';
import '../../shared/mapa_selector.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import 'rutas_modulo.dart';

/// Convierte pedidos de la bandeja en el cuerpo para logística. Si alguno no
/// tiene ubicación en mapa, la pide antes (sin ella no se puede planificar).
Future<List<Map<String, dynamic>>?> completarUbicaciones(BuildContext context, List<Map<String, dynamic>> pedidos) async {
  final items = <Map<String, dynamic>>[];
  for (final p in pedidos) {
    if (p['delivery_latitude'] != null && p['delivery_longitude'] != null) {
      items.add({'pedidoId': p['id']});
      continue;
    }
    final u = await Navigator.of(context).push<UbicacionElegida>(MaterialPageRoute(
      builder: (_) => ConTemaAlumVid(child: MapaSelectorScreen(titulo: 'Ubicación del pedido #${p['number']}')),
    ));
    if (u == null) return null;
    items.add({'pedidoId': p['id'], 'latitud': u.punto.latitude, 'longitud': u.punto.longitude});
  }
  return items;
}

/// Hoja para elegir chofer: solo los disponibles se pueden seleccionar.
Future<Map<String, dynamic>?> elegirChofer(BuildContext context, {String? actualId}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.7, child: _SelectorChofer(actualId: actualId)),
  );
}

class _SelectorChofer extends StatefulWidget {
  const _SelectorChofer({this.actualId});
  final String? actualId;

  @override
  State<_SelectorChofer> createState() => _SelectorChoferState();
}

class _SelectorChoferState extends State<_SelectorChofer> {
  late Future<List<Map<String, dynamic>>> _f = Api.choferes();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (ctx, snap) {
        if (snap.hasError) return VistaError(mensaje: limpiarError(snap.error!), onReintentar: () => setState(() => _f = Api.choferes()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final orden = {'DISPONIBLE': 0, 'EN_RUTA': 1, 'INACTIVO': 2};
        final choferes = [...snap.data!]..sort((a, b) => (orden[a['estadoDisponibilidad']] ?? 3).compareTo(orden[b['estadoDisponibilidad']] ?? 3));
        return ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Elegir chofer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Solo se asignan choferes disponibles: activos y sin una ruta en curso.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
            if (choferes.isEmpty) const ListTile(title: Text('No hay usuarios con rol CHOFER')),
            for (final c in choferes)
              Builder(builder: (_) {
                final estado = aTexto(c['estadoDisponibilidad']);
                final disponible = estado == 'DISPONIBLE';
                final actual = '${c['id']}' == widget.actualId;
                return ListTile(
                  enabled: disponible && !actual,
                  leading: AvatarIniciales(aTexto(c['nombre'], '?'), color: disponible ? null : AppColors.neutral),
                  title: Text(aTexto(c['nombre'])),
                  subtitle: Text(
                    actual
                        ? 'Chofer actual'
                        : switch (estado) {
                            'DISPONIBLE' => 'Disponible${aTexto(c['telefono']).isEmpty ? '' : ' · ${c['telefono']}'}',
                            'EN_RUTA' => 'En ruta: se libera al terminar su recorrido',
                            _ => 'Inactivo o con clave temporal pendiente',
                          },
                  ),
                  trailing: EstadoChip(estado, texto: humanizar(estado)),
                  onTap: disponible && !actual ? () => Navigator.pop(context, c) : null,
                );
              }),
          ],
        );
      },
    );
  }
}

/// Hoja para elegir pedidos listos de la bandeja (excluye los ya elegidos).
Future<List<Map<String, dynamic>>?> elegirPedidosListos(BuildContext context, {Set<String> excluir = const {}}) {
  return showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _SelectorPedidos(excluir: excluir)),
  );
}

class _SelectorPedidos extends StatefulWidget {
  const _SelectorPedidos({required this.excluir});
  final Set<String> excluir;

  @override
  State<_SelectorPedidos> createState() => _SelectorPedidosState();
}

class _SelectorPedidosState extends State<_SelectorPedidos> {
  late final Future<List<Map<String, dynamic>>> _f = Api.entregasPendientes();
  final Set<String> _sel = {};

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (ctx, snap) {
        if (snap.hasError) return Center(child: Text(limpiarError(snap.error!)));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final listos = snap.data!.where((p) => listoParaRuta(p) && !widget.excluir.contains('${p['id']}')).toList();
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Pedidos listos para ruta', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ),
            Expanded(
              child: listos.isEmpty
                  ? const VistaVacia(icono: Icons.inbox_outlined, titulo: 'No hay pedidos listos', mensaje: 'Bodega debe preparar el material primero.')
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final p in listos) ...[
                          EntregaCard(
                            pedido: p,
                            seleccionado: _sel.contains('${p['id']}'),
                            onSeleccion: (v) => setState(() => v ? _sel.add('${p['id']}') : _sel.remove('${p['id']}')),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, listos.where((p) => _sel.contains('${p['id']}')).toList()),
                    child: Text(_sel.isEmpty ? 'Selecciona pedidos' : 'Agregar ${_sel.length} pedido(s)'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Crear ruta: chofer disponible + pedidos (opcional). Devuelve la ruta creada.
class CrearRuta extends StatefulWidget {
  const CrearRuta({super.key, this.pedidos = const []});
  final List<Map<String, dynamic>> pedidos;

  @override
  State<CrearRuta> createState() => _CrearRutaState();
}

class _CrearRutaState extends State<CrearRuta> {
  final _codigo = TextEditingController();
  final _desc = TextEditingController();
  Map<String, dynamic>? _chofer;
  late final List<Map<String, dynamic>> _pedidos = [...widget.pedidos];
  bool _guardando = false;

  @override
  void dispose() {
    _codigo.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _elegirChofer() async {
    final c = await elegirChofer(context, actualId: _chofer?['id']?.toString());
    if (c != null) setState(() => _chofer = c);
  }

  Future<void> _agregarPedidos() async {
    final r = await elegirPedidosListos(context, excluir: _pedidos.map((p) => '${p['id']}').toSet());
    if (r != null) setState(() => _pedidos.addAll(r));
  }

  Future<void> _crear() async {
    if (_chofer == null) {
      avisoError(context, 'Elige un chofer disponible');
      return;
    }
    final items = await completarUbicaciones(context, _pedidos);
    if (items == null) return;
    setState(() => _guardando = true);
    try {
      final ruta = await Api.crearRuta(
        choferId: '${_chofer!['id']}',
        codigo: _codigo.text.trim().isEmpty ? null : _codigo.text.trim().toUpperCase(),
        comentarios: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        pedidos: items,
      );
      if (!mounted) return;
      avisoOk(context, 'Ruta ${ruta['codigoRuta']} creada con ${_pedidos.length} parada(s)');
      Navigator.pop(context, ruta);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        avisoError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva ruta')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _guardando ? null : _crear,
            icon: _guardando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: Text(_pedidos.isEmpty ? 'Crear ruta vacía' : 'Crear ruta con ${_pedidos.length} parada(s)'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SeccionTitulo('Chofer'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: AvatarIniciales(aTexto(_chofer?['nombre'], '?')),
              title: Text(_chofer == null ? 'Elegir chofer disponible' : aTexto(_chofer!['nombre'])),
              subtitle: Text(_chofer == null ? 'Obligatorio' : aTexto(_chofer!['telefono'], 'Disponible')),
              trailing: const Icon(Icons.chevron_right),
              onTap: _elegirChofer,
            ),
          ),
          SeccionTitulo('Pedidos (${_pedidos.length})',
              accion: TextButton.icon(onPressed: _agregarPedidos, icon: const Icon(Icons.add), label: const Text('Agregar'))),
          if (_pedidos.isEmpty)
            const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('Puedes agregar pedidos ahora o después desde el detalle de la ruta.'))),
          for (final p in _pedidos)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text('#${p['number']} · ${p['client_name']}'),
                subtitle: Text(aTexto(p['delivery_address']), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Quitar de esta ruta',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _pedidos.remove(p)),
                ),
              ),
            ),
          const SeccionTitulo('Datos de la ruta (opcional)'),
          TextField(
            controller: _codigo,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Código', helperText: 'Si lo dejas vacío se genera automáticamente'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Descripción (ej. Zona norte - mañana)')),
          const SizedBox(height: 12),
          const Text(
            'Al crear la ruta, el material preparado de cada pedido queda bajo custodia del chofer asignado.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
