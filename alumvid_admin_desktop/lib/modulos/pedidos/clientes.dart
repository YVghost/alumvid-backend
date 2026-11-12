import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_negocio.dart';
import '../../shared/adaptable.dart';
import '../../shared/identificacion.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';

/// Catálogo de clientes (administración y ventas).
class ClientesLista extends StatefulWidget {
  const ClientesLista({super.key, required this.permisos});
  final Permisos permisos;

  @override
  State<ClientesLista> createState() => _ClientesListaState();
}

class _ClientesListaState extends State<ClientesLista> with AutomaticKeepAliveClientMixin {
  String _q = '';
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _items.isEmpty;
      _error = null;
    });
    try {
      final r = await Api.clientes(q: _q, inactivos: true);
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _form([Map<String, dynamic>? c]) async {
    final ok = await abrirPanel<Map<String, dynamic>>(context, (_) => ClienteForm(cliente: c));
    if (ok != null) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nuevo-cliente',
        onPressed: () => _form(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Cliente'),
      ),
      body: AnchoLegible(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: CampoBusqueda(
                hint: 'Nombre, cédula/RUC o teléfono',
                onChanged: (v) {
                  _q = v;
                  _cargar();
                },
              ),
            ),
            Expanded(
              child: _cargando
                  ? const CargandoLista()
                  : _error != null
                  ? VistaError(mensaje: _error!, onReintentar: _cargar)
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: _items.isEmpty
                          ? const VistaVacia(icono: Icons.people_outline, titulo: 'Sin clientes')
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final c = _items[i];
                                final activo = c['active'] != false;
                                final ident = aTexto(c['identification']);
                                final info = ident.isEmpty ? null : analizarIdentificacion(ident);
                                final datosInvalidos = (info != null && !info.valida) ||
                                    normalizarTelefono(aTexto(c['phone'])) == null;
                                return Card(
                                  child: ListTile(
                                    leading: AvatarIniciales(aTexto(c['name'], '?'), color: activo ? null : AppColors.neutral),
                                    title: Text(aTexto(c['name'])),
                                    subtitle: Text(
                                      [
                                        if (ident.isNotEmpty) info!.valida ? '$ident · ${info.mensaje}' : ident,
                                        aTexto(c['phone']),
                                        aTexto(c['address']),
                                      ].where((x) => x.isNotEmpty).join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AppColors.textMuted),
                                    ),
                                    trailing: datosInvalidos
                                        ? const EstadoChip('', texto: 'Datos inválidos', color: AppColors.danger)
                                        : activo
                                        ? const Icon(Icons.edit_outlined)
                                        : const EstadoChip('INACTIVO', texto: 'Inactivo'),
                                    onTap: () => _form(c),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alta o edición de cliente. Devuelve el cliente guardado.
class ClienteForm extends StatefulWidget {
  const ClienteForm({super.key, this.cliente});
  final Map<String, dynamic>? cliente;

  @override
  State<ClienteForm> createState() => _ClienteFormState();
}

class _ClienteFormState extends State<ClienteForm> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: aTexto(widget.cliente?['name']));
  late final _ident = TextEditingController(text: aTexto(widget.cliente?['identification']));
  late final _tel = TextEditingController(text: aTexto(widget.cliente?['phone']));
  late final _email = TextEditingController(text: aTexto(widget.cliente?['email']));
  late final _dir = TextEditingController(text: aTexto(widget.cliente?['address']));
  late bool _activo = widget.cliente?['active'] != false;
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_nombre, _ident, _tel, _email, _dir]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final r = await Api.guardarCliente(widget.cliente == null ? null : '${widget.cliente!['id']}', {
        'name': _nombre.text.trim(),
        'identification': _ident.text.trim(),
        'phone': normalizarTelefono(_tel.text) ?? _tel.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'address': _dir.text.trim(),
        'active': _activo,
      });
      if (!mounted) return;
      avisoOk(context, widget.cliente == null ? 'Cliente registrado' : 'Cliente actualizado');
      Navigator.pop(context, Map<String, dynamic>.from(r as Map));
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
      appBar: AppBar(title: Text(widget.cliente == null ? 'Nuevo cliente' : 'Editar cliente')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: Text(widget.cliente == null ? 'Registrar cliente' : 'Guardar cambios'),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre o razón social *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
            ),
            gap,
            TextFormField(
              controller: _ident,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13)],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Cédula o RUC',
                helperText: _ident.text.isEmpty
                    ? 'Opcional. Consumidor final: 9999999999999'
                    : analizarIdentificacion(_ident.text).valida
                    ? analizarIdentificacion(_ident.text).mensaje
                    : null,
                helperStyle: const TextStyle(color: AppColors.success),
              ),
              validator: (v) => validarIdentificacion(v, obligatorio: false),
            ),
            gap,
            TextFormField(
              controller: _tel,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(16)],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(labelText: 'Teléfono', helperText: 'Celular 09XXXXXXXX o fijo 02XXXXXXX'),
              validator: validarTelefono,
            ),
            gap,
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo'),
              validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim()) ? null : 'Correo no válido',
            ),
            gap,
            TextFormField(controller: _dir, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Dirección')),
            if (widget.cliente != null) ...[
              gap,
              Card(
                child: SwitchListTile(
                  title: const Text('Cliente activo'),
                  subtitle: const Text('Los clientes inactivos no aparecen al crear pedidos'),
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

/// Hoja para elegir un cliente activo (o registrar uno nuevo).
class SelectorCliente extends StatefulWidget {
  const SelectorCliente({super.key});

  @override
  State<SelectorCliente> createState() => _SelectorClienteState();
}

class _SelectorClienteState extends State<SelectorCliente> {
  late Future<List<Map<String, dynamic>>> _f = Api.clientes();

  Future<void> _nuevo() async {
    final c = await abrirPanel<Map<String, dynamic>>(context, (_) => const ClienteForm());
    if (c != null && mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: CampoBusqueda(
                  hint: 'Buscar cliente',
                  onChanged: (v) => setState(() => _f = Api.clientes(q: v)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(tooltip: 'Nuevo cliente', onPressed: _nuevo, icon: const Icon(Icons.person_add_alt_1)),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _f,
            builder: (ctx, snap) {
              if (snap.hasError) return VistaError(mensaje: limpiarError(snap.error!), onReintentar: () => setState(() => _f = Api.clientes()));
              if (!snap.hasData) return const CargandoLista();
              final items = snap.data!.where((c) => c['active'] != false).toList();
              if (items.isEmpty) {
                return VistaVacia(
                  icono: Icons.person_search,
                  titulo: 'Sin resultados',
                  accion: FilledButton.icon(onPressed: _nuevo, icon: const Icon(Icons.person_add_alt_1), label: const Text('Registrar cliente')),
                );
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => ListTile(
                  leading: AvatarIniciales(aTexto(items[i]['name'], '?')),
                  title: Text(aTexto(items[i]['name'])),
                  subtitle: Text(aTexto(items[i]['address'], aTexto(items[i]['phone'])), style: const TextStyle(color: AppColors.textMuted)),
                  onTap: () => Navigator.pop(context, items[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
