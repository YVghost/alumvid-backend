import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/despacho.dart';
import '../models/ruta.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import 'map_picker_dialog.dart';

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
  late final TextEditingController _comentariosCtrl;

  late double _latitud;
  late double _longitud;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _clienteCtrl = TextEditingController(text: widget.parada.cliente);
    _direccionCtrl = TextEditingController(text: widget.parada.direccionTexto);
    _comentariosCtrl = TextEditingController(text: widget.parada.comentarios ?? '');
    _latitud = widget.parada.latitud;
    _longitud = widget.parada.longitud;
  }

  @override
  void dispose() {
    _clienteCtrl.dispose();
    _direccionCtrl.dispose();
    _comentariosCtrl.dispose();
    super.dispose();
  }

  Future<void> _abrirMapPicker() async {
    final result = await showDialog<MapPickerResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MapPickerDialog(
        initialLocation: LatLng(_latitud, _longitud),
        title: 'Actualizar Ubicación de Entrega',
      ),
    );

    if (result != null) {
      setState(() {
        _latitud = result.location.latitude;
        _longitud = result.location.longitude;
        if (result.address.isNotEmpty) {
          _direccionCtrl.text = result.address;
        }
      });
      if (mounted) {
        AppToast.info(context, 'Coordenadas y dirección actualizadas desde el mapa');
      }
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    final cliente = _clienteCtrl.text.trim();
    final direccion = _direccionCtrl.text.trim();
    final comentarios = _comentariosCtrl.text.trim();

    setState(() => _guardando = true);
    try {
      await ApiService.modificarDestinoRuta(
        rutaId: widget.ruta.id,
        despachoId: widget.parada.id,
        cliente: cliente,
        direccionTexto: direccion,
        latitud: _latitud,
        longitud: _longitud,
        comentarios: comentarios.isEmpty ? null : comentarios,
      );

      if (!mounted) return;
      AppToast.success(context, 'Parada #$cliente actualizada correctamente');
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Modificar Parada #${widget.parada.ordenParada}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                              ),
                              Text(
                                'Ruta: ${widget.ruta.codigoRuta}',
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
                  const SizedBox(height: 18),

                  // Campo: Nombre del Cliente
                  const Text('Nombre del Cliente', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _clienteCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF090E1A),
                      hintText: 'Ej. Juan Pérez / Empresa XYZ',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1D72FE)),
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese el nombre del cliente' : null,
                  ),
                  const SizedBox(height: 14),

                  // Campo: Dirección de Entrega
                  const Text('Dirección de Entrega', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _direccionCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 2,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF090E1A),
                      hintText: 'Calle principal y secundaria, numeración...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1D72FE)),
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese la dirección de entrega' : null,
                  ),
                  const SizedBox(height: 14),

                  // Selector de Coordenadas con Botón de Mapa
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090E1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.pin_drop_rounded, color: Color(0xFF38BDF8), size: 20),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Coordenadas GPS', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                Text(
                                  '${_latitud.toStringAsFixed(5)}, ${_longitud.toStringAsFixed(5)}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E293B),
                            foregroundColor: const Color(0xFF38BDF8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.map_rounded, size: 16),
                          label: const Text('Elegir en Mapa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: _abrirMapPicker,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Campo: Material / Comentarios
                  const Text('Material / Comentarios Adicionales', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _comentariosCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 2,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF090E1A),
                      hintText: 'Ej. Perfil Aluminio Pesado 3x1 (6 METROS)',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1D72FE)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Botones Guardar / Cancelar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                          side: const BorderSide(color: Color(0xFF1E293B)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1D72FE),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        onPressed: _guardando ? null : _guardarCambios,
                        child: _guardando
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Guardar Cambios', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
