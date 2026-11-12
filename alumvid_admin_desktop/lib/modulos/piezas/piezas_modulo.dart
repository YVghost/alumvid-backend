import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_negocio.dart';
import '../../shared/adaptable.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import '../inventario/ficha_pieza.dart';

/// Buscador de piezas (retazos y unidades completas) en todos los materiales.
/// Responde "¿tengo un retazo que me sirva para esta medida y dónde está?".
class PiezasModulo extends StatefulWidget {
  const PiezasModulo({super.key, required this.permisos});
  final Permisos permisos;

  @override
  State<PiezasModulo> createState() => _PiezasModuloState();
}

class _PiezasModuloState extends State<PiezasModulo> {
  String _tipo = '';
  String _estado = 'DISPONIBLE';
  String _q = '';
  final _minimo = TextEditingController();
  Timer? _espera;
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _minimo.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _items.isEmpty;
      _error = null;
    });
    final min = double.tryParse(_minimo.text.replaceAll(',', '.'));
    try {
      final r = await Api.buscarPiezas(
        q: _q,
        tipo: _tipo,
        estado: _estado,
        minLargoM: _tipo == 'ALUMINIO' ? min : null,
        minAnchoCm: _tipo == 'VIDRIO' ? min : null,
      );
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _medidaCambio(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), _cargar);
  }

  Future<void> _abrir(Map<String, dynamic> p) async {
    final cambio = await abrirPanel<bool>(context, (_) => FichaPieza(piezaId: '${p['id']}', permisos: widget.permisos));
    if (cambio == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Piezas y retazos')),
      body: AnchoLegible(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: CampoBusqueda(
                hint: 'Material, código o ubicación',
                onChanged: (v) {
                  _q = v;
                  _cargar();
                },
              ),
            ),
            FiltrosChips<String>(
              opciones: const {'': 'Todos', 'ALUMINIO': 'Perfiles de aluminio', 'VIDRIO': 'Vidrios'},
              seleccion: _tipo,
              onSeleccion: (v) {
                setState(() {
                  _tipo = v;
                  _minimo.clear();
                });
                _cargar();
              },
            ),
            if (_tipo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: TextField(
                  controller: _minimo,
                  onChanged: _medidaCambio,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.straighten),
                    labelText: _tipo == 'ALUMINIO' ? 'Largo mínimo que necesito (m)' : 'Ancho mínimo que necesito (cm)',
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(child: Text('${_items.length} piezas', style: const TextStyle(color: AppColors.textMuted))),
                  DropdownButton<String>(
                    value: _estado,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'DISPONIBLE', child: Text('Disponibles')),
                      DropdownMenuItem(value: 'PREPARADO', child: Text('Reservadas')),
                      DropdownMenuItem(value: 'DESCARTADO', child: Text('Descartadas')),
                      DropdownMenuItem(value: '', child: Text('Todas')),
                    ],
                    onChanged: (v) {
                      setState(() => _estado = v ?? 'DISPONIBLE');
                      _cargar();
                    },
                  ),
                ],
              ),
            ),
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
          ? const VistaVacia(icono: Icons.content_cut, titulo: 'Sin piezas', mensaje: 'Prueba con una medida menor u otro material.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = _items[i];
                final completa = p['fullPiece'] == true;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: (completa ? AppColors.success : AppColors.violet).withValues(alpha: 0.16),
                      child: Icon(completa ? Icons.crop_square : Icons.content_cut, color: completa ? AppColors.success : AppColors.violet),
                    ),
                    title: Text(medidas(p['lengthM'], p['widthCm'], p['heightCm']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    subtitle: Text('${p['productName']}\n${aTexto(p['location'], 'Sin ubicación')} · ${fmtNum(aNum(p['percentage']))} % de una unidad',
                        style: const TextStyle(color: AppColors.textMuted)),
                    isThreeLine: true,
                    trailing: _estado == '' ? EstadoChip(aTexto(p['state'])) : const Icon(Icons.chevron_right),
                    onTap: () => _abrir(p),
                  ),
                );
              },
            ),
    );
  }
}
