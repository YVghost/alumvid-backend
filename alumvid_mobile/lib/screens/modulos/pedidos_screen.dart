import 'package:alumvid_admin_desktop/models/pedido_comercial.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Pedidos y ventas comerciales (misma información que el administrador).
class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  static const _estados = <String, String>{
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

  String _estado = '';
  String _q = '';
  bool _cargando = true;
  String? _error;
  List<PedidoComercial> _items = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await adm.ApiService.obtenerPedidosComerciales(
        state: _estado,
        q: _q,
        size: 100,
      );
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        actions: [
          IconButton(
            tooltip: 'Abrir gestión completa en el navegador',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => abrirPortal(context, 'pedidos'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: CampoBusqueda(
              hint: 'Buscar por cliente o número',
              onChanged: (v) {
                _q = v;
                _cargar();
              },
            ),
          ),
          FiltrosChips<String>(
            opciones: _estados,
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
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const CargandoLista();
    if (_error != null) return VistaError(mensaje: _error!, onReintentar: _cargar);
    return RefreshIndicator(
      onRefresh: _cargar,
      child: _items.isEmpty
          ? const VistaVacia(
              icono: Icons.receipt_long,
              titulo: 'Sin pedidos',
              mensaje: 'No hay pedidos con este filtro.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _PedidoCard(
                pedido: _items[i],
                onTap: () => _detalle(_items[i]),
              ),
            ),
    );
  }

  void _detalle(PedidoComercial p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pedido #${p.number}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                EstadoChip(p.state),
              ],
            ),
            const SizedBox(height: 4),
            Text(p.clientName, style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    DatoFila('Total', fmtDinero(p.total), icono: Icons.payments_outlined),
                    DatoFila(
                      'Modalidad',
                      p.isEntregaDomicilio ? 'Entrega a domicilio' : 'Retiro en local',
                      icono: p.isEntregaDomicilio ? Icons.local_shipping_outlined : Icons.storefront_outlined,
                    ),
                    if (p.isEntregaDomicilio)
                      DatoFila('Dirección', p.deliveryAddress ?? '', icono: Icons.place_outlined),
                    DatoFila('Recibe', p.receiverName ?? '', icono: Icons.person_outline),
                    DatoFila('Creado', fmtFecha(p.createdAt), icono: Icons.event_outlined),
                    if (p.expiresAt != null)
                      DatoFila('Reserva vence', fmtFecha(p.expiresAt), icono: Icons.timer_outlined),
                  ],
                ),
              ),
            ),
            if ((p.notes ?? '').isNotEmpty) ...[
              const SeccionTitulo('Notas'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(p.notes!),
                ),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => abrirPortal(context, 'pedidos'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Gestionar en el portal web'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PedidoCard extends StatelessWidget {
  const _PedidoCard({required this.pedido, required this.onTap});
  final PedidoComercial pedido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
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
                height: 52,
                decoration: BoxDecoration(
                  color: colorEstado(p.state),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#${p.number}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          p.isEntregaDomicilio ? Icons.local_shipping_outlined : Icons.storefront_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        const Spacer(),
                        EstadoChip(p.state),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${fmtDinero(p.total)} · ${fmtFecha(p.createdAt)}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
