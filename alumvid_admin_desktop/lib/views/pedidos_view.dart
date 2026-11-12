import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pedido_comercial.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class PedidosView extends StatefulWidget {
  const PedidosView({super.key});

  @override
  State<PedidosView> createState() => _PedidosViewState();
}

class _PedidosViewState extends State<PedidosView> {
  List<PedidoComercial> _pedidos = [];
  bool _cargando = true;
  String _filtroEstado = '';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _estados = [
    'TODOS',
    'RESERVADO',
    'LISTO',
    'PARCIAL',
    'EN_REPARTO',
    'ENTREGADO',
    'CANCELADO',
    'VENCIDO',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
  }

  Future<void> _cargarPedidos() async {
    setState(() => _cargando = true);
    try {
      final list = await ApiService.obtenerPedidosComerciales(
        state: _filtroEstado == 'TODOS' ? '' : _filtroEstado,
        q: _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _pedidos = list;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cargar: $e')));
    }
  }

  Color _obtenerColorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case 'LISTO':
      case 'ENTREGADO':
        return AppTheme.statusCompletada; // Verde
      case 'EN_REPARTO':
      case 'RESERVADO':
        return const Color(0xFF38BDF8); // Cian
      case 'PARCIAL':
        return AppTheme.statusEnCurso; // Ámbar
      case 'VENCIDO':
      case 'CANCELADO':
        return AppTheme.statusAlerta; // Rojo
      default:
        return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bgDark,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra Superior: Título y Acciones
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gestión de Pedidos & Ventas Comerciales',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Microservicio Pedidos (Puerto 8085) • Reservas inmutables con plazo de 72 horas',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir gestión completa'),
                onPressed: () async {
                  final host = await ApiService.getBaseHost();
                  await launchUrl(
                    Uri.parse('$host/pedidos/'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Actualizar'),
                onPressed: _cargarPedidos,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Filtros de Búsqueda y Estados
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText:
                        'Buscar por número de pedido o nombre de cliente...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: AppTheme.textMuted,
                    ),
                    filled: true,
                    fillColor: AppTheme.surfaceDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 12,
                    ),
                  ),
                  onSubmitted: (_) => _cargarPedidos(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filtroEstado.isEmpty ? 'TODOS' : _filtroEstado,
                  dropdownColor: AppTheme.surfaceDark,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Estado del Pedido',
                    labelStyle: const TextStyle(color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surfaceDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 12,
                    ),
                  ),
                  items: _estados
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _filtroEstado = v ?? '');
                    _cargarPedidos();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Contenido: Lista / Grid de Pedidos
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _pedidos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_rounded,
                          size: 64,
                          color: AppTheme.textMuted.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No se encontraron pedidos registrados con los filtros actuales',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Los pedidos se registran en el portal de ventas y se sincronizan aquí para su despacho.',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _pedidos.length,
                    itemBuilder: (context, index) {
                      final p = _pedidos[index];
                      final estadoColor = _obtenerColorEstado(p.state);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Row(
                          children: [
                            // Número e Ícono de Pedido
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: estadoColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '#${p.number}',
                                  style: TextStyle(
                                    color: estadoColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Cliente y Modo de Entrega
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.clientName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        p.isEntregaDomicilio
                                            ? Icons.local_shipping_rounded
                                            : Icons.storefront_rounded,
                                        size: 14,
                                        color: AppTheme.textMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        p.deliveryMode == 'ENTREGA'
                                            ? (p.deliveryAddress ??
                                                  'Dirección a domicilio')
                                            : 'Retiro en almacén AlumVid',
                                        style: TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Plazo y Vencimiento 72h
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Plazo de Reserva (72h)',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    p.expiresAt != null
                                        ? DateFormat(
                                            'dd/MM/yyyy HH:mm',
                                          ).format(p.expiresAt!)
                                        : 'Ficha antigua',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Monto Total
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Total Facturado',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '\$${p.total.toStringAsFixed(2)} USD',
                                    style: const TextStyle(
                                      color: Color(0xFF34D399),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Badge de Estado
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: estadoColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: estadoColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                p.state,
                                style: TextStyle(
                                  color: estadoColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
