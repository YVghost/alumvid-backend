import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user.dart';
import '../../services/api_negocio.dart';
import '../../services/api_service.dart';
import '../../shared/adaptable.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';

const todosLosRoles = ['ADMINISTRADOR', 'VENDEDOR', 'BODEGUERO', 'CHOFER'];

String claveTemporal() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789-_';
  final r = Random.secure();
  return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Usuarios y auditoría de seguridad (administración).
/// Un administrador gestiona a quienes no son administradores; a los
/// administradores solo los gestiona la cuenta maestra.
class UsuariosModulo extends StatelessWidget {
  const UsuariosModulo({super.key, required this.permisos});
  final Permisos permisos;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Usuarios'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Colaboradores'), Tab(text: 'Auditoría de seguridad')],
          ),
        ),
        body: TabBarView(children: [_Colaboradores(permisos: permisos), const _Auditoria()]),
      ),
    );
  }
}

class _Colaboradores extends StatefulWidget {
  const _Colaboradores({required this.permisos});
  final Permisos permisos;

  @override
  State<_Colaboradores> createState() => _ColaboradoresState();
}

class _ColaboradoresState extends State<_Colaboradores> with AutomaticKeepAliveClientMixin {
  bool _cargando = true;
  String? _error;
  List<AppUser> _usuarios = [];
  String _q = '';
  String _rol = '';

