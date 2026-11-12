import '../models/user.dart';

/// Qué puede hacer el usuario en cada módulo. Replica las reglas del backend
/// (que es quien las hace cumplir); la app solo oculta lo que no corresponde.
class Permisos {
  const Permisos(this.usuario);
  final AppUser usuario;

  bool tiene(String rol) => usuario.roles.contains(rol);
  bool get esAdmin => tiene('ADMINISTRADOR');
  bool get esMaestro => usuario.master;

  /// Crear pedidos, clientes, confirmar, reintentar y cancelar.
  bool get vende => esAdmin || tiene('VENDEDOR');

  /// Preparar, entregar en local, recibir devoluciones, recepción de compras y traslados.
  bool get bodega => esAdmin || tiene('BODEGUERO');

  /// Retrasar / reanudar un pedido.
  bool get gestionaPedidos => vende || bodega;

  /// Conteo físico (ajuste) y catálogo de productos.
  bool get ajustaInventario => esAdmin;
  bool get editaCatalogo => esAdmin;

  /// Planificar rutas, monitoreo y usuarios.
  bool get planificaRutas => esAdmin;
  bool get gestionaUsuarios => esAdmin;

  /// Gestionar a otro usuario: los administradores solo los gestiona la cuenta maestra.
  bool puedeGestionar(AppUser otro) =>
      esAdmin && (esMaestro || !otro.isAdmin || otro.id == usuario.id);
}
