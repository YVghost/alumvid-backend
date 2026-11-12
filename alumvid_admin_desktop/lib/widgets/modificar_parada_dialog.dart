import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/despacho.dart';
import '../models/producto.dart';
import '../models/retazo_pieza.dart';
import '../models/ruta.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import 'map_picker_dialog.dart';

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
  final _cantidadCtrl = TextEditingController(text: '1');
  late final TextEditingController _observacionesCtrl;

  late double _lat;
  late double _lon;
  String _direccionResuelta = '';
  bool _ubicacionModificada = false;

  // Catálogos
  TipoEntregaMaterial _tipoEntrega = TipoEntregaMaterial.inventario;
  List<Producto> _productosInventario = [];
  Producto? _productoSeleccionado;

  List<ProductoRetazo> _productosRetazo = [];
  ProductoRetazo? _productoRetazoSeleccionado;
  List<PiezaRetazo> _piezasDisponibles = [];
  PiezaRetazo? _piezaSeleccionada;

  String? _initialProductId;
  String? _initialPieceId;

  // Estado de corte a medida
  bool _modoCorteActivo = false;
  bool _ejecutandoCorte = false;
  final _longitudCorteCtrl = TextEditingController();
  final _anchoCorteCtrl = TextEditingController();
  final _mermaCorteCtrl = TextEditingController(text: '0.00');
  PiezaRetazo? _piezaOrigenCorte;
  String? _mensajeCorteExitoso;

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

    if (rawComentarios.contains('[META:')) {
      final match = RegExp(r'\[META:([^\]]+)\]').firstMatch(rawComentarios);
      if (match != null) {
        final metaContent = match.group(1)!;
        for (final p in metaContent.split(';')) {
          final kv = p.split('=');
          if (kv.length == 2) {
            final k = kv[0].trim().toUpperCase();
            final v = kv[1].trim();
            if (k == 'PID') _initialProductId = v;
            if (k == 'QTY') _cantidadCtrl.text = v;
            if (k == 'PIECE') {
              _initialPieceId = v;
              _tipoEntrega = TipoEntregaMaterial.retazo;
            }
          }
        }
      }
    }

    _lat = widget.parada.latitud;
    _lon = widget.parada.longitud;
    _direccionResuelta = widget.parada.direccionTexto;

    _cargarCatalogos();
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

  Future<void> _cargarCatalogos() async {
    try {
      final resInv = await ApiService.obtenerProductos(size: 100);
      final List<Producto> prods = resInv['items'] as List<Producto>? ?? [];
      final retazos = await ApiService.obtenerProductosRetazos();

      if (mounted) {
        setState(() {
          _productosInventario = prods;
          _productosRetazo = retazos;
          if (prods.isNotEmpty) {
            _productoSeleccionado = prods.first;
          }
          if (retazos.isNotEmpty) {
            _productoRetazoSeleccionado = retazos.first;
          }
          if (_initialProductId != null) {
            final pFound = prods.where((p) => p.id == _initialProductId).firstOrNull;
            if (pFound != null) _productoSeleccionado = pFound;
            final rFound = retazos.where((r) => r.id == _initialProductId).firstOrNull;
            if (rFound != null) _productoRetazoSeleccionado = rFound;
          }
          _cargandoCatalogos = false;
        });

        if (_productoRetazoSeleccionado != null) {
          _cargarPiezasDeRetazo(_productoRetazoSeleccionado!.id);
        }
      }
    } catch (e) {
      debugPrint('Error al cargar catálogos: $e');
      if (mounted) setState(() => _cargandoCatalogos = false);
    }
  }

  Future<void> _cargarPiezasDeRetazo(String prodId) async {
    setState(() => _cargandoPiezas = true);
    try {
      final piezas = await ApiService.obtenerPiezasRetazo(prodId, state: 'DISPONIBLE');
      if (!mounted) return;
      setState(() {
        _piezasDisponibles = piezas;
        if (_initialPieceId != null) {
          final pFound = piezas.where((p) => p.id == _initialPieceId).firstOrNull;
          _piezaSeleccionada = pFound ?? (piezas.isNotEmpty ? piezas.first : null);
        } else {
          _piezaSeleccionada = piezas.isNotEmpty ? piezas.first : null;
        }
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
        reason: 'Corte operativo para despacho en ruta ${widget.ruta.codigoRuta}',
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
      barrierDismissible: false,
      builder: (_) => MapPickerDialog(
        initialLocation: LatLng(_lat, _lon),
        title: 'Actualizar Ubicación de Parada',
      ),
    );

    if (result != null) {
      setState(() {
        _lat = result.location.latitude;
        _lon = result.location.longitude;
        _direccionResuelta = result.address;
        _ubicacionModificada = true;
        if (result.address.isNotEmpty) {
          _direccionCtrl.text = result.address;
        }
      });
      if (mounted) {
        AppToast.info(context, 'Ubicación actualizada en el mapa');
      }
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    // Formatear qué se va a entregar con metadatos de integración física e-PoD
    String materialFinal = '';
    if (_tipoEntrega == TipoEntregaMaterial.retazo && _piezaSeleccionada != null && _productoRetazoSeleccionado != null) {
      materialFinal = 'Retazo: [${_productoRetazoSeleccionado!.code}] ${_productoRetazoSeleccionado!.name} (${_piezaSeleccionada!.dimensionesTexto})';
      if (_piezaSeleccionada!.location != null && _piezaSeleccionada!.location!.isNotEmpty) {
        materialFinal += ' - Ubic: ${_piezaSeleccionada!.location}';
      }
      if (_observacionesCtrl.text.trim().isNotEmpty) {
        materialFinal += ' - ${_observacionesCtrl.text.trim()}';
      }
      materialFinal += ' [META:PID=${_productoRetazoSeleccionado!.id};QTY=1;PIECE=${_piezaSeleccionada!.id}]';
    } else if (_tipoEntrega == TipoEntregaMaterial.inventario && _productoSeleccionado != null) {
      final cant = _cantidadCtrl.text.trim().isNotEmpty ? _cantidadCtrl.text.trim() : '1';
      materialFinal = '${_productoSeleccionado!.name} ($cant ${_productoSeleccionado!.unit})';
      if (_observacionesCtrl.text.trim().isNotEmpty) {
        materialFinal += ' - ${_observacionesCtrl.text.trim()}';
      }
      materialFinal += ' [META:PID=${_productoSeleccionado!.id};QTY=$cant]';
    } else if (_observacionesCtrl.text.trim().isNotEmpty) {
      materialFinal = _observacionesCtrl.text.trim();
    } else {
      materialFinal = widget.parada.comentarios ?? 'Material general';
    }

    try {
      await ApiService.modificarDestinoRuta(
        rutaId: widget.ruta.id,
        despachoId: widget.parada.id,
        cliente: _clienteCtrl.text.trim(),
        direccionTexto: _direccionCtrl.text.trim(),
        latitud: _lat,
        longitud: _lon,
        comentarios: materialFinal,
      );

      if (!mounted) return;
      AppToast.success(context, 'Parada actualizada correctamente');
      widget.onParadaModificada();
      Navigator.pop(context);
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
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF1E293B)),
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
                            color: const Color(0xFF1D72FE).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_location_alt_rounded, color: Color(0xFF38BDF8), size: 22),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Modificar Parada #${widget.parada.ordenParada}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(
                              'Ruta: ${widget.ruta.codigoRuta} • Modifique cliente, material/retazo o ubicación en mapa',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
                const Divider(color: Color(0xFF1E293B), height: 22),

                // Distribución en 2 Columnas idéntica a Agregar Parada
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 640;

                    // Columna Izquierda: Formulario y Material/Retazos
                    final formSection = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cliente y Razón Social
                        TextFormField(
                          controller: _clienteCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Cliente o Razón Social *',
                            hintText: 'Ej. Constructora Los Andes / Vidriería El Diamante',
                            prefixIcon: Icon(Icons.business_rounded, size: 18),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese el cliente o razón social' : null,
                        ),
                        const SizedBox(height: 12),

                        // Dirección de Entrega
                        TextFormField(
                          controller: _direccionCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Dirección de Entrega *',
                            hintText: 'Ej. Av. 6 de Diciembre y Orellana, Quito',
                            prefixIcon: Icon(Icons.home_rounded, size: 18),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese la dirección de entrega' : null,
                        ),
                        const SizedBox(height: 14),

                        // Bloque: Qué se va a entregar (Inventario y Retazos)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF090E1A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF1E293B)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.inventory_2_rounded, color: Color(0xFF38BDF8), size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'Qué se va a entregar (Inventario & Retazos)',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF38BDF8)),
                                      ),
                                    ],
                                  ),
                                  // Selector Modo: Inventario o Retazo
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

                              if (_cargandoCatalogos)
                                const Row(
                                  children: [
                                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                    SizedBox(width: 8),
                                    Text('Cargando catálogo...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                  ],
                                )
                              else if (_tipoEntrega == TipoEntregaMaterial.inventario) ...[
                                // Modo Inventario Estándar
                                DropdownButtonFormField<Producto>(
                                  initialValue: _productoSeleccionado,
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF101728),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: const InputDecoration(
                                    labelText: 'Seleccionar Producto de Bodega *',
                                    isDense: true,
                                    prefixIcon: Icon(Icons.category_rounded, size: 18),
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
                                      width: 120,
                                      child: TextFormField(
                                        controller: _cantidadCtrl,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                        decoration: InputDecoration(
                                          labelText: 'Cantidad *',
                                          suffixText: _productoSeleccionado?.unit ?? 'Unid',
                                          isDense: true,
                                          prefixIcon: const Icon(Icons.numbers_rounded, size: 16),
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
                                          hintText: 'Ej. Medidas especiales, corte requerido...',
                                          isDense: true,
                                          prefixIcon: Icon(Icons.edit_note_rounded, size: 18),
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
                                  dropdownColor: const Color(0xFF101728),
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
                                       dropdownColor: const Color(0xFF101728),
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
                                             dropdownColor: const Color(0xFF101728),
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

                    // Columna Derecha: Tarjeta de Mapa Interactivo "Punto de Entrega"
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
                                  Icon(Icons.location_on_rounded, size: 15, color: Color(0xFF38BDF8)),
                                  SizedBox(width: 5),
                                  Text(
                                    'Punto de Entrega',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF38BDF8)),
                                  ),
                                ],
                              ),
                              Text(
                                '${_lat.toStringAsFixed(4)}, ${_lon.toStringAsFixed(4)}',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontFamily: 'monospace'),
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
                                    color: _ubicacionModificada
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF1E293B),
                                    width: 1.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black45,
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
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
                                          key: ValueKey('dialog-map-mod-$_lat-$_lon'),
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
                                                  color: const Color(0xFFEF4444),
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(0xFFEF4444).withValues(alpha: 0.7),
                                                      blurRadius: 8,
                                                      spreadRadius: 2,
                                                    ),
                                                    const BoxShadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2)),
                                                  ],
                                                ),
                                                child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
                                              ),
                                              Container(
                                                width: 4,
                                                height: 4,
                                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // Botón overlay para abrir mapa completo
                                      Positioned(
                                        bottom: 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xEE090E1A),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF1E293B)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.open_in_full_rounded, size: 12, color: Color(0xFF38BDF8)),
                                              SizedBox(width: 4),
                                              Text('Ajustar en Mapa', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
                          const SizedBox(height: 6),
                          Text(
                            _direccionResuelta,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontStyle: FontStyle.italic),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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

                // Botones Cancelar / Guardar Cambios
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
                      label: const Text('Guardar Cambios', style: TextStyle(fontWeight: FontWeight.bold)),
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
