import 'package:flutter/material.dart';

import '../../services/api_negocio.dart';
import '../../shared/adaptable.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import 'clientes.dart';
import 'pedido_detalle.dart';
import 'pedido_form.dart';

const estadosPedido = <String, String>{
  '': 'Todos',
  'RESERVADO': 'Reservados',
  'PENDIENTE_MATERIAL': 'Falta material',
  'PARCIAL': 'Parciales',
  'LISTO': 'Listos',
  'EN_REPARTO': 'En reparto',
  'RETRASADO': 'Retrasados',
  'ENTREGADO': 'Entregados',
  'CANCELADO': 'Cancelados',
  'VENCIDO': 'Vencidos',
};

/// Pedidos y ventas: crear, reservar, preparar, entregar y devolver.
/// Toda la gestión se hace aquí (ya no hay portal web).
class PedidosModulo extends StatelessWidget {
  const PedidosModulo({super.key, required this.permisos});
  final Permisos permisos;

  @override
  Widget build(BuildContext context) {
    if (!permisos.vende) return Scaffold(appBar: AppBar(title: const Text('Pedidos')), body: ListaPedidos(permisos: permisos));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pedidos'),
          bottom: const TabBar(
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            tabs: [Tab(text: 'Pedidos'), Tab(text: 'Clientes')],
          ),
        ),
        body: TabBarView(children: [ListaPedidos(permisos: permisos), ClientesLista(permisos: permisos)]),
      ),
    );
  }
}

class ListaPedidos extends StatefulWidget {
  const ListaPedidos({super.key, required this.permisos});
  final Permisos permisos;

  @override
  State<ListaPedidos> createState() => _ListaPedidosState();
}

class _ListaPedidosState extends State<ListaPedidos> with AutomaticKeepAliveClientMixin {
  String _estado = '';
  String _q = '';
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _items.isEmpty;
      _error = null;
    });
    try {
      final r = await Api.pedidos(estado: _estado, q: _q);
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(String id) async {
    await abrirPanel(context, (_) => PedidoDetalle(pedidoId: id, permisos: widget.permisos));
    _cargar();
  }

  Future<void> _nuevo() async {
    final id = await abrirPanel<String>(context, (_) => const PedidoForm(), ancho: 720);
    await _cargar();
    if (id != null && mounted) _abrir(id);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: widget.permisos.vende
          ? FloatingActionButton.extended(
              heroTag: 'nuevo-pedido',
              onPressed: _nuevo,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nuevo pedido'),
            )
          : null,
      body: AnchoLegible(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: CampoBusqueda(
                hint: 'Buscar por cliente o número',
                onChanged: (v) {
                  _q = v;
                  _cargar();
                },
              ),
            ),
            FiltrosChips<String>(
              opciones: estadosPedido,
              seleccion: _estado,
              onSeleccion: (v) {
                setState(() => _estado = v);
                _cargar();
              },
            ),
            const SizedBox(height: 8),
            Expanded(child: _cuerpo()),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const CargandoLista();
    if (_error != null) return VistaError(mensaje: _error!, onReintentar: _cargar);
    return RefreshIndicator(
      onRefresh: _cargar,
      child: _items.isEmpty
          ? const VistaVacia(icono: Icons.receipt_long, titulo: 'Sin pedidos', mensaje: 'No hay pedidos con este filtro.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => PedidoCard(pedido: _items[i], onTap: () => _abrir('${_items[i]['id']}')),
            ),
    );
  }
}

class PedidoCard extends StatelessWidget {
  const PedidoCard({super.key, required this.pedido, required this.onTap, this.trailing});
  final Map<String, dynamic> pedido;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final estado = aTexto(p['state']);
    final entrega = p['delivery_mode'] == 'ENTREGA';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 54,
                decoration: BoxDecoration(color: colorEstado(estado), borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${p['number']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: entrega ? 'Entrega a domicilio' : 'Retiro en local',
                          child: Icon(entrega ? Icons.local_shipping_outlined : Icons.storefront_outlined,
                              size: 16, color: AppColors.textMuted),
                        ),
                        const Spacer(),
                        EstadoChip(estado),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(aTexto(p['client_name'], 'Cliente'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      '${fmtDinero(aNum(p['total']))} · ${fmtFecha(aFecha(p['created_at']))}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
