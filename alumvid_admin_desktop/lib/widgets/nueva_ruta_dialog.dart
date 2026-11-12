import 'package:flutter/material.dart';
import '../models/chofer.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class NuevaRutaDialog extends StatefulWidget {
  final List<Chofer> choferes;
  final VoidCallback onRutaCreada;

  const NuevaRutaDialog({
    super.key,
    required this.choferes,
    required this.onRutaCreada,
  });

  @override
  State<NuevaRutaDialog> createState() => _NuevaRutaDialogState();
}

class _NuevaRutaDialogState extends State<NuevaRutaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codigoRutaCtrl = TextEditingController(text: 'Ruta-${DateTime.now().hour}${DateTime.now().minute}');
  final _comentariosCtrl = TextEditingController();

  String? _choferSeleccionadoId;
  final List<Map<String, dynamic>> _destinos = [];
  bool _creando = false;

  @override
  void initState() {
    super.initState();
    if (widget.choferes.isNotEmpty) {
      _choferSeleccionadoId = widget.choferes.first.id;
    }
    // Agregar un primer destino predeterminado en Quito
    _destinos.add({
      'cliente': 'Vidriería El Diamante',
      'direccionTexto': 'Av. 6 de Diciembre y Orellana, Quito',
      'latitudDestino': -0.1985,
      'longitudDestino': -78.4850,
      'comentarios': 'Entrega de 5 planchas laminadas 6mm'
    });
  }

  void _agregarFilaDestino() {
    setState(() {
      _destinos.add({
        'cliente': 'Nuevo Cliente ${_destinos.length + 1}',
        'direccionTexto': 'Quito, Sector Norte',
        'latitudDestino': -0.1800 - (_destinos.length * 0.015),
        'longitudDestino': -78.4700 - (_destinos.length * 0.010),
        'comentarios': ''
      });
    });
  }

  Future<void> _crearRuta() async {
    if (!_formKey.currentState!.validate()) return;
    if (_choferSeleccionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione un chofer para la ruta')),
      );
      return;
    }
    if (_destinos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe agregar al menos una parada')),
      );
      return;
    }

    setState(() => _creando = true);

    try {
      await ApiService.crearRutaMultiDestino(
        codigoRuta: _codigoRutaCtrl.text.trim(),
        choferId: _choferSeleccionadoId!,
        comentarios: _comentariosCtrl.text.trim(),
        destinos: _destinos,
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onRutaCreada();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hoja de ruta creada exitosamente.'),
          backgroundColor: AppTheme.statusCompletada,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'),
          backgroundColor: AppTheme.statusAlerta,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.primaryLight),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.alt_route, color: AppTheme.primaryLight, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Planificar Ruta con Paradas',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppTheme.border, height: 20),

              // Campos principales: Código y Chofer
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codigoRutaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Código / Nombre de Ruta',
                        prefixIcon: Icon(Icons.tag, size: 18),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _choferSeleccionadoId,
                      decoration: const InputDecoration(
                        labelText: 'Chofer Asignado',
                        prefixIcon: Icon(Icons.person, size: 18),
                      ),
                      dropdownColor: AppTheme.surfaceCard,
                      items: widget.choferes.map((c) {
                        return DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.nombre} (${c.estadoDisponibilidad})', style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _choferSeleccionadoId = val;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Lista de Destinos / Paradas
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Paradas de Entrega (${_destinos.length}):',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16, color: AppTheme.primaryLight),
                    label: const Text('+ Agregar Parada', style: TextStyle(color: AppTheme.primaryLight, fontSize: 12)),
                    onPressed: _agregarFilaDestino,
                  ),
                ],
              ),
              const SizedBox(height: 6),

              Expanded(
                child: ListView.separated(
                  itemCount: _destinos.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _destinos[index];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161F30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: AppTheme.primary,
                                child: Text('${index + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: item['cliente'],
                                  decoration: const InputDecoration(
                                    labelText: 'Cliente',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  onChanged: (v) => item['cliente'] = v,
                                ),
                              ),
                              if (_destinos.length > 1) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.statusAlerta, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _destinos.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            initialValue: item['direccionTexto'],
                            decoration: const InputDecoration(
                              labelText: 'Dirección',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onChanged: (v) => item['direccionTexto'] = v,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _comentariosCtrl,
                decoration: const InputDecoration(
                  labelText: 'Instrucciones generales de la ruta',
                  hintText: 'Ej. Prioridad para obras con grúa en la mañana',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // Botones de pie
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                    icon: _creando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_creando ? 'Creando Ruta...' : 'Crear Hoja de Ruta'),
                    onPressed: _creando ? null : _crearRuta,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