  Permisos get p => widget.permisos;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _usuarios.isEmpty;
      _error = null;
    });
    try {
      final r = await ApiService.obtenerUsuariosAdmin();
      r.sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });
      if (mounted) setState(() => _usuarios = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<AppUser> get _filtrados {
    final q = _q.toLowerCase();
    return _usuarios.where((u) {
      if (_rol == 'INACTIVOS') return !u.active;
      if (_rol.isNotEmpty && !u.roles.contains(_rol)) return false;
      return q.isEmpty ||
          u.fullName.toLowerCase().contains(q) ||
          u.identification.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _form([AppUser? u]) async {
    final ok = await abrirPanel<bool>(context, (_) => _UsuarioForm(usuario: u, existentes: _usuarios, permisos: p));
    if (ok == true) _cargar();
  }

  void _acciones(AppUser u) {
    final gestiona = p.puedeGestionar(u);
    final propio = u.id == p.usuario.id;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AvatarIniciales(u.fullName),
              title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([u.identification, u.email, if ((u.telefono ?? '').isNotEmpty) u.telefono!].join(' · ')),
            ),
            const Divider(),
            if (!gestiona)
              const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Solo la cuenta maestra gestiona a otros administradores'),
              ),
            if (gestiona)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(u.active ? 'Editar datos y roles' : 'Editar o reactivar'),
                onTap: () {
                  Navigator.pop(ctx);
                  _form(u);
                },
              ),
            if (gestiona && !propio && u.active)
              ListTile(
                leading: const Icon(Icons.key_outlined, color: AppColors.warning),
                title: const Text('Restablecer contraseña'),
                subtitle: const Text('Genera una clave temporal y cierra sus sesiones'),
                onTap: () {
                  Navigator.pop(ctx);
                  _restablecer(u);
                },
              ),
            if (gestiona && !propio && !u.master && u.active)
              ListTile(
                leading: const Icon(Icons.person_off_outlined, color: AppColors.danger),
                title: const Text('Desactivar', style: TextStyle(color: AppColors.danger)),
                subtitle: const Text('No podrá ingresar; su historial se conserva'),
                onTap: () {
                  Navigator.pop(ctx);
                  _desactivar(u);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _restablecer(AppUser u) async {
    final clave = claveTemporal();
    final ok = await confirmar(
      context,
      titulo: 'Restablecer contraseña',
      mensaje: 'Clave temporal:\n\n$clave\n\n${u.fullName} deberá cambiarla al ingresar. Se copiará al portapapeles.',
      accion: 'Restablecer',
    );
    if (!ok || !mounted) return;
    try {
      await ApiService.restablecerContrasenaUsuario(u.id, clave);
      await ApiService.notificarSesionRevocada(u.id);
      await Clipboard.setData(ClipboardData(text: clave));
      if (mounted) avisoOk(context, 'Clave restablecida y copiada');
      _cargar();
    } catch (e) {
      if (mounted) avisoError(context, e);
    }
  }

  Future<void> _desactivar(AppUser u) async {
    final ok = await confirmar(context,
        titulo: 'Desactivar colaborador', mensaje: '${u.fullName} no podrá iniciar sesión.', accion: 'Desactivar', peligro: true);
    if (!ok || !mounted) return;
    try {
      await ApiService.eliminarUsuario(u.id);
      await ApiService.notificarSesionRevocada(u.id);
      if (mounted) avisoOk(context, 'Colaborador desactivado');
      _cargar();
    } catch (e) {
      if (mounted) avisoError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nuevo-usuario',
        onPressed: () => _form(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Usuario'),
      ),
      body: AnchoLegible(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: CampoBusqueda(hint: 'Nombre, cédula o correo', onChanged: (v) => setState(() => _q = v)),
            ),
            FiltrosChips<String>(
              opciones: {'': 'Todos', for (final r in todosLosRoles) r: humanizar(r), 'INACTIVOS': 'Desactivados'},
              seleccion: _rol,
              onSeleccion: (v) => setState(() => _rol = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _cargando
                  ? const CargandoLista()
                  : _error != null
                  ? VistaError(mensaje: _error!, onReintentar: _cargar)
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: _filtrados.isEmpty
                          ? const VistaVacia(icono: Icons.person_search, titulo: 'Sin resultados')
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                              itemCount: _filtrados.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _tarjeta(_filtrados[i]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(AppUser u) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _acciones(u),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AvatarIniciales(u.fullName, color: !u.active ? AppColors.neutral : u.master ? AppColors.warning : AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(u.fullName, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: u.active ? AppColors.text : AppColors.textDim)),
                        ),
                        if (u.master) ...[
                          const SizedBox(width: 6),
                          const Tooltip(message: 'Cuenta maestra', child: Icon(Icons.stars, color: AppColors.warning, size: 16)),
                        ],
                      ],
                    ),
                    Text(u.identification, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (!u.active) const EstadoChip('INACTIVO', texto: 'Desactivado'),
                        if (u.mustChangePassword) const EstadoChip('EN_CURSO', texto: 'Clave temporal'),
                        for (final r in u.roles) EstadoChip(r, texto: humanizar(r), color: AppColors.primaryLight),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.more_vert, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bitácora de seguridad: accesos, intentos fallidos y cambios de cuentas.
class _Auditoria extends StatefulWidget {
  const _Auditoria();

  @override
  State<_Auditoria> createState() => _AuditoriaState();
}

class _AuditoriaState extends State<_Auditoria> with AutomaticKeepAliveClientMixin {
  static const _grupos = <String, Set<String>>{
    '': {},
    'ACCESOS': {'LOGIN', 'LOGOUT'},
    'FALLIDOS': {'LOGIN_FAILED'},
    'CLAVES': {'PASSWORD_CHANGED', 'PASSWORD_RESET'},
    'CUENTAS': {'USER_CREATED', 'USER_UPDATED', 'ACCESS_UPDATED', 'USER_DEACTIVATED'},
  };
  String _grupo = '';
  late Future<List<Map<String, dynamic>>> _f = _cargar();

  @override
  bool get wantKeepAlive => true;

  Future<List<Map<String, dynamic>>> _cargar() async =>
      ((await Api.get('/api/v1/admin/audit')) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  static (String, IconData, Color) _etiqueta(String accion) => switch (accion) {
    'LOGIN' => ('Inició sesión', Icons.login, AppColors.success),
    'LOGOUT' => ('Cerró sesión', Icons.logout, AppColors.textMuted),
    'LOGIN_FAILED' => ('Intento de acceso fallido', Icons.gpp_bad, AppColors.danger),
    'PASSWORD_CHANGED' => ('Cambió su contraseña', Icons.key, AppColors.info),
    'PASSWORD_RESET' => ('Contraseña restablecida', Icons.lock_reset, AppColors.warning),
    'USER_CREATED' => ('Usuario creado', Icons.person_add_alt, AppColors.primaryLight),
    'USER_UPDATED' => ('Datos actualizados', Icons.edit, AppColors.primaryLight),
    'ACCESS_UPDATED' => ('Roles o acceso modificados', Icons.admin_panel_settings, AppColors.warning),
    'USER_DEACTIVATED' => ('Usuario desactivado', Icons.person_off, AppColors.danger),
    _ => (humanizar(accion), Icons.shield_outlined, AppColors.textMuted),
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnchoLegible(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Registro de seguridad: quién ingresó, intentos fallidos y cambios en cuentas y permisos (últimos 200 eventos).',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          FiltrosChips<String>(
            opciones: const {'': 'Todo', 'ACCESOS': 'Accesos', 'FALLIDOS': 'Fallidos', 'CLAVES': 'Contraseñas', 'CUENTAS': 'Cuentas'},
            seleccion: _grupo,
            onSeleccion: (v) => setState(() => _grupo = v),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _f,
              builder: (ctx, snap) {
                if (snap.hasError) return VistaError(mensaje: limpiarError(snap.error!), onReintentar: () => setState(() => _f = _cargar()));
                if (!snap.hasData) return const CargandoLista();
                final filtro = _grupos[_grupo]!;
                final eventos = snap.data!.where((e) => filtro.isEmpty || filtro.contains(e['action'])).toList();
                if (eventos.isEmpty) return const VistaVacia(icono: Icons.shield_outlined, titulo: 'Sin eventos');
                return RefreshIndicator(
                  onRefresh: () async => setState(() => _f = _cargar()),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                    itemCount: eventos.length,
                    separatorBuilder: (_, _) => const Divider(indent: 72),
                    itemBuilder: (_, i) {
                      final e = eventos[i];
                      final (texto, icono, color) = _etiqueta(aTexto(e['action']));
                      final quien = aTexto(e['actor']);
                      final sobre = aTexto(e['target']);
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.14), child: Icon(icono, color: color, size: 20)),
                        title: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            if (quien.isNotEmpty) 'Por $quien',
                            if (sobre.isNotEmpty && sobre != quien) 'sobre $sobre',
                            aTexto(e['detail']),
                            fmtFecha(aFecha(e['occurred_at'])),
                          ].where((x) => x.isNotEmpty).join(' · '),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      );
                    },
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

class _UsuarioForm extends StatefulWidget {
  const _UsuarioForm({this.usuario, required this.existentes, required this.permisos});
  final AppUser? usuario;
  final List<AppUser> existentes;
  final Permisos permisos;

  @override
  State<_UsuarioForm> createState() => _UsuarioFormState();
}

class _UsuarioFormState extends State<_UsuarioForm> {
  final _form = GlobalKey<FormState>();
  late final _ident = TextEditingController(text: widget.usuario?.identification ?? '');
  late final _nombre = TextEditingController(text: widget.usuario?.fullName ?? '');
  late final _email = TextEditingController(text: widget.usuario?.email ?? '');
  late final _tel = TextEditingController(text: widget.usuario?.telefono ?? '');
  final _clave = TextEditingController(text: claveTemporal());
  late final Set<String> _roles = {...?widget.usuario?.roles};
  late bool _activo = widget.usuario?.active ?? true;
  bool _guardando = false;

  bool get _editando => widget.usuario != null;
  bool get _propio => widget.usuario?.id == widget.permisos.usuario.id;

  @override
  void initState() {
    super.initState();
    if (_roles.isEmpty) _roles.add('VENDEDOR');
  }

  @override
  void dispose() {
    for (final c in [_ident, _nombre, _email, _tel, _clave]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      if (_editando) {
        await ApiService.actualizarUsuario(widget.usuario!.id,
            fullName: _nombre.text.trim(), telefono: _tel.text.trim(), roles: _roles.toList(), active: _activo);
        if (!_activo && widget.usuario!.active) await ApiService.notificarSesionRevocada(widget.usuario!.id);
      } else {
        await ApiService.crearUsuario(
          identification: _ident.text.trim(),
          fullName: _nombre.text.trim(),
          email: _email.text.trim(),
          telefono: _tel.text.trim(),
          roles: _roles.toList(),
          temporaryPassword: _clave.text.trim(),
        );
        await Clipboard.setData(ClipboardData(text: _clave.text.trim()));
      }
      if (!mounted) return;
      avisoOk(context, _editando ? 'Colaborador actualizado' : 'Usuario creado · clave temporal copiada');
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
    final maestro = widget.usuario?.master == true;
    // Otorgar el rol ADMINISTRADOR solo lo hace la cuenta maestra.
    final puedeAdmin = widget.permisos.esMaestro;
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar colaborador' : 'Nuevo usuario')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _guardando ? null : _guardar, child: Text(_editando ? 'Guardar cambios' : 'Crear usuario')),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _ident,
              enabled: !_editando,
              decoration: const InputDecoration(labelText: 'Identificación *', hintText: 'Cédula o identificación'),
              validator: (v) {
                if (_editando) return null;
                final c = (v ?? '').trim();
                if (!RegExp(r'^[A-Za-z0-9-]{3,30}$').hasMatch(c)) return 'Entre 3 y 30 letras, números o guiones';
                if (widget.existentes.any((u) => u.identification == c)) return 'Ya está registrada';
                return null;
              },
            ),
            gap,
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre completo *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
            ),
            gap,
            TextFormField(
              controller: _email,
              enabled: !_editando,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo *'),
              validator: (v) {
                if (_editando) return null;
                final m = (v ?? '').trim().toLowerCase();
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(m)) return 'Correo no válido';
                if (widget.existentes.any((u) => u.email.toLowerCase() == m)) return 'Ya está registrado';
                return null;
              },
            ),
            gap,
            TextFormField(controller: _tel, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
            const SeccionTitulo('Roles'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in todosLosRoles)
                  FilterChip(
                    label: Text(humanizar(r)),
                    selected: _roles.contains(r),
                    onSelected: (r == 'ADMINISTRADOR' && (!puedeAdmin || maestro || _propio))
                        ? null
                        : (sel) => setState(() {
                              if (sel) {
                                _roles.add(r);
                              } else if (_roles.length > 1) {
                                _roles.remove(r);
                              }
                            }),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Administrador: todo. Vendedor: pedidos y clientes. Bodeguero: preparación, recepciones y traslados. Chofer: rutas asignadas.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            if (!puedeAdmin)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Solo la cuenta maestra otorga o quita el rol Administrador.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ),
            if (!_editando) ...[
              const SeccionTitulo('Clave temporal'),
              TextFormField(
                controller: _clave,
                decoration: InputDecoration(
                  labelText: 'Contraseña temporal *',
                  helperText: 'La cambiará en su primer ingreso',
                  suffixIcon: IconButton(
                    tooltip: 'Generar otra',
                    icon: const Icon(Icons.autorenew),
                    onPressed: () => setState(() => _clave.text = claveTemporal()),
                  ),
                ),
                validator: (v) => (v ?? '').length < 12 ? 'Mínimo 12 caracteres' : null,
              ),
            ],
            if (_editando && !_propio) ...[
              gap,
              Card(
                child: SwitchListTile(
                  title: const Text('Cuenta activa'),
                  subtitle: Text(maestro ? 'La cuenta maestra no se puede desactivar' : 'Si la desactivas se cierran sus sesiones'),
                  value: _activo,
                  onChanged: maestro ? null : (v) => setState(() => _activo = v),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
