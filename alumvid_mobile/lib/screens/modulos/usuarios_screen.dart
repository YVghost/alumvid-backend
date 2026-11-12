import 'dart:math';

import 'package:alumvid_admin_desktop/models/audit_event.dart';
import 'package:alumvid_admin_desktop/models/user.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sesion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

const _todosLosRoles = ['ADMINISTRADOR', 'VENDEDOR', 'BODEGUERO', 'CHOFER'];

String _claveTemporal() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789-_';
  final r = Random.secure();
  return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Gestión de usuarios (solo ADMINISTRADOR). Auditoría, restablecer clave y
/// desactivar: solo la cuenta maestra, como en el backend y el escritorio.
class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key, required this.sesion});
  final Sesion sesion;

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  bool _cargando = true;
  String? _error;
  List<AppUser> _usuarios = [];
  String _q = '';
  String _rol = '';

  AppUser get _yo => widget.sesion.usuario;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await adm.ApiService.obtenerUsuariosAdmin();
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
      if (_rol.isNotEmpty && !u.roles.contains(_rol)) return false;
      if (q.isEmpty) return true;
      return u.fullName.toLowerCase().contains(q) ||
          u.identification.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _formulario([AppUser? u]) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _UsuarioFormScreen(usuario: u, existentes: _usuarios),
      ),
    );
    if (ok == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    // El backend solo entrega la auditoría a la cuenta maestra.
    final verAuditoria = _yo.master;
    return DefaultTabController(
      length: verAuditoria ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Usuarios'),
          bottom: verAuditoria
              ? const TabBar(
                  tabAlignment: TabAlignment.fill,
                  tabs: [
                    Tab(text: 'Colaboradores'),
                    Tab(text: 'Auditoría'),
                  ],
                )
              : null,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _formulario(),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Usuario'),
        ),
        body: TabBarView(
          children: [
            _lista(),
            if (verAuditoria) const _AuditoriaTab(),
          ],
        ),
      ),
    );
  }

  Widget _lista() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: CampoBusqueda(
            hint: 'Nombre, cédula o correo',
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        FiltrosChips<String>(
          opciones: {'': 'Todos', for (final r in _todosLosRoles) r: humanizar(r)},
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
                          itemBuilder: (_, i) => _usuarioCard(_filtrados[i]),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _usuarioCard(AppUser u) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _acciones(u),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AvatarIniciales(
                u.fullName,
                color: !u.active
                    ? AppColors.neutral
                    : u.master
                    ? AppColors.warning
                    : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            u.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: u.active ? AppColors.text : AppColors.textDim,
                            ),
                          ),
                        ),
                        if (u.master) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.stars, color: AppColors.warning, size: 16),
                        ],
                      ],
                    ),
                    Text(
                      u.identification,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (!u.active) const EstadoChip('INACTIVO', texto: 'Desactivado'),
                        if (u.mustChangePassword)
                          const EstadoChip('EN_CURSO', texto: 'Clave temporal'),
                        for (final r in u.roles)
                          EstadoChip(r, texto: humanizar(r), color: AppColors.primaryLight),
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

  void _acciones(AppUser u) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AvatarIniciales(u.fullName),
              title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                [u.email, if ((u.telefono ?? '').isNotEmpty) u.telefono!].join(' · '),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar datos y roles'),
              onTap: () {
                Navigator.pop(ctx);
                _formulario(u);
              },
            ),
            if (_yo.master)
              ListTile(
                leading: const Icon(Icons.key_outlined, color: AppColors.warning),
                title: const Text('Restablecer contraseña'),
                subtitle: const Text('Cierra todas sus sesiones activas'),
                onTap: () {
                  Navigator.pop(ctx);
                  _restablecer(u);
                },
              ),
            if (_yo.master && !u.master && u.active)
              ListTile(
                leading: const Icon(Icons.person_off_outlined, color: AppColors.danger),
                title: const Text('Desactivar colaborador', style: TextStyle(color: AppColors.danger)),
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
    final clave = _claveTemporal();
    final ok = await confirmar(
      context,
      titulo: 'Restablecer contraseña',
      mensaje:
          'Se asignará la clave temporal:\n\n$clave\n\n${u.fullName} deberá cambiarla al ingresar y se cerrarán sus sesiones.',
      accion: 'Restablecer',
    );
    if (!ok || !mounted) return;
    try {
      await adm.ApiService.restablecerContrasenaUsuario(u.id, clave);
      await adm.ApiService.notificarSesionRevocada(u.id);
      await Clipboard.setData(ClipboardData(text: clave));
      if (mounted) avisoOk(context, 'Clave restablecida y copiada al portapapeles');
      _cargar();
    } catch (e) {
      if (mounted) avisoError(context, e);
    }
  }

  Future<void> _desactivar(AppUser u) async {
    final ok = await confirmar(
      context,
      titulo: 'Desactivar colaborador',
      mensaje: '${u.fullName} no podrá iniciar sesión y se cerrarán sus sesiones activas.',
      accion: 'Desactivar',
      peligro: true,
    );
    if (!ok || !mounted) return;
    try {
      await adm.ApiService.eliminarUsuario(u.id, esChofer: u.roles.contains('CHOFER'));
      await adm.ApiService.notificarSesionRevocada(u.id);
      if (mounted) avisoOk(context, 'Colaborador desactivado');
      _cargar();
    } catch (e) {
      if (mounted) avisoError(context, e);
    }
  }
}

