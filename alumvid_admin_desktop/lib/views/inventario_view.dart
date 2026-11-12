import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/movimiento.dart';
import '../models/producto.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auditoria_inventario_dialog.dart';

class InventarioView extends StatefulWidget {
  const InventarioView({super.key});

  @override
  State<InventarioView> createState() => _InventarioViewState();
}

class _InventarioViewState extends State<InventarioView> {
  final _searchCtrl = TextEditingController();
  String _categoriaSeleccionada = '';
  bool _lowStock = false;
  bool _includeInactive = false;
  DateTimeRange _rangoInventario = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  void _abrirAuditoriaInventario() {
    showDialog(
      context: context,
      builder: (_) => AuditoriaInventarioDialog(
        rangoInicial: _rangoInventario,
        onRangoCambiado: (nuevo) => setState(() => _rangoInventario = nuevo),
      ),
    );
  }

  List<Producto> _productos = [];
  int _totalProductos = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  Future<void> _cargarProductos() async {
    setState(() => _cargando = true);
    try {
      final res = await ApiService.obtenerProductos(
        q: _searchCtrl.text.trim(),
        category: _categoriaSeleccionada,
        lowStock: _lowStock,
        includeInactive: _includeInactive,
        page: 0,
        size: 100,
      );
      if (!mounted) return;
      setState(() {
        _productos = res['items'] as List<Producto>;
        _totalProductos = res['total'] as int;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar inventario: $e'), backgroundColor: AppTheme.statusAlerta),
      );
    }
  }

  void _abrirModalProducto([Producto? prod]) {
    final isEditing = prod != null;
    final codeCtrl = TextEditingController(text: prod?.code ?? '');
    final nameCtrl = TextEditingController(text: prod?.name ?? '');
    String categoria = prod?.category ?? 'VIDRIO';
    String unit = prod?.unit ?? 'UNIDAD';
    final minStockCtrl = TextEditingController(text: prod != null ? prod.minStock.toString() : '5');
    final locationCtrl = TextEditingController(text: prod?.location ?? '');
    final supplierCtrl = TextEditingController(text: prod?.supplier ?? '');
    final extCodeCtrl = TextEditingController(text: prod?.externalCode ?? '');
    final descCtrl = TextEditingController(text: prod?.description ?? '');
    bool activo = prod?.active ?? true;

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => Dialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppTheme.border)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 580),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Editar Producto: ${prod.code}' : 'Nuevo Producto en Bodega',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const Divider(color: AppTheme.border, height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: codeCtrl,
                            enabled: !isEditing, // Código inmutable
                            decoration: const InputDecoration(labelText: 'Código / SKU', hintText: 'Ej. VID-CL-4MM'),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(labelText: 'Nombre Comercial', hintText: 'Ej. Vidrio Claro 4mm'),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: categoria,
                            decoration: const InputDecoration(labelText: 'Categoría'),
                            dropdownColor: AppTheme.surfaceCard,
                            items: const [
                              DropdownMenuItem(value: 'VIDRIO', child: Text('VIDRIO')),
                              DropdownMenuItem(value: 'ALUMINIO', child: Text('ALUMINIO')),
                              DropdownMenuItem(value: 'ACCESORIOS', child: Text('ACCESORIOS')),
                              DropdownMenuItem(value: 'VYNIL', child: Text('VYNIL')),
                              DropdownMenuItem(value: 'ACRILICO', child: Text('ACRILICO')),
                              DropdownMenuItem(value: 'ACERO INOXIDABLE', child: Text('ACERO INOXIDABLE')),
                            ],
                            onChanged: (val) => setDState(() => categoria = val ?? 'VIDRIO'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: unit,
                            decoration: const InputDecoration(labelText: 'Unidad de Medida'),
                            dropdownColor: AppTheme.surfaceCard,
                            items: const [
                              DropdownMenuItem(value: 'UNIDAD', child: Text('UNIDAD')),
                              DropdownMenuItem(value: 'METRO', child: Text('METRO LINEAL (m)')),
                              DropdownMenuItem(value: 'METRO_CUADRADO', child: Text('METRO CUADRADO (m²)')),
                              DropdownMenuItem(value: 'ROLLO', child: Text('ROLLO')),
                              DropdownMenuItem(value: 'KILOGRAMO', child: Text('KILOGRAMO (kg)')),
                              DropdownMenuItem(value: 'LITRO', child: Text('LITRO (L)')),
                            ],
                            onChanged: (val) => setDState(() => unit = val ?? 'UNIDAD'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: minStockCtrl,
                            decoration: const InputDecoration(labelText: 'Stock Mínimo de Alerta'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) => v == null || double.tryParse(v) == null ? 'Número válido requerido' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: locationCtrl,
                            decoration: const InputDecoration(labelText: 'Ubicación en Bodega', hintText: 'Caballete A-1'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: supplierCtrl,
                            decoration: const InputDecoration(labelText: 'Proveedor', hintText: 'Distribuidora'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: extCodeCtrl,
                            decoration: const InputDecoration(labelText: 'Código Externo', hintText: 'Ref de fábrica'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Descripción Técnica y Observaciones de Retazos / Cortes',
                        hintText: 'Especificaciones de dimensiones, tolerancia y retazos...',
                      ),
                      maxLines: 2,
                    ),

                    if (isEditing) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Producto Activo en Catálogo', style: TextStyle(fontSize: 13)),
                        value: activo,
                        activeThumbColor: AppTheme.primaryLight,
                        onChanged: (val) => setDState(() => activo = val),
                      ),
                    ],

                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted))),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            final data = {
                              'code': codeCtrl.text.trim().toUpperCase(),
                              'name': nameCtrl.text.trim(),
                              'category': categoria,
                              'unit': unit,
                              'minStock': double.parse(minStockCtrl.text.trim()),
                              'location': locationCtrl.text.trim(),
                              'supplier': supplierCtrl.text.trim(),
                              'externalCode': extCodeCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                              'active': activo,
                            };

                            try {
                              if (isEditing) {
                                await ApiService.actualizarProducto(prod.id, data);
                              } else {
                                await ApiService.crearProducto(data);
                              }
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              _cargarProductos();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isEditing ? 'Producto actualizado' : 'Producto creado con éxito'),
                                  backgroundColor: AppTheme.statusCompletada,
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: AppTheme.statusAlerta),
                              );
                            }
                          },
                          child: Text(isEditing ? 'Guardar Cambios' : 'Crear Producto'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _abrirModalMovimiento(Producto prod) {
    String tipo = 'INGRESO';
    final cantCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Row(
            children: [
              const Icon(Icons.sync_alt, color: AppTheme.primaryLight, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Movimiento: ${prod.name} (${prod.code})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo Actual: ${prod.stock} ${prod.unit}',
                  style: const TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo de Movimiento'),
                  dropdownColor: AppTheme.surfaceCard,
                  items: const [
                    DropdownMenuItem(value: 'INGRESO', child: Text('INGRESO (Entrada por compra / recepción)')),
                    DropdownMenuItem(value: 'SALIDA', child: Text('SALIDA (Despacho / Consumo de corte)')),
                    DropdownMenuItem(value: 'AJUSTE', child: Text('AJUSTE (Ajuste por conteo físico / retazo)')),
                  ],
                  onChanged: (val) => setDState(() => tipo = val ?? 'INGRESO'),
                ),
                const SizedBox(height: 10),

                TextFormField(
                  controller: cantCtrl,
                  decoration: InputDecoration(
                    labelText: tipo == 'AJUSTE' ? 'Nuevo Saldo Total Contado' : 'Cantidad a Mover',
                    hintText: 'Ej. 10.5',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || double.tryParse(v) == null) return 'Cantidad inválida';
                    if (tipo != 'AJUSTE' && double.parse(v) <= 0) return 'Debe ser mayor a 0';
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                TextFormField(
                  controller: motivoCtrl,
                  decoration: const InputDecoration(labelText: 'Motivo del Movimiento', hintText: 'Ej. Corte para ventana / Carga inicial'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese un motivo' : null,
                ),
                const SizedBox(height: 10),

                TextFormField(
                  controller: refCtrl,
                  decoration: const InputDecoration(labelText: 'Referencia / Documento', hintText: 'Ej. Factura 123 o Pedido RUTA-01'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted))),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ApiService.registrarMovimiento(
                    prod.id,
                    type: tipo,
                    quantity: double.parse(cantCtrl.text.trim()),
                    reason: motivoCtrl.text.trim(),
                    reference: refCtrl.text.trim(),
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  _cargarProductos();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Movimiento registrado exitosamente'), backgroundColor: AppTheme.statusCompletada),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: AppTheme.statusAlerta),
                  );
                }
              },
              child: const Text('Registrar Movimiento'),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirHistorialMovimientos(Producto prod) async {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<List<MovimientoInventario>>(
        future: ApiService.obtenerMovimientos(prod.id),
        builder: (context, snapshot) {
          final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text('Historial de Movimientos — ${prod.name}'),
            content: SizedBox(
              width: 550,
              height: 400,
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : (snapshot.data == null || snapshot.data!.isEmpty)
                      ? const Center(child: Text('Sin movimientos registrados aún.', style: TextStyle(color: AppTheme.textMuted)))
                      : ListView.separated(
                          itemCount: snapshot.data!.length,
                          separatorBuilder: (c, i) => const Divider(color: AppTheme.border, height: 1),
                          itemBuilder: (context, index) {
                            final m = snapshot.data![index];
                            final color = m.type == 'INGRESO'
                                ? AppTheme.statusCompletada
                                : m.type == 'SALIDA'
                                    ? AppTheme.statusAlerta
                                    : AppTheme.statusEnCurso;

                            return ListTile(
                              dense: true,
                              leading: Icon(
                                m.type == 'INGRESO' ? Icons.add_circle : m.type == 'SALIDA' ? Icons.remove_circle : Icons.tune,
                                color: color,
                              ),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${m.type}: ${m.delta > 0 ? "+" : ""}${m.delta} ${prod.unit}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                                  Text('Saldo: ${m.stockAfter}', style: const TextStyle(color: AppTheme.primaryLight, fontSize: 11)),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.reason, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  Text(
                                    '${m.occurredAt != null ? dateFormat.format(m.occurredAt!) : ""} • Por: ${m.actorName}',
                                    style: const TextStyle(color: AppTheme.textDim, fontSize: 10),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Control de Inventario y Bodega', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text('Catálogo de materiales, existencias y movimientos auditados ($_totalProductos productos)', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.primaryLight),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.history_edu, size: 16, color: AppTheme.primaryLight),
                    label: const Text('Auditoría e Histórico (Kardex)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _abrirAuditoriaInventario,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppTheme.primaryLight),
                    tooltip: 'Actualizar catálogo',
                    onPressed: _cargarProductos,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('+ Nuevo Producto', style: TextStyle(fontSize: 12)),
                    onPressed: () => _abrirModalProducto(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Barra de Filtros
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      labelText: 'Buscar producto',
                      hintText: 'Código o nombre...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      suffixIcon: IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); _cargarProductos(); }),
                    ),
                    onSubmitted: (_) => _cargarProductos(),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    initialValue: _categoriaSeleccionada,
                    decoration: const InputDecoration(labelText: 'Categoría', isDense: true),
                    dropdownColor: AppTheme.surfaceCard,
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Todas')),
                      DropdownMenuItem(value: 'VIDRIO', child: Text('VIDRIO')),
                      DropdownMenuItem(value: 'ALUMINIO', child: Text('ALUMINIO')),
                      DropdownMenuItem(value: 'ACCESORIOS', child: Text('ACCESORIOS')),
                      DropdownMenuItem(value: 'VYNIL', child: Text('VYNIL')),
                      DropdownMenuItem(value: 'ACRILICO', child: Text('ACRILICO')),
                    ],
                    onChanged: (val) {
                      setState(() => _categoriaSeleccionada = val ?? '');
                      _cargarProductos();
                    },
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _lowStock,
                      activeColor: AppTheme.statusAlerta,
                      onChanged: (v) {
                        setState(() => _lowStock = v ?? false);
                        _cargarProductos();
                      },
                    ),
                    const Text('Solo Bajo Stock', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _includeInactive,
                      onChanged: (v) {
                        setState(() => _includeInactive = v ?? false);
                        _cargarProductos();
                      },
                    ),
                    const Text('Incluir Inactivos', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryLight,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: _cargarProductos,
                  child: const Text('Filtrar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tabla o Lista de Productos
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _productos.isEmpty
                    ? const Center(child: Text('No se encontraron productos en bodega', style: TextStyle(color: AppTheme.textMuted)))
                    : ListView.separated(
                        itemCount: _productos.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final p = _productos[index];
                          Color stockColor = AppTheme.statusCompletada;
                          String stockLabel = 'NORMAL';
                          if (p.isAgotado) {
                            stockColor = AppTheme.statusAlerta;
                            stockLabel = 'AGOTADO';
                          } else if (p.isStockBajo) {
                            stockColor = AppTheme.statusEnCurso;
                            stockLabel = 'BAJO STOCK';
                          }

                          return Card(
                            margin: EdgeInsets.zero,
                            color: const Color(0xFF161F30),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // SKU y Categoría
                                  SizedBox(
                                    width: 140,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: AppTheme.primaryLight, fontSize: 13)),
                                        const SizedBox(height: 3),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(4)),
                                          child: Text(p.category, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Nombre y Descripción
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                                        if (p.description.isNotEmpty)
                                          Text(p.description, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        Text('Ubicación: ${p.location.isEmpty ? "—" : p.location}', style: const TextStyle(color: AppTheme.textDim, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Stock
                                  SizedBox(
                                    width: 120,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${p.stock} ${p.unit}', style: TextStyle(color: stockColor, fontWeight: FontWeight.bold, fontSize: 13)),
                                        Text('Mín: ${p.minStock} • $stockLabel', style: TextStyle(color: stockColor, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Botones de acción
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 18, color: AppTheme.primaryLight),
                                        tooltip: 'Editar producto',
                                        onPressed: () => _abrirModalProducto(p),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.sync_alt, size: 18, color: AppTheme.statusCompletada),
                                        tooltip: '+ Registrar Movimiento',
                                        onPressed: () => _abrirModalMovimiento(p),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.history, size: 18, color: AppTheme.textMuted),
                                        tooltip: 'Ver Historial de Movimientos',
                                        onPressed: () => _abrirHistorialMovimientos(p),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
