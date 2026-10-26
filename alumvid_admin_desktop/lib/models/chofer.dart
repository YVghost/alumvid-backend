class Chofer {
  final String id;
  final String nombre;
  final String email;
  final String? telefono;
  final String estadoDisponibilidad; // DISPONIBLE, EN_RUTA, INACTIVO

  Chofer({
    required this.id,
    required this.nombre,
    required this.email,
    this.telefono,
    required this.estadoDisponibilidad,
  });

  bool get isEnRuta => estadoDisponibilidad == 'EN_RUTA';

  factory Chofer.fromJson(Map<String, dynamic> json) {
    return Chofer(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? 'Chofer',
      email: json['email']?.toString() ?? '',
      telefono: json['telefono']?.toString(),
      estadoDisponibilidad: json['estadoDisponibilidad']?.toString() ?? 'DISPONIBLE',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chofer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