// ---------------------------------------------------------------------------

class _AuditoriaTab extends StatefulWidget {
  const _AuditoriaTab();

  @override
  State<_AuditoriaTab> createState() => _AuditoriaTabState();
}

class _AuditoriaTabState extends State<_AuditoriaTab>
    with AutomaticKeepAliveClientMixin {
  bool _cargando = true;
  String? _error;
  List<EventoAuditoria> _eventos = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await adm.ApiService.obtenerAuditoriaSeguridad();
      if (mounted) setState(() => _eventos = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  IconData _icono(String a) {
    final x = a.toUpperCase();
    if (x.contains('LOGIN')) return Icons.login;
    if (x.contains('LOGOUT')) return Icons.logout;
    if (x.contains('PASSWORD')) return Icons.key;
    if (x.contains('CREATE')) return Icons.person_add_alt;
    if (x.contains('DEACTIV') || x.contains('DELETE')) return Icons.person_off;
    if (x.contains('UPDATE')) return Icons.edit;
    if (x.contains('FAIL') || x.contains('DENIED')) return Icons.gpp_bad;
    return Icons.shield_outlined;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return const CargandoLista();
    if (_error != null) return VistaError(mensaje: _error!, onReintentar: _cargar);
    return RefreshIndicator(
      onRefresh: _cargar,
      child: _eventos.isEmpty
          ? const VistaVacia(icono: Icons.shield_outlined, titulo: 'Sin eventos de seguridad')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              itemCount: _eventos.length,
              separatorBuilder: (_, _) => const Divider(indent: 72),
              itemBuilder: (_, i) {
                final e = _eventos[i];
                final falla = e.action.toUpperCase().contains('FAIL');
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (falla ? AppColors.danger : AppColors.primaryLight)
                        .withValues(alpha: 0.14),
                    child: Icon(
                      _icono(e.action),
                      color: falla ? AppColors.danger : AppColors.primaryLight,
                      size: 20,
                    ),
                  ),
                  title: Text(humanizar(e.action), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${e.detail}\n${fmtFecha(e.occurredAt)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  isThreeLine: true,
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------

class _UsuarioFormScreen extends StatefulWidget {
  const _UsuarioFormScreen({this.usuario, required this.existentes});
  final AppUser? usuario;
  final List<AppUser> existentes;

  @override
  State<_UsuarioFormScreen> createState() => _UsuarioFormScreenState();
}

class _UsuarioFormScreenState extends State<_UsuarioFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _ident = TextEditingController(text: widget.usuario?.identification ?? '');
  late final _nombre = TextEditingController(text: widget.usuario?.fullName ?? '');
  late final _email = TextEditingController(text: widget.usuario?.email ?? '');
  late final _tel = TextEditingController(text: widget.usuario?.telefono ?? '');
  final _clave = TextEditingController(text: _claveTemporal());
  late final Set<String> _roles = {...?widget.usuario?.roles};
  late bool _activo = widget.usuario?.active ?? true;
  bool _guardando = false;

  bool get _editando => widget.usuario != null;

  @override
  void initState() {
    super.initState();
    if (_roles.isEmpty) _roles.add('CHOFER');
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
        await adm.ApiService.actualizarUsuario(
          widget.usuario!.id,
          fullName: _nombre.text.trim(),
          telefono: _tel.text.trim(),
          roles: _roles.toList(),
          active: _activo,
        );
        if (!_activo && widget.usuario!.active) {
          await adm.ApiService.notificarSesionRevocada(widget.usuario!.id);
        }
      } else {
        await adm.ApiService.crearUsuario(
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
      avisoOk(
        context,
        _editando ? 'Colaborador actualizado' : 'Usuario creado · clave temporal copiada',
      );
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
    final esMaestro = widget.usuario?.master == true;
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar colaborador' : 'Nuevo usuario')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(_editando ? 'Guardar cambios' : 'Crear usuario'),
          ),
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
              decoration: const InputDecoration(
                labelText: 'Identificación *',
                hintText: 'Cédula o identificación',
              ),
              validator: (v) {
                final c = (v ?? '').trim();
                if (_editando) return null;
                if (!RegExp(r'^[A-Za-z0-9-]{3,30}$').hasMatch(c)) {
                  return 'Entre 3 y 30 letras, números o guiones';
                }
                if (widget.existentes.any((u) => u.identification == c)) {
                  return 'Esta identificación ya está registrada';
                }
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
              decoration: const InputDecoration(labelText: 'Correo electrónico *'),
              validator: (v) {
                if (_editando) return null;
                final m = (v ?? '').trim().toLowerCase();
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(m)) return 'Correo no válido';
                if (widget.existentes.any((u) => u.email.toLowerCase() == m)) {
                  return 'Este correo ya está registrado';
                }
                return null;
              },
            ),
            gap,
            TextFormField(
              controller: _tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
            const SeccionTitulo('Roles'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _todosLosRoles)
                  FilterChip(
                    label: Text(humanizar(r)),
                    selected: _roles.contains(r),
                    onSelected: (sel) => setState(() {
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
                'Cada rol habilita sus módulos: Administrador (todo), Vendedor (pedidos y consulta), '
                'Bodeguero (stock y preparación), Chofer (rutas asignadas).',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            if (!_editando) ...[
              const SeccionTitulo('Clave temporal'),
              TextFormField(
                controller: _clave,
                decoration: InputDecoration(
                  labelText: 'Contraseña temporal *',
                  helperText: 'Deberá cambiarla en su primer ingreso',
                  suffixIcon: IconButton(
                    tooltip: 'Generar otra',
                    icon: const Icon(Icons.autorenew),
                    onPressed: () => setState(() => _clave.text = _claveTemporal()),
                  ),
                ),
                validator: (v) => (v ?? '').length < 12 ? 'Mínimo 12 caracteres' : null,
              ),
            ],
            if (_editando) ...[
              gap,
              Card(
                child: SwitchListTile(
                  title: const Text('Cuenta activa'),
                  subtitle: Text(
                    esMaestro
                        ? 'La cuenta maestra no se puede desactivar'
                        : 'Si la desactivas se cierran sus sesiones',
                  ),
                  value: _activo,
                  onChanged: esMaestro ? null : (v) => setState(() => _activo = v),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

