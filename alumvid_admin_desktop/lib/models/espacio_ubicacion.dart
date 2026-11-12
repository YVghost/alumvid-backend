class EspacioUbicacion {
  final String id;
  final String code; // Ej: "A1", "A2", "B3"
  final String? description;
  final bool active;
  final DateTime createdAt;

  EspacioUbicacion({
    required this.id,
    required this.code,
    this.description,
    required this.active,
    required this.createdAt,
  });

  factory EspacioUbicacion.fromJson(Map<String, dynamic> json) {
    return EspacioUbicacion(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? 'Ubicación',
      description: json['description']?.toString(),
      active: json['active'] != false,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }
}
