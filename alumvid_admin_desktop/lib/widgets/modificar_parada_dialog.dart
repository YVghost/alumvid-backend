import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/despacho.dart';
import '../models/item_entrega_parada.dart';
import '../models/producto.dart';
import '../models/retazo_pieza.dart';
import '../models/ruta.dart';
import '../services/api_service.dart';
import '../services/location_search_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

enum TipoEntregaMaterial {
  inventario,
  retazo,
}

class ModificarParadaDialog extends StatefulWidget {
  final Ruta ruta;
  final Despacho parada;
  final VoidCallback onParadaModificada;

  const ModificarParadaDialog({
    super.key,
    required this.ruta,
    required this.parada,
    required this.onParadaModificada,
  });

  @override
  State<ModificarParadaDialog> createState() => _ModificarParadaDialogState();
}

class _ModificarParadaDialogState extends State<ModificarParadaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _clienteCtrl;
  late final TextEditingController _direccionCtrl;
  late final TextEditingController _observacionesCtrl;

  // Multi-item list
  final List<ItemEntregaParada> _itemsEntrega = [];

  // Controllers para agregar item actual
  final _cantidadInvCtrl = TextEditingController(text: '1');
  final _corteLongitudCtrl = TextEditingController();
  final _corteAnchoCtrl = TextEditingController();
  final _corteLargoCtrl = TextEditingController();
  bool _aplicarCorteRetazo = false;

  final MapController _mapController = MapController();
  late double _lat;
  late double _lon;
  String _direccionResuelta = '';
  bool _ubicacionModificada = false;
  bool _isResolvingAddress = false;

  // Catálogos
  TipoEntregaMaterial _tipoSubForm = TipoEntregaMaterial.inventario;
  List<Producto> _productosInventario = [];
  Producto? _productoSeleccionado;

  List<ProductoRetazo> _productosRetazo = [];
  ProductoRetazo? _productoRetazoSeleccionado;
  List<PiezaRetazo> _piezasDisponibles = [];
  PiezaRetazo? _piezaSeleccionada;

  bool _cargandoCatalogos = true;
  bool _cargandoPiezas = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _clienteCtrl = TextEditingController(text: widget.parada.cliente);
    _direccionCtrl = TextEditingController(text: widget.parada.direccionTexto);

    final rawComentarios = widget.parada.comentarios ?? '';
    final cleanComentarios = rawComentarios.replaceAll(RegExp(r'\s*\[META:[^\]]+\]'), '').trim();
    _observacionesCtrl = TextEditingController(text: cleanComentarios);

    // Cargar items existentes
    final parsedItems = ItemEntregaParada.parseFromComentarios(rawComentarios);
    _itemsEntrega.addAll(parsedItems);

    _lat = widget.parada.latitud;
    _lon = widget.parada.longitud;
    _direccionResuelta = widget.parada.direccionTexto;

    _cargarCatalogos();
  }

  @override
  void dispose() {
    _clienteCtrl.dispose();
    _direccionCtrl.dispose();
    _observacionesCtrl.dispose();
    _cantidadInvCtrl.dispose();
    _corteLongitudCtrl.dispose();
    _corteAnchoCtrl.dispose();
    _corteLargoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogos() async {
    try {
      final resInv = await ApiService.obtenerProductos(size: 100);
      final List<Producto> prods = resInv['items'] as List<Producto>? ?? [];
      final retazos = await ApiService.obtenerProductosRetazos();

      if (mounted) {
        setState(() {
          _productosInventario = prods;
          _productosRetazo = retazos;
          if (prods.isNotEmpty) _productoSeleccionado = prods.first;
          if (retazos.isNotEmpty) _productoRetazoSeleccionado = retazos.first;
          _cargandoCatalogos = false;
        });

        if (_productoRetazoSeleccionado != null) {
          _cargarPiezasDeRetazo(_productoRetazoSeleccionado!.id);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargandoCatalogos = false);
        AppToast.error(context, 'Error al cargar catálogos: $e');
      }
    }
  }

  Future<void> _cargarPiezasDeRetazo(String productId) async {
    setState(() => _cargandoPiezas = true);
    try {
      final piezas = await ApiService.obtenerPiezasRetazo(productId);
      if (mounted) {
        setState(() {
          _piezasDisponibles = piezas;
          _piezaSeleccionada = piezas.isNotEmpty ? piezas.first : null;
          _cargandoPiezas = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargandoPiezas = false);
      }
    }
  }

  Future<void> _actualizarUbicacionDesdeMapa(LatLng point) async {
    setState(() {
      _lat = point.latitude;
      _lon = point.longitude;
      _ubicacionModificada = true;
      _isResolvingAddress = true;
    });

    try {
      final addr = await LocationSearchService.reverseGeocode(point);
      if (mounted) {
        setState(() {
          _isResolvingAddress = false;
          if (addr.isNotEmpty) {
            _direccionResuelta = addr;
            _direccionCtrl.text = addr;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isResolvingAddress = false);
    }
  }

  Future<void> _abrirEnGoogleMaps() async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$_lat,$_lon');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error al abrir Google Maps: $e');
    }
  }

  void _agregarItemInventario() {
    if (_productoSeleccionado == null) {
      AppToast.error(context, 'Selecciona un producto');
      return;
    }
    final cant = double.tryParse(_cantidadInvCtrl.text.trim()) ?? 0.0;
    if (cant <= 0) {
      AppToast.error(context, 'Ingresa una cantidad mayor a 0');
      return;
    }
    if (cant > _productoSeleccionado!.stock) {
      AppToast.error(context, 'Stock insuficiente. Máximo disponible: ${_productoSeleccionado!.stock}');
      return;
    }

    setState(() {
      _itemsEntrega.add(ItemEntregaParada(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tipo: 'INVENTARIO',
        productoId: _productoSeleccionado!.id,
        productoNombre: _productoSeleccionado!.name,
        unidad: _productoSeleccionado!.unit,
        cantidad: cant,
        descripcionVisible: '${_productoSeleccionado!.name} ($cant ${_productoSeleccionado!.unit})',
      ));
      _cantidadInvCtrl.text = '1';
    });
    AppToast.success(context, 'Producto añadido a la lista de entrega');
  }

  void _agregarItemRetazo() {
    if (_piezaSeleccionada == null || _productoRetazoSeleccionado == null) {
      AppToast.error(context, 'Selecciona un retazo disponible');
      return;
    }

    final kind = _productoRetazoSeleccionado?.kind?.toUpperCase() ?? '';
    double? cutLen;
    double? cutWid;
    double? cutHei;

    if (_aplicarCorteRetazo) {
      if (kind == 'ALUMINIO') {
        cutLen = double.tryParse(_corteLongitudCtrl.text.trim());
        if (cutLen == null || cutLen <= 0) {
          AppToast.error(context, 'Ingresa una longitud de corte válida');
          return;
        }
        if (_piezaSeleccionada!.lengthM != null && cutLen > _piezaSeleccionada!.lengthM!) {
          AppToast.error(context, 'La longitud excede el tamaño del retazo (${_piezaSeleccionada!.lengthM}m)');
          return;
        }
      } else {
        cutWid = double.tryParse(_corteAnchoCtrl.text.trim());
        cutHei = double.tryParse(_corteLargoCtrl.text.trim());
        if (cutWid == null || cutWid <= 0 || cutHei == null || cutHei <= 0) {
          AppToast.error(context, 'Ingresa ancho y largo de corte válidos en cm');
          return;
        }
        if (_piezaSeleccionada!.widthCm != null && cutWid > _piezaSeleccionada!.widthCm!) {
          AppToast.error(context, 'El ancho excede el retazo (${_piezaSeleccionada!.widthCm}cm)');
          return;
        }
        if (_piezaSeleccionada!.heightCm != null && cutHei > _piezaSeleccionada!.heightCm!) {
          AppToast.error(context, 'El largo excede el retazo (${_piezaSeleccionada!.heightCm}cm)');
          return;
        }
      }
    }

    String desc = '${_productoRetazoSeleccionado!.name} - Retazo [${_piezaSeleccionada!.dimensionesTexto}]';
    if (_aplicarCorteRetazo) {
      if (kind == 'ALUMINIO') {
        desc += ' (Corte: ${cutLen}m)';
      } else {
        desc += ' (Corte: ${cutWid}x${cutHei}cm)';
      }
    }

    setState(() {
      _itemsEntrega.add(ItemEntregaParada(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tipo: 'RETAZO',
        productoId: _productoRetazoSeleccionado!.id,
        productoNombre: _productoRetazoSeleccionado!.name,
        unidad: 'PIEZA',
        cantidad: 1,
        piezaId: _piezaSeleccionada!.id,
        piezaCodigo: _piezaSeleccionada!.location,
        piezaOriginalLengthM: _piezaSeleccionada!.lengthM,
        piezaOriginalWidthCm: _piezaSeleccionada!.widthCm,
        piezaOriginalHeightCm: _piezaSeleccionada!.heightCm,
        corteLengthM: cutLen,
        corteWidthCm: cutWid,
        corteHeightCm: cutHei,
        descripcionVisible: desc,
      ));
      _corteLongitudCtrl.clear();
      _corteAnchoCtrl.clear();
      _corteLargoCtrl.clear();
      _aplicarCorteRetazo = false;
    });
    AppToast.success(context, 'Retazo añadido a la lista de entrega');
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    if (_itemsEntrega.isEmpty) {
      AppToast.error(context, 'Debe haber al menos 1 material (producto o retazo) para esta entrega.');
      return;
    }

    setState(() => _guardando = true);

    final resumenItems = _itemsEntrega.map((i) => i.descripcionVisible).join(', ');
    final metaTags = _itemsEntrega.map((i) => i.toMetaTag()).join(' ');
    final obs = _observacionesCtrl.text.trim();
    final comentariosFinal = obs.isNotEmpty ? '$resumenItems - $obs $metaTags' : '$resumenItems $metaTags';

    try {
      await ApiService.modificarDestinoRuta(
        rutaId: widget.ruta.id,
        despachoId: widget.parada.id,
        cliente: _clienteCtrl.text.trim(),
        direccionTexto: _direccionCtrl.text.trim(),
        latitud: _lat,
        longitud: _lon,
        comentarios: comentariosFinal.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onParadaModificada();
      AppToast.success(context, 'Parada modificada exitosamente con ${_itemsEntrega.length} items');
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      AppToast.error(context, 'Error al modificar parada: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF101728),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF1E293B)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabecera
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D72FE).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_location_alt_rounded, color: Color(0xFF38BDF8), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Modificar Parada #${widget.parada.ordenParada}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                            Text(
                              'Ruta: ${widget.ruta.codigoRuta} • Chofer: ${widget.ruta.choferNombre ?? "Sin asignar"}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Contenido en 2 Columnas: Izquierda (Formulario y Materiales), Derecha (Mapa Interactivo)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ==========================================
                      // COLUMNA IZQUIERDA: FORMULARIO Y MATERIALES
                      // ==========================================
                      Expanded(
                        flex: 6,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(right: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cliente y Dirección
                              TextFormField(
                                controller: _clienteCtrl,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  labelText: 'Nombre del Cliente / Receptor *',
                                  prefixIcon: Icon(Icons.person_rounded, size: 18),
                                ),
                                validator: (val) => (val == null || val.trim().isEmpty) ? 'Ingrese el cliente' : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _direccionCtrl,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'Dirección o Referencia *',
                                  prefixIcon: const Icon(Icons.location_on_rounded, size: 18),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 18),
                                    tooltip: 'Localizar dirección en el mapa',
                                    onPressed: () async {
                                      final query = _direccionCtrl.text.trim();
                                      if (query.isNotEmpty) {
                                        final results = await LocationSearchService.searchPlaces(query, center: LatLng(_lat, _lon));
                                        if (results.isNotEmpty && mounted) {
                                          _actualizarUbicacionDesdeMapa(results.first.location);
                                          _mapController.move(results.first.location, 15.0);
                                        }
                                      }
                                    },
                                  ),
                                ),
                                validator: (val) => (val == null || val.trim().isEmpty) ? 'Ingrese la dirección' : null,
                              ),
                              const SizedBox(height: 14),

                              // SECCIÓN: MATERIALES A ENTREGAR
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.inventory_2_rounded, size: 16, color: Color(0xFF38BDF8)),
                                      SizedBox(width: 8),
                                      Text(
                                        'Materiales a Entregar en esta Parada',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1D72FE).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_itemsEntrega.length} items asignados',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Lista de items asignados (Sin mensaje de advertencia irrelevante)
                              if (_itemsEntrega.isNotEmpty)
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _itemsEntrega.length,
                                  separatorBuilder: (_, index) => const SizedBox(height: 6),
                                  itemBuilder: (context, idx) {
                                    final it = _itemsEntrega[idx];
                                    final isInv = it.tipo == 'INVENTARIO';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0D1424),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isInv ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFF38BDF8).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isInv ? Icons.category_rounded : Icons.straighten_rounded,
                                            size: 15,
                                            color: isInv ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: (isInv ? const Color(0xFF10B981) : const Color(0xFF38BDF8)).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isInv ? 'INVENTARIO' : 'RETAZO',
                                              style: TextStyle(
                                                color: isInv ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              it.descripcionVisible,
                                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                                            tooltip: 'Quitar este material',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              setState(() => _itemsEntrega.removeAt(idx));
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              const SizedBox(height: 10),

                              // PANEL PARA AGREGAR NUEVO MATERIAL
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF090E1A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF1E293B)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        ChoiceChip(
                                          label: const Text('Producto Inventario', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          selected: _tipoSubForm == TipoEntregaMaterial.inventario,
                                          selectedColor: const Color(0xFF1D72FE),
                                          onSelected: (val) {
                                            if (val) setState(() => _tipoSubForm = TipoEntregaMaterial.inventario);
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ChoiceChip(
                                          label: const Text('Retazo / Corte Bodega', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          selected: _tipoSubForm == TipoEntregaMaterial.retazo,
                                          selectedColor: const Color(0xFF1D72FE),
                                          onSelected: (val) {
                                            if (val) setState(() => _tipoSubForm = TipoEntregaMaterial.retazo);
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),

                                    if (_cargandoCatalogos)
                                      const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                                    else if (_tipoSubForm == TipoEntregaMaterial.inventario) ...[
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 6,
                                            child: DropdownButtonFormField<Producto>(
                                              key: ValueKey('mod_prod_inv_${_productoSeleccionado?.id}'),
                                              initialValue: _productoSeleccionado,
                                              isExpanded: true,
                                              dropdownColor: AppTheme.surfaceCard,
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                              decoration: const InputDecoration(
                                                labelText: 'Producto',
                                                isDense: true,
                                                prefixIcon: Icon(Icons.widgets_outlined, size: 16),
                                              ),
                                              items: _productosInventario.map((p) {
                                                return DropdownMenuItem<Producto>(
                                                  value: p,
                                                  child: Text(
                                                    '${p.name} (Stock: ${p.stock} ${p.unit})',
                                                    style: const TextStyle(fontSize: 11),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                setState(() => _productoSeleccionado = val);
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 3,
                                            child: TextFormField(
                                              controller: _cantidadInvCtrl,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                              decoration: InputDecoration(
                                                labelText: 'Cant.',
                                                isDense: true,
                                                helperText: _productoSeleccionado != null ? 'Máx: ${_productoSeleccionado!.stock}' : null,
                                                helperStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF10B981),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            ),
                                            icon: const Icon(Icons.add_rounded, size: 14),
                                            label: const Text('Añadir', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                            onPressed: _agregarItemInventario,
                                          ),
                                        ],
                                      ),
                                    ] else ...[
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 5,
                                            child: DropdownButtonFormField<ProductoRetazo>(
                                              key: ValueKey('mod_retazo_prod_${_productoRetazoSeleccionado?.id}'),
                                              initialValue: _productoRetazoSeleccionado,
                                              isExpanded: true,
                                              dropdownColor: AppTheme.surfaceCard,
                                              style: const TextStyle(color: Colors.white, fontSize: 11),
                                              decoration: const InputDecoration(
                                                labelText: 'Material Retazo',
                                                isDense: true,
                                                prefixIcon: Icon(Icons.filter_none_rounded, size: 16),
                                              ),
                                              items: _productosRetazo.map((r) {
                                                return DropdownMenuItem<ProductoRetazo>(
                                                  value: r,
                                                  child: Text('${r.name} (${r.kind ?? "GENERAL"})', style: const TextStyle(fontSize: 11)),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                if (val != null) {
                                                  setState(() => _productoRetazoSeleccionado = val);
                                                  _cargarPiezasDeRetazo(val.id);
                                                }
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 6,
                                            child: _cargandoPiezas
                                                ? const Padding(padding: EdgeInsets.all(8), child: Center(child: LinearProgressIndicator()))
                                                : DropdownButtonFormField<PiezaRetazo>(
                                                    key: ValueKey('mod_pieza_${_piezaSeleccionada?.id}'),
                                                    initialValue: _piezaSeleccionada,
                                                    isExpanded: true,
                                                    dropdownColor: AppTheme.surfaceCard,
                                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                                    decoration: const InputDecoration(
                                                      labelText: 'Pieza Disponible',
                                                      isDense: true,
                                                      prefixIcon: Icon(Icons.straighten_rounded, size: 16),
                                                    ),
                                                    items: _piezasDisponibles.map((p) {
                                                      final loc = p.location != null && p.location!.isNotEmpty ? ' (${p.location})' : '';
                                                      return DropdownMenuItem<PiezaRetazo>(
                                                        value: p,
                                                        child: Text(
                                                          '${p.dimensionesTexto}$loc',
                                                          style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8)),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      );
                                                    }).toList(),
                                                    onChanged: (val) {
                                                      setState(() => _piezaSeleccionada = val);
                                                    },
                                                  ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: _aplicarCorteRetazo,
                                            onChanged: (val) => setState(() => _aplicarCorteRetazo = val ?? false),
                                          ),
                                          const Text('Realizar corte a medida de esta pieza', style: TextStyle(color: Colors.white, fontSize: 11)),
                                        ],
                                      ),
                                      if (_aplicarCorteRetazo) ...[
                                        if ((_productoRetazoSeleccionado?.kind?.toUpperCase() ?? '') == 'ALUMINIO')
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _corteLongitudCtrl,
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                                  decoration: InputDecoration(
                                                    labelText: 'Longitud corte (m)',
                                                    isDense: true,
                                                    helperText: _piezaSeleccionada?.lengthM != null ? 'Máx: ${_piezaSeleccionada!.lengthM}m' : null,
                                                    helperStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _corteAnchoCtrl,
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                                  decoration: InputDecoration(
                                                    labelText: 'Ancho (cm)',
                                                    isDense: true,
                                                    helperText: _piezaSeleccionada?.widthCm != null ? 'Máx: ${_piezaSeleccionada!.widthCm}cm' : null,
                                                    helperStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _corteLargoCtrl,
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                                  decoration: InputDecoration(
                                                    labelText: 'Largo (cm)',
                                                    isDense: true,
                                                    helperText: _piezaSeleccionada?.heightCm != null ? 'Máx: ${_piezaSeleccionada!.heightCm}cm' : null,
                                                    helperStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        const SizedBox(height: 6),
                                      ],
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF10B981),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          icon: const Icon(Icons.add_rounded, size: 14),
                                          label: const Text('Añadir Retazo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          onPressed: _agregarItemRetazo,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _observacionesCtrl,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: const InputDecoration(
                                  labelText: 'Observaciones de entrega (Opcional)',
                                  hintText: 'Ej. Entregar en portería, llamar antes de llegar',
                                  isDense: true,
                                  prefixIcon: Icon(Icons.comment_outlined, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Separador vertical
                      Container(width: 1, color: const Color(0xFF1E293B)),
                      const SizedBox(width: 14),

                      // ==========================================
                      // COLUMNA DERECHA: MAPA INTERACTIVO DIRECTO
                      // ==========================================
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.map_rounded, size: 16, color: Color(0xFF38BDF8)),
                                    SizedBox(width: 6),
                                    Text('Ubicación en el Mapa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                InkWell(
                                  onTap: _abrirEnGoogleMaps,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF334155)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.open_in_new_rounded, size: 12, color: Color(0xFF38BDF8)),
                                        SizedBox(width: 4),
                                        Text('Google Maps', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF090E1A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF1E293B)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.touch_app_rounded, size: 14, color: Color(0xFF38BDF8)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _isResolvingAddress
                                          ? 'Obteniendo dirección...'
                                          : (_ubicacionModificada
                                              ? 'Nueva ubicación: $_direccionResuelta'
                                              : 'Ubicación actual: $_direccionResuelta (Haz clic para cambiar)'),
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Mapa Interactivo con selección directa por clic
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFF1E293B)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: FlutterMap(
                                    mapController: _mapController,
                                    options: MapOptions(
                                      initialCenter: LatLng(_lat, _lon),
                                      initialZoom: 15.0,
                                      onTap: (tapPosition, point) => _actualizarUbicacionDesdeMapa(point),
                                    ),
                                    children: [
                                      TileLayer(
                                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                        userAgentPackageName: 'com.alumvid.admin',
                                      ),
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: LatLng(_lat, _lon),
                                            width: 38,
                                            height: 38,
                                            child: const Icon(
                                              Icons.location_on,
                                              color: Color(0xFFEF4444),
                                              size: 38,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Botones Cancelar y Guardar Cambios
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D72FE),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _guardando
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        _guardando ? 'Guardando Cambios...' : 'Guardar Cambios (${_itemsEntrega.length} items)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _guardando ? null : _guardarCambios,
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
