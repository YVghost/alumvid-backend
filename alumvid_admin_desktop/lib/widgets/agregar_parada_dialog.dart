import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/producto.dart';
import '../models/pedido_comercial.dart';
import '../models/retazo_pieza.dart';
import '../models/ruta.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import 'map_picker_dialog.dart';

enum TipoEntregaMaterial {
  inventario,
  retazo,
}

class AgregarParadaDialog extends StatefulWidget {
  final Ruta ruta;
  final VoidCallback onParadaAgregada;

  const AgregarParadaDialog({
    super.key,
    required this.ruta,
    required this.onParadaAgregada,
  });

  @override
  State<AgregarParadaDialog> createState() => _AgregarParadaDialogState();
}

class _AgregarParadaDialogState extends State<AgregarParadaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _clienteCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '1');
  final _observacionesCtrl = TextEditingController();

  double _lat = -0.1807;
  double _lon = -78.4678;
  String _direccionResuelta = 'Quito Centro, Pichincha, Ecuador';
  bool _ubicacionSeleccionada = false;

  // Catálogos
  TipoEntregaMaterial _tipoEntrega = TipoEntregaMaterial.inventario;
  List<Producto> _productosInventario = [];
  List<PedidoComercial> _pedidosComerciales = [];
  Producto? _productoSeleccionado;

  List<ProductoRetazo> _productosRetazo = [];
  ProductoRetazo? _productoRetazoSeleccionado;
  List<PiezaRetazo> _piezasDisponibles = [];
  PiezaRetazo? _piezaSeleccionada;

  // Estado de corte a medida
  bool _modoCorteActivo = false;
  bool _ejecutandoCorte = false;
  final _longitudCorteCtrl = TextEditingController();
  final _anchoCorteCtrl = TextEditingController();
  final _mermaCorteCtrl = TextEditingController(text: '0.00');
  PiezaRetazo? _piezaOrigenCorte;
  String? _mensajeCorteExitoso;

  bool _cargandoProductos = true;
  bool _cargandoPiezas = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  @override
  void dispose() {
    _clienteCtrl.dispose();
    _direccionCtrl.dispose();
    _cantidadCtrl.dispose();
    _observacionesCtrl.dispose();
    _longitudCorteCtrl.dispose();
    _anchoCorteCtrl.dispose();
    _mermaCorteCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    try {
      final res = await ApiService.obtenerProductos(size: 100);
      final List<Producto> prods = res['items'] as List<Producto>? ?? [];
      final pedidos = await ApiService.obtenerPedidosComerciales(size: 30);
      final retazos = await ApiService.obtenerProductosRetazos();

      if (mounted) {
        setState(() {
          _productosInventario = prods;
          _pedidosComerciales = pedidos.where((p) => p.isEntregaDomicilio).toList();
          _productosRetazo = retazos;
          if (prods.isNotEmpty) {
            _productoSeleccionado = prods.first;
          }
          if (retazos.isNotEmpty) {
            _productoRetazoSeleccionado = retazos.first;
          }
          _cargandoProductos = false;
        });

        if (retazos.isNotEmpty) {
          _cargarPiezasDeRetazo(retazos.first.id);
        }
      }
    } catch (e) {
      debugPrint('Error al cargar productos de inventario: $e');
      if (mounted) setState(() => _cargandoProductos = false);
    }
  }

  Future<void> _cargarPiezasDeRetazo(String prodId) async {
    setState(() => _cargandoPiezas = true);
    try {
      final piezas = await ApiService.obtenerPiezasRetazo(prodId, state: 'DISPONIBLE');
      if (!mounted) return;
      setState(() {
        _piezasDisponibles = piezas;
        _piezaSeleccionada = piezas.isNotEmpty ? piezas.first : null;
        _piezaOrigenCorte = piezas.isNotEmpty ? piezas.first : null;
        _cargandoPiezas = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoPiezas = false);
    }
  }

  Future<void> _realizarCorte() async {
    if (_productoRetazoSeleccionado == null) return;
    if (_piezaOrigenCorte == null) {
      AppToast.error(context, 'Seleccione la pieza física de origen para el corte');
      return;
    }

    final kind = _productoRetazoSeleccionado!.kind?.toUpperCase() ?? 'ALUMINIO';
    double? usedLength;
    double? usedWidth;
    double? wasteLength;
    double? wasteWidth;

    if (kind == 'ALUMINIO') {
      final len = double.tryParse(_longitudCorteCtrl.text.replaceAll(',', '.'));
      if (len == null || len <= 0) {
        AppToast.error(context, 'Ingrese una longitud válida mayor a 0 m');
        return;
      }
      final maxAvailable = _piezaOrigenCorte!.lengthM ?? 0;
      if (len > maxAvailable) {
        AppToast.error(context, 'La longitud requerida ($len m) supera la pieza origen ($maxAvailable m)');
        return;
      }
      usedLength = len;
      final waste = double.tryParse(_mermaCorteCtrl.text.replaceAll(',', '.'));
      if (waste != null && waste > 0) wasteLength = waste;
    } else {
      final width = double.tryParse(_anchoCorteCtrl.text.replaceAll(',', '.'));
      if (width == null || width <= 0) {
        AppToast.error(context, 'Ingrese un ancho válido mayor a 0 cm');
        return;
      }
      final maxAvailable = _piezaOrigenCorte!.widthCm ?? 0;
      if (width > maxAvailable) {
        AppToast.error(context, 'El ancho requerido ($width cm) supera la pieza origen ($maxAvailable cm)');
        return;
      }
      usedWidth = width;
      final waste = double.tryParse(_mermaCorteCtrl.text.replaceAll(',', '.'));
      if (waste != null && waste > 0) wasteWidth = waste;
    }

    setState(() => _ejecutandoCorte = true);

    try {
      final res = await ApiService.cortarPiezaRetazo(
        productoId: _productoRetazoSeleccionado!.id,
        pieceId: _piezaOrigenCorte!.id,
        usedLengthM: usedLength,
        usedWidthCm: usedWidth,
        wasteLengthM: wasteLength,
        wasteWidthCm: wasteWidth,
        reason: 'Corte de material para despacho en ruta ${widget.ruta.codigoRuta}',
      );

      final med = kind == 'ALUMINIO' ? '$usedLength m' : '$usedWidth cm';
      final detail = res['detail'] as Map<String, dynamic>?;
      final rem = detail?['remainingExtent'];
      final remText = rem != null ? ' (Sobrante: $rem ${kind == 'ALUMINIO' ? 'm' : 'cm'} en bodega)' : '';

      final piezasActualizadas = await ApiService.obtenerPiezasRetazo(_productoRetazoSeleccionado!.id, state: 'DISPONIBLE');

      if (!mounted) return;
      setState(() {
        _piezasDisponibles = piezasActualizadas;
        _piezaSeleccionada = piezasActualizadas.isNotEmpty ? piezasActualizadas.first : null;
        _modoCorteActivo = false;
        _mensajeCorteExitoso = '✓ Corte de $med registrado$remText y asignado a esta entrega.';
        _ejecutandoCorte = false;
      });

      AppToast.success(context, 'Corte de material registrado y descontado en Bodega');
    } catch (e) {
      if (mounted) {
        setState(() => _ejecutandoCorte = false);
        AppToast.error(context, 'Error al ejecutar corte: $e');
      }
    }
  }

  Future<void> _abrirSelectorMapa() async {
    final result = await showDialog<MapPickerResult>(
      context: context,
      builder: (_) => MapPickerDialog(
        initialLocation: LatLng(_lat, _lon),
        title: 'Elegir Ubicación de Parada en Google Maps',
      ),
    );

    if (result != null) {
      setState(() {
        _lat = result.location.latitude;
        _lon = result.location.longitude;
        _direccionResuelta = result.address;
        _ubicacionSeleccionada = true;
        if (_direccionCtrl.text.trim().isEmpty || _direccionCtrl.text.trim() == 'Quito Centro, Pichincha, Ecuador') {
          _direccionCtrl.text = result.address;
        }
      });
    }
  }

  Future<void> _guardarParada() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    // Formatear qué se va a entregar con metadatos para cierre e-PoD y descuento físico
    String queSeEntrega = '';
    if (_tipoEntrega == TipoEntregaMaterial.retazo && _piezaSeleccionada != null && _productoRetazoSeleccionado != null) {
      queSeEntrega = 'Retazo: [${_productoRetazoSeleccionado!.code}] ${_productoRetazoSeleccionado!.name} (${_piezaSeleccionada!.dimensionesTexto})';
      if (_piezaSeleccionada!.location != null && _piezaSeleccionada!.location!.isNotEmpty) {
        queSeEntrega += ' - Ubic: ${_piezaSeleccionada!.location}';
      }
      if (_observacionesCtrl.text.trim().isNotEmpty) {
        queSeEntrega += ' - ${_observacionesCtrl.text.trim()}';
      }
      queSeEntrega += ' [META:PID=${_productoRetazoSeleccionado!.id};QTY=1;PIECE=${_piezaSeleccionada!.id}]';
    } else if (_tipoEntrega == TipoEntregaMaterial.inventario && _productoSeleccionado != null) {
      final cant = _cantidadCtrl.text.trim().isNotEmpty ? _cantidadCtrl.text.trim() : '1';
      queSeEntrega = '${_productoSeleccionado!.name} ($cant ${_productoSeleccionado!.unit})';
      if (_observacionesCtrl.text.trim().isNotEmpty) {
        queSeEntrega += ' - ${_observacionesCtrl.text.trim()}';
      }
      queSeEntrega += ' [META:PID=${_productoSeleccionado!.id};QTY=$cant]';
    } else if (_observacionesCtrl.text.trim().isNotEmpty) {
      queSeEntrega = _observacionesCtrl.text.trim();
    } else {
      queSeEntrega = 'Material de Vidriería / Perfilería';
    }

    try {
      await ApiService.agregarDestinoRuta(
        rutaId: widget.ruta.id,
        cliente: _clienteCtrl.text.trim(),
        direccionTexto: _direccionCtrl.text.trim(),
        latitud: _lat,
        longitud: _lon,
        comentarios: queSeEntrega,
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onParadaAgregada();

      AppToast.success(context, 'Parada "${_clienteCtrl.text.trim()}" agregada a la ruta ${widget.ruta.codigoRuta}.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      AppToast.error(context, 'Error al guardar la parada: ${e.toString().replaceAll("Exception: ", "")}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.primaryLight),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 880),
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Encabezado
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add_location_alt, color: AppTheme.primaryLight, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Agregar Parada a ${widget.ruta.codigoRuta}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const Text(
                              'Complete los datos del cliente, producto de inventario y ubicación en mapa',
                              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
                const Divider(color: AppTheme.border, height: 22),

                // Distribución en 2 Columnas: Formulario a la izquierda, Tarjeta de Mapa a la derecha
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 640;

                    final formSection = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Vincular con Pedido Comercial (Opcional)
                        if (_pedidosComerciales.isNotEmpty) ...[
                          DropdownButtonFormField<PedidoComercial>(
                            dropdownColor: AppTheme.surfaceDark,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Importar de Pedido Comercial (Opcional)',
                              prefixIcon: Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFF38BDF8)),
                              hintText: 'Seleccione un pedido para autocompletar',
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('-- Ingreso manual independiente --')),
                              ..._pedidosComerciales.map((p) => DropdownMenuItem(
                                value: p,
                                child: Text('#${p.number} · ${p.clientName} (\$${p.total.toStringAsFixed(2)})', overflow: TextOverflow.ellipsis),
                              )),
                            ],
                            onChanged: (p) {
                              if (p != null) {
                                setState(() {
                                  _clienteCtrl.text = p.clientName;
                                  if (p.deliveryAddress != null && p.deliveryAddress!.isNotEmpty) {
                                    _direccionCtrl.text = p.deliveryAddress!;
                                    _direccionResuelta = p.deliveryAddress!;
                                  }
                                  _observacionesCtrl.text = 'Orden #${p.number} comercial • ${p.notes ?? "Entrega a domicilio"}';
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Cliente y Dirección
                        TextFormField(
                          controller: _clienteCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Cliente o Razón Social *',
                            hintText: 'Ej. Constructora Los Andes / Vidriería El Diamante',
                            prefixIcon: Icon(Icons.business, size: 18),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese el cliente o razón social' : null,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _direccionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Dirección de Entrega *',
                            hintText: 'Ej. Av. 6 de Diciembre y Orellana, Quito',
                            prefixIcon: Icon(Icons.home, size: 18),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese la dirección de entrega' : null,
                        ),
                        const SizedBox(height: 12),

                        // Qué se va a entregar (Selector Inventario / Retazos)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131D2E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.inventory_2_rounded, color: AppTheme.primaryLight, size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'Qué se va a entregar (Inventario & Retazos)',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryLight),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () => setState(() => _tipoEntrega = TipoEntregaMaterial.inventario),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _tipoEntrega == TipoEntregaMaterial.inventario ? const Color(0xFF1D72FE) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Inventario',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: _tipoEntrega == TipoEntregaMaterial.inventario ? Colors.white : const Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => setState(() => _tipoEntrega = TipoEntregaMaterial.retazo),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _tipoEntrega == TipoEntregaMaterial.retazo ? const Color(0xFF1D72FE) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Retazo Bodega',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: _tipoEntrega == TipoEntregaMaterial.retazo ? Colors.white : const Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              if (_cargandoProductos)
                                const Row(
                                  children: [
                                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                    SizedBox(width: 8),
                                    Text('Cargando catálogo...', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                                  ],
                                )
                              else if (_tipoEntrega == TipoEntregaMaterial.inventario) ...[
                                DropdownButtonFormField<Producto>(
                                  initialValue: _productoSeleccionado,
                                  isExpanded: true,
                                  dropdownColor: AppTheme.surfaceCard,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: const InputDecoration(
                                    labelText: 'Seleccionar Producto de Bodega *',
                                    isDense: true,
                                    prefixIcon: Icon(Icons.category, size: 18),
                                  ),
                                  items: _productosInventario.map((prod) {
                                    return DropdownMenuItem<Producto>(
                                      value: prod,
                                      child: Text(
                                        '[${prod.code}] ${prod.name}  —  (Stock: ${prod.stock.toStringAsFixed(0)} ${prod.unit})',
                                        style: const TextStyle(fontSize: 12, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() => _productoSeleccionado = val);
                                  },
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 130,
                                      child: TextFormField(
                                        controller: _cantidadCtrl,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                        decoration: InputDecoration(
                                          labelText: 'Cantidad *',
                                          suffixText: _productoSeleccionado?.unit ?? 'Unid',
                                          isDense: true,
                                          prefixIcon: const Icon(Icons.numbers, size: 16),
                                        ),
                                        validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _observacionesCtrl,
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                        decoration: const InputDecoration(
                                          labelText: 'Detalle adicional / Dimensiones',
                                          hintText: 'Ej. Templado 10mm / Medidas especiales',
                                          isDense: true,
                                          prefixIcon: Icon(Icons.edit_note, size: 18),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                // Modo Retazos de Bodega
                                DropdownButtonFormField<ProductoRetazo>(
                                  initialValue: _productoRetazoSeleccionado,
                                  isExpanded: true,
                                  dropdownColor: AppTheme.surfaceCard,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: const InputDecoration(
                                    labelText: 'Material de Corte *',
                                    isDense: true,
                                    prefixIcon: Icon(Icons.content_cut_rounded, size: 18),
                                  ),
                                  items: _productosRetazo.map((prod) {
                                    return DropdownMenuItem<ProductoRetazo>(
                                      value: prod,
                                      child: Text(
                                        '[${prod.code}] ${prod.name} (${prod.kind ?? "Corte"})',
                                        style: const TextStyle(fontSize: 12, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _productoRetazoSeleccionado = val);
                                      _cargarPiezasDeRetazo(val.id);
                                    }
                                  },
                                ),
                                const SizedBox(height: 10),

                                // Selector Modo: Existente vs Corte a Medida
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _modoCorteActivo = false),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          decoration: BoxDecoration(
                                            color: !_modoCorteActivo ? const Color(0xFF1E293B) : Colors.transparent,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: !_modoCorteActivo ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.inventory_2_outlined, size: 14, color: !_modoCorteActivo ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8)),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Retazo Existente',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: !_modoCorteActivo ? Colors.white : const Color(0xFF94A3B8)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _modoCorteActivo = true),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _modoCorteActivo ? const Color(0xFF1E293B) : Colors.transparent,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: _modoCorteActivo ? const Color(0xFF10B981) : const Color(0xFF334155),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.content_cut_rounded, size: 14, color: _modoCorteActivo ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Corte a Medida',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _modoCorteActivo ? Colors.white : const Color(0xFF94A3B8)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                if (_mensajeCorteExitoso != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF064E3B).withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF10B981)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _mensajeCorteExitoso!,
                                            style: const TextStyle(color: Color(0xFFD1FAE5), fontSize: 11, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],

                                if (_cargandoPiezas)
                                  const Row(
                                    children: [
                                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                      SizedBox(width: 8),
                                      Text('Buscando retazos disponibles...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                    ],
                                  )
                                else if (!_modoCorteActivo) ...[
                                   if (_piezasDisponibles.isEmpty)
                                     const Text(
                                       'No hay retazos físicos individuales registrados para este material. Use "Corte a Medida" para seccionar una barra/plancha.',
                                       style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11),
                                     )
                                   else
                                     DropdownButtonFormField<PiezaRetazo>(
                                       initialValue: _piezaSeleccionada,
                                       isExpanded: true,
                                       dropdownColor: AppTheme.surfaceCard,
                                       style: const TextStyle(color: Colors.white, fontSize: 12),
                                       decoration: const InputDecoration(
                                         labelText: 'Seleccionar Retazo Disponible *',
                                         isDense: true,
                                         prefixIcon: Icon(Icons.straighten_rounded, size: 18),
                                       ),
                                       items: _piezasDisponibles.map((p) {
                                         final loc = p.location != null && p.location!.isNotEmpty ? ' (${p.location})' : '';
                                         return DropdownMenuItem<PiezaRetazo>(
                                           value: p,
                                           child: Text(
                                             '${p.dimensionesTexto}$loc',
                                             style: const TextStyle(fontSize: 12, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
                                             overflow: TextOverflow.ellipsis,
                                           ),
                                         );
                                       }).toList(),
                                       onChanged: (val) {
                                         setState(() => _piezaSeleccionada = val);
                                       },
                                     ),
                                 ] else ...[
                                   // Formulario de Corte a Medida en Directo
                                   Container(
                                     padding: const EdgeInsets.all(10),
                                     decoration: BoxDecoration(
                                       color: const Color(0xFF0F172A),
                                       borderRadius: BorderRadius.circular(8),
                                       border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                     ),
                                     child: Column(
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                         Row(
                                           children: [
                                             const Icon(Icons.content_cut_rounded, size: 14, color: Color(0xFF10B981)),
                                             const SizedBox(width: 6),
                                             Text(
                                               'Corte de ${_productoRetazoSeleccionado?.kind == "VIDRIO" ? "Vidrio" : "Aluminio"}',
                                               style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF10B981)),
                                             ),
                                           ],
                                         ),
                                         const SizedBox(height: 8),

                                         // Pieza origen a cortar
                                         if (_piezasDisponibles.isNotEmpty) ...[
                                           DropdownButtonFormField<PiezaRetazo>(
                                             initialValue: _piezaOrigenCorte,
                                             isExpanded: true,
                                             dropdownColor: AppTheme.surfaceCard,
                                             style: const TextStyle(color: Colors.white, fontSize: 11),
                                             decoration: const InputDecoration(
                                               labelText: 'Pieza física origen a cortar *',
                                               isDense: true,
                                               prefixIcon: Icon(Icons.crop_square_rounded, size: 16),
                                             ),
                                             items: _piezasDisponibles.map((p) {
                                               final loc = p.location != null && p.location!.isNotEmpty ? ' (${p.location})' : '';
                                               return DropdownMenuItem<PiezaRetazo>(
                                                 value: p,
                                                 child: Text(
                                                   '${p.dimensionesTexto}$loc',
                                                   style: const TextStyle(fontSize: 11, color: Colors.white),
                                                   overflow: TextOverflow.ellipsis,
                                                 ),
                                               );
                                             }).toList(),
                                             onChanged: (val) => setState(() => _piezaOrigenCorte = val),
                                           ),
                                           const SizedBox(height: 8),
                                         ],

                                         if (_productoRetazoSeleccionado?.kind == 'VIDRIO') ...[
                                           Row(
                                             children: [
                                               Expanded(
                                                 child: TextFormField(
                                                   controller: _anchoCorteCtrl,
                                                   keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                   style: const TextStyle(color: Colors.white, fontSize: 12),
                                                   decoration: const InputDecoration(
                                                     labelText: 'Ancho requerido *',
                                                     hintText: 'Ej. 80.0',
                                                     suffixText: 'cm',
                                                     isDense: true,
                                                     prefixIcon: Icon(Icons.straighten, size: 16),
                                                   ),
                                                 ),
                                               ),
                                               const SizedBox(width: 8),
                                               Expanded(
                                                 child: TextFormField(
                                                   controller: _mermaCorteCtrl,
                                                   keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                   style: const TextStyle(color: Colors.white, fontSize: 12),
                                                   decoration: const InputDecoration(
                                                     labelText: 'Merma',
                                                     hintText: '0.0',
                                                     suffixText: 'cm',
                                                     isDense: true,
                                                     prefixIcon: Icon(Icons.delete_sweep_outlined, size: 16),
                                                   ),
                                                 ),
                                               ),
                                             ],
                                           ),
                                           const SizedBox(height: 4),
                                           const Text(
                                             '• Alto estándar de plancha: 150.0 cm',
                                             style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                           ),
                                         ] else ...[
                                           Row(
                                             children: [
                                               Expanded(
                                                 child: TextFormField(
                                                   controller: _longitudCorteCtrl,
                                                   keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                   style: const TextStyle(color: Colors.white, fontSize: 12),
                                                   decoration: const InputDecoration(
                                                     labelText: 'Longitud requerida *',
                                                     hintText: 'Ej. 1.80',
                                                     suffixText: 'm',
                                                     isDense: true,
                                                     prefixIcon: Icon(Icons.straighten, size: 16),
                                                   ),
                                                 ),
                                               ),
                                               const SizedBox(width: 8),
                                               Expanded(
                                                 child: TextFormField(
                                                   controller: _mermaCorteCtrl,
                                                   keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                   style: const TextStyle(color: Colors.white, fontSize: 12),
                                                   decoration: const InputDecoration(
                                                     labelText: 'Merma',
                                                     hintText: '0.00',
                                                     suffixText: 'm',
                                                     isDense: true,
                                                     prefixIcon: Icon(Icons.delete_sweep_outlined, size: 16),
                                                   ),
                                                 ),
                                               ),
                                             ],
                                           ),
                                         ],
                                         const SizedBox(height: 10),

                                         SizedBox(
                                           width: double.infinity,
                                           height: 32,
                                           child: ElevatedButton.icon(
                                             icon: _ejecutandoCorte
                                                 ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                 : const Icon(Icons.content_cut, size: 15),
                                             label: Text(
                                               _ejecutandoCorte ? 'Procesando corte en Bodega...' : 'Ejecutar Corte y Asignar Pieza',
                                               style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                             ),
                                             style: ElevatedButton.styleFrom(
                                               backgroundColor: const Color(0xFF10B981),
                                               foregroundColor: Colors.white,
                                               padding: const EdgeInsets.symmetric(horizontal: 10),
                                               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                             ),
                                             onPressed: _ejecutandoCorte ? null : _realizarCorte,
                                           ),
                                         ),
                                       ],
                                     ),
                                   ),
                                 ],
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _observacionesCtrl,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: const InputDecoration(
                                    labelText: 'Detalle adicional / Nota de corte',
                                    hintText: 'Ej. Despacho directo de sobrante de bodega',
                                    isDense: true,
                                    prefixIcon: Icon(Icons.edit_note_rounded, size: 18),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );

                    final mapPreviewSection = SizedBox(
                      width: isWide ? 280 : double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.location_on, size: 15, color: AppTheme.primaryLight),
                                  SizedBox(width: 5),
                                  Text(
                                    'Punto de Entrega',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryLight),
                                  ),
                                ],
                              ),
                              Text(
                                '${_lat.toStringAsFixed(4)}, ${_lon.toStringAsFixed(4)}',
                                style: const TextStyle(color: AppTheme.textDim, fontSize: 10, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Miniatura Interactiva del Mapa (Google Roadmap, Pin centrado)
                          InkWell(
                            onTap: _abrirSelectorMapa,
                            borderRadius: BorderRadius.circular(10),
                            child: Tooltip(
                              message: 'Haga clic para abrir el mapa interactivo con buscador inteligente',
                              child: Container(
                                height: 210,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _ubicacionSeleccionada
                                        ? AppTheme.statusCompletada.withValues(alpha: 0.85)
                                        : AppTheme.border,
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: Stack(
                                    children: [
                                      IgnorePointer(
                                        ignoring: true,
                                        child: FlutterMap(
                                          key: ValueKey('dialog-map-$_lat-$_lon'),
                                          options: MapOptions(
                                            initialCenter: LatLng(_lat, _lon),
                                            initialZoom: 15.0,
                                            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                                          ),
                                          children: [
                                            TileLayer(
                                              urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                                              userAgentPackageName: 'com.alumvid.admin',
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Pin Rojo Centrado con Sombra
                                      Center(
                                        child: FractionalTranslation(
                                          translation: const Offset(0.0, -0.42),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(5),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.statusAlerta,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppTheme.statusAlerta.withValues(alpha: 0.7),
                                                      blurRadius: 8,
                                                      spreadRadius: 2,
                                                    ),
                                                    const BoxShadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2)),
                                                  ],
                                                ),
                                                child: const Icon(Icons.location_pin, color: Colors.white, size: 22),
                                              ),
                                              Container(
                                                width: 4,
                                                height: 4,
                                                margin: const EdgeInsets.only(top: 1),
                                                decoration: const BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_direccionResuelta.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Punto: $_direccionResuelta',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5, fontStyle: FontStyle.italic),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: formSection),
                          const SizedBox(width: 18),
                          mapPreviewSection,
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          formSection,
                          const SizedBox(height: 16),
                          mapPreviewSection,
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),

                // Botones de Acción
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.statusCompletada,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      icon: _guardando
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add_location_alt, size: 18),
                      label: Text(
                        _guardando ? 'Guardando...' : '+ Agregar Parada a la Ruta',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: _guardando ? null : _guardarParada,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
