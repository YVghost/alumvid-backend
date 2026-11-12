import 'package:flutter/material.dart';

import '../../models/producto.dart';
import '../../services/api_service.dart';
import '../../shared/ui.dart';
import 'inventario_modulo.dart';

/// Alta o edición de producto del catálogo (solo administración).
class ProductoForm extends StatefulWidget {
  const ProductoForm({super.key, this.producto});
  final Producto? producto;

  @override
  State<ProductoForm> createState() => _ProductoFormState();
}

class _ProductoFormState extends State<ProductoForm> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.producto?.code ?? '');
  late final _name = TextEditingController(text: widget.producto?.name ?? '');
  late final _min = TextEditingController(text: widget.producto == null ? '5' : fmtNum(widget.producto!.minStock));
  late final _sup = TextEditingController(text: widget.producto?.supplier ?? '');
  late final _ext = TextEditingController(text: widget.producto?.externalCode ?? '');
  late final _desc = TextEditingController(text: widget.producto?.description ?? '');
  late String _categoria = categoriasProducto.contains(widget.producto?.category) ? widget.producto!.category : 'VIDRIO';
  late String _unidad = unidadesProducto.containsKey(widget.producto?.unit) ? widget.producto!.unit : 'UNIDAD';
  late bool _activo = widget.producto?.active ?? true;
  bool _guardando = false;

  bool get _editando => widget.producto != null;

  @override
  void dispose() {
    for (final c in [_code, _name, _min, _sup, _ext, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final data = {
      'code': _code.text.trim().toUpperCase(),
      'name': _name.text.trim(),
      'category': _categoria,
      'unit': _unidad,
      'minStock': double.parse(_min.text.replaceAll(',', '.')),
      // La ubicación física se gestiona en Bodega (espacios), no como texto libre.
      'location': widget.producto?.location ?? '',
      'supplier': _sup.text.trim(),
      'externalCode': _ext.text.trim(),
      'description': _desc.text.trim(),
      'active': _activo,
    };
    try {
      if (_editando) {
        await ApiService.actualizarProducto(widget.producto!.id, data);
      } else {
        await ApiService.crearProducto(data);
      }
      if (!mounted) return;
      avisoOk(context, _editando ? 'Producto actualizado' : 'Producto creado');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        avisoError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar producto' : 'Nuevo producto')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: Text(_editando ? 'Guardar cambios' : 'Crear producto'),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _code,
              enabled: !_editando,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Código *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
            ),
            gap,
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Mínimo 3 caracteres' : null,
            ),
            gap,
            DropdownButtonFormField<String>(
              initialValue: _categoria,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [for (final c in categoriasProducto) DropdownMenuItem(value: c, child: Text(humanizar(c)))],
              onChanged: (v) => setState(() => _categoria = v ?? _categoria),
            ),
            gap,
            DropdownButtonFormField<String>(
              initialValue: _unidad,
              decoration: const InputDecoration(labelText: 'Unidad de medida'),
              items: [for (final e in unidadesProducto.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: _editando ? null : (v) => setState(() => _unidad = v ?? _unidad),
            ),
            gap,
            TextFormField(
              controller: _min,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Stock mínimo *', helperText: 'Por debajo se avisa como "stock bajo"'),
              validator: (v) {
                final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                return n == null || n < 0 ? 'Número mayor o igual a 0' : null;
              },
            ),
            gap,
            TextFormField(controller: _sup, decoration: const InputDecoration(labelText: 'Proveedor')),
            gap,
            TextFormField(controller: _ext, decoration: const InputDecoration(labelText: 'Código del proveedor')),
            gap,
            TextFormField(controller: _desc, maxLines: 3, minLines: 2, decoration: const InputDecoration(labelText: 'Descripción')),
            if (_editando) ...[
              gap,
              Card(
                child: SwitchListTile(
                  title: const Text('Activo en el catálogo'),
                  subtitle: const Text('Los productos inactivos no se venden'),
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
