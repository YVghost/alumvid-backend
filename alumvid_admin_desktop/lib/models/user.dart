class AppUser {
  final String id;
  final String identification;
  final String fullName;
  final String email;
  final String? telefono;
  final List<String> roles;
  final bool master;
  final bool active;

  AppUser({
    required this.id,
    required this.identification,
    required this.fullName,
    required this.email,
    this.telefono,
    required this.roles,
    required this.master,
    required this.active,
  });

  bool get isAdmin => roles.contains('ADMINISTRADOR');

  factory AppUser.fromJson(Map<String, dynamic> json) {
    List<String> parsedRoles = [];
    if (json['roles'] is List) {
      parsedRoles = (json['roles'] as List).map((r) => r.toString()).toList();
    } else if (json['roles'] is String) {
      parsedRoles = (json['roles'] as String).split(',').map((r) => r.trim()).toList();
    }

    return AppUser(
      id: json['id']?.toString() ?? '',
      identification: json['identification']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? json['nombre']?.toString() ?? 'Usuario',
      email: json['email']?.toString() ?? '',
      telefono: json['telefono']?.toString(),
      roles: parsedRoles,
      master: json['master'] == true,
      active: json['active'] != false,
    );
  }
}
