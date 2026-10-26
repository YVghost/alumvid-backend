import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/audit_event.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/cedula_validator.dart';

class UsuariosView extends StatefulWidget {
  final AppUser currentUser;

  const UsuariosView({super.key, required this.currentUser});

  @override
  State<UsuariosView> createState() => _UsuariosViewState();
}

class _UsuariosViewState extends State<UsuariosView> {
  List<AppUser> _usuarios = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  Future<void> _cargarUsuarios() async {
    setState(() => _cargando = true);
    try {
      final list = await ApiService.obtenerUsuariosAdmin();
      if (!mounted) return;
      setState(() {
        _usuarios = list;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar usuarios: $e'), backgroundColor: AppTheme.statusAlerta),
      );
    }
  }

  void _abrirModalCrearUsuario() {
    final identCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final tempPassCtrl = TextEditingController(text: 'AlumVid2026!');
    final formKey = GlobalKey<FormState>();

    List<String> rolesSeleccionados = ['CHOFER'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.person_add, color: AppTheme.primaryLight, size: 20),
              SizedBox(width: 8),
              Text('Registrar Nuevo Colaborador'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: identCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cédula Ecuatoriana',
                      hintText: '10 dígitos (Algoritmo Módulo 10)',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Requerido';
                      final ced = v.trim();
                      if (!validarCedulaEcuatoriana(ced)) {
                        return 'Cédula ecuatoriana inválida (verifique dígitos y provincia)';
                      }
                      if (_usuarios.any((u) => u.identification == ced)) {
                        return 'Esta cédula ya se encuentra registrada en el sistema';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre Completo'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Correo Electrónico'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Requerido';
                      final mail = v.trim().toLowerCase();
                      if (_usuarios.any((u) => u.email.toLowerCase() == mail)) {
                        return 'Este correo ya está registrado';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Teléfono Móvil (Ej. 0983579402)'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Roles Operativos:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ['ADMINISTRADOR', 'VENDEDOR', 'BODEGUERO', 'CHOFER'].map((rol) {
                      final isSelected = rolesSeleccionados.contains(rol);
                      return FilterChip(
                        label: Text(rol, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textMuted, fontSize: 11)),
                        selected: isSelected,
                        selectedColor: AppTheme.primary,
                        backgroundColor: const Color(0xFF161F30),
                        onSelected: (val) {
                          setDState(() {
                            if (val) {
                              rolesSeleccionados.add(rol);
                            } else {
                              if (rolesSeleccionados.length > 1) {
                                rolesSeleccionados.remove(rol);
                              }
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: tempPassCtrl,
                    decoration: const InputDecoration(labelText: 'Contraseña Temporal (mín 12 car.)'),
                    validator: (v) => v == null || v.length < 12 ? 'Mínimo 12 caracteres' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted))),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ApiService.crearUsuario(
                    identification: identCtrl.text.trim(),
                    fullName: nameCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    telefono: phoneCtrl.text.trim(),
                    roles: rolesSeleccionados,
                    temporaryPassword: tempPassCtrl.text.trim(),
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  _cargarUsuarios();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Colaborador creado exitosamente'), backgroundColor: AppTheme.statusCompletada),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: AppTheme.statusAlerta),
                  );
                }
              },
              child: const Text('Crear Colaborador'),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirModalEditarUsuario(AppUser u) {
    final nameCtrl = TextEditingController(text: u.fullName);
    final phoneCtrl = TextEditingController(text: u.telefono ?? '');
    List<String> rolesSeleccionados = List.from(u.roles);
    bool activo = u.active;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Editar Colaborador — ${u.identification}'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre Completo'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Teléfono Móvil'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Roles Operativos:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ['ADMINISTRADOR', 'VENDEDOR', 'BODEGUERO', 'CHOFER'].map((rol) {
                      final isSelected = rolesSeleccionados.contains(rol);
                      return FilterChip(
                        label: Text(rol, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textMuted, fontSize: 11)),
                        selected: isSelected,
                        selectedColor: AppTheme.primary,
                        backgroundColor: const Color(0xFF161F30),
                        onSelected: (val) {
                          setDState(() {
                            if (val) {
                              rolesSeleccionados.add(rol);
                            } else {
                              if (rolesSeleccionados.length > 1) {
                                rolesSeleccionados.remove(rol);
                              }
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Cuenta Activa', style: TextStyle(fontSize: 13)),
                    value: activo,
                    activeThumbColor: AppTheme.primaryLight,
                    onChanged: u.master ? null : (val) => setDState(() => activo = val),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted))),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ApiService.actualizarUsuario(
                    u.id,
                    fullName: nameCtrl.text.trim(),
                    telefono: phoneCtrl.text.trim(),
                    roles: rolesSeleccionados,
                    active: activo,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  _cargarUsuarios();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Colaborador actualizado'), backgroundColor: AppTheme.statusCompletada),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: AppTheme.statusAlerta),
                  );
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirModalResetClave(AppUser u) {
    final passCtrl = TextEditingController(text: 'AlumVidNueva2026!');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Restablecer Clave — ${u.fullName}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Al restablecer la contraseña, se revocarán todas sus sesiones activas.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              TextFormField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'Nueva Contraseña Temporal (mín 12 car.)'),
                validator: (v) => v == null || v.length < 12 ? 'Mínimo 12 caracteres' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusEnCurso),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await ApiService.restablecerContrasenaUsuario(u.id, passCtrl.text.trim());
                await ApiService.notificarSesionRevocada(u.id);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contraseña restablecida exitosamente'), backgroundColor: AppTheme.statusCompletada),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: AppTheme.statusAlerta),
                );
              }
            },
            child: const Text('Restablecer Contraseña'),
          ),
        ],
      ),
    );
  }

  void _eliminarUsuario(AppUser u) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Eliminar Usuario: ${u.fullName}'),
        content: Text(
          '¿Está seguro de que desea eliminar permanentemente al usuario "${u.fullName}" (${u.identification}) de la base de datos?\n\nEsta acción no se puede deshacer.',
          style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusAlerta),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar Definitivamente'),
          ),
        ],
      ),
    );

    if (conf == true) {
      try {
        await ApiService.eliminarUsuario(u.id, esChofer: u.roles.contains('CHOFER'));
        await ApiService.notificarSesionRevocada(u.id);
        if (!mounted) return;
        _cargarUsuarios();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario eliminado de la base de datos'), backgroundColor: AppTheme.statusCompletada),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar usuario: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: AppTheme.statusAlerta),
        );
      }
    }
  }

  void _abrirBitacoraAuditoria() {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<List<EventoAuditoria>>(
        future: ApiService.obtenerAuditoriaSeguridad(),
        builder: (context, snapshot) {
          final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Row(
              children: [
                Icon(Icons.security, color: AppTheme.primaryLight, size: 20),
                SizedBox(width: 8),
                Text('Bitácora de Auditoría de Seguridad'),
              ],
            ),
            content: SizedBox(
              width: 650,
              height: 450,
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : (snapshot.data == null || snapshot.data!.isEmpty)
                      ? const Center(child: Text('Sin eventos de auditoría registrados', style: TextStyle(color: AppTheme.textMuted)))
                      : ListView.separated(
                          itemCount: snapshot.data!.length,
                          separatorBuilder: (c, i) => const Divider(color: AppTheme.border, height: 1),
                          itemBuilder: (context, index) {
                            final ev = snapshot.data![index];
                            return ListTile(
                              dense: true,
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(ev.action, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryLight, fontSize: 12)),
                                  Text(ev.occurredAt != null ? dateFormat.format(ev.occurredAt!) : '', style: const TextStyle(color: AppTheme.textDim, fontSize: 10)),
                                ],
                              ),
                              subtitle: Text(ev.detail, style: const TextStyle(color: Colors.white, fontSize: 11)),
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
          // Encabezado
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gestión de Usuarios y Roles (RBAC)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('Control de acceso, cédulas ecuatorianas y auditoría (${_usuarios.length} cuentas registradas)', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.refresh, color: AppTheme.primaryLight), tooltip: 'Actualizar usuarios', onPressed: _cargarUsuarios),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.border)),
                    icon: const Icon(Icons.shield, size: 16, color: AppTheme.accent),
                    label: const Text('Auditoría', style: TextStyle(fontSize: 12, color: AppTheme.accent)),
                    onPressed: _abrirBitacoraAuditoria,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                    icon: const Icon(Icons.person_add, size: 16),
                    label: const Text('+ Nuevo Colaborador', style: TextStyle(fontSize: 12)),
                    onPressed: _abrirModalCrearUsuario,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Lista de Colaboradores
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _usuarios.isEmpty
                    ? const Center(child: Text('Sin usuarios en la base de datos', style: TextStyle(color: AppTheme.textMuted)))
                    : ListView.separated(
                        itemCount: _usuarios.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final u = _usuarios[index];

                          return Card(
                            margin: EdgeInsets.zero,
                            color: const Color(0xFF161F30),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // Avatar
                                  CircleAvatar(
                                    backgroundColor: u.master ? AppTheme.statusEnCurso : AppTheme.primary,
                                    radius: 18,
                                    child: Icon(u.master ? Icons.stars : Icons.person, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: 12),

                                  // Identificación y Nombre
                                  SizedBox(
                                    width: 170,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(u.identification, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: AppTheme.primaryLight, fontSize: 13)),
                                        Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Contacto (Email y Teléfono)
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.email_outlined, size: 12, color: AppTheme.textMuted),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                u.email.isEmpty ? '—' : u.email,
                                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(Icons.phone_outlined, size: 12, color: AppTheme.primaryLight),
                                            const SizedBox(width: 4),
                                            Text(
                                              (u.telefono != null && u.telefono!.isNotEmpty) ? u.telefono! : 'Sin teléfono',
                                              style: TextStyle(
                                                color: (u.telefono != null && u.telefono!.isNotEmpty) ? Colors.white70 : AppTheme.textDim,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Roles
                                  Expanded(
                                    flex: 2,
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: u.roles.map((r) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.border)),
                                          child: Text(r, style: const TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Estado
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: u.active ? AppTheme.statusCompletada.withValues(alpha: 0.15) : AppTheme.statusAlerta.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      u.active ? 'ACTIVO' : 'INACTIVO',
                                      style: TextStyle(color: u.active ? AppTheme.statusCompletada : AppTheme.statusAlerta, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Acciones
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 18, color: AppTheme.primaryLight),
                                        tooltip: 'Editar colaborador',
                                        onPressed: () => _abrirModalEditarUsuario(u),
                                      ),
                                      if (widget.currentUser.master)
                                        IconButton(
                                          icon: const Icon(Icons.key, size: 18, color: AppTheme.statusEnCurso),
                                          tooltip: 'Restablecer contraseña',
                                          onPressed: () => _abrirModalResetClave(u),
                                        ),
                                      if (widget.currentUser.master && !u.master)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.statusAlerta),
                                          tooltip: 'Eliminar colaborador de la BD',
                                          onPressed: () => _eliminarUsuario(u),
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
