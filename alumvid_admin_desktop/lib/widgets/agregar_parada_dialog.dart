import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/producto.dart';
import '../models/ruta.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import 'map_picker_dialog.dart';

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

  List<Producto> _productosInventario = [];
  Producto? _productoSeleccionado;
  bool _cargandoProductos = true;
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
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    try {
      final res = await ApiService.obtenerProductos(size: 100);
      final List<Producto> prods = res['items'] as List<Producto>? ?? [];
      if (mounted) {
        setState(() {
          _productosInventario = prods;
          if (prods.isNotEmpty) {
            _productoSeleccionado = prods.first;
          }
          _cargandoProductos = false;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar productos de inventario: $e');
      if (mounted) setState(() => _cargandoProductos = false);
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

    // Formatear qué se va a entregar a partir del producto de inventario
    String queSeEntrega = '';
    if (_productoSeleccionado != null) {
      final cant = _cantidadCtrl.text.trim().isNotEmpty ? _cantidadCtrl.text.trim() : '1';
      queSeEntrega = '${_productoSeleccionado!.name} ($cant ${_productoSeleccionado!.unit})';
      if (_observacionesCtrl.text.trim().isNotEmpty) {
        queSeEntrega += ' - ${_observacionesCtrl.text.trim()}';
      }
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

                        // Qué se va a entregar (Selector desplegable de Inventario)
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
                              const Row(
                                children: [
                                  Icon(Icons.inventory_2, color: AppTheme.primaryLight, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'Qué se va a entregar (Catálogo de Inventario y Bodega)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryLight),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (_cargandoProductos)
                                const Row(
                                  children: [
                                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                    SizedBox(width: 8),
                                    Text('Cargando catálogo de productos...', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                                  ],
                                )
                              else if (_productosInventario.isEmpty)
                                const Text(
                                  'No hay productos registrados en bodega. Ingrese una descripción manual abajo.',
                                  style: TextStyle(color: AppTheme.statusAlerta, fontSize: 11),
                                )
                              else
                                DropdownButtonFormField<Producto>(
                                  initialValue: _productoSeleccionado,
                                  isExpanded: true,
                                  dropdownColor: AppTheme.surfaceCard,
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
