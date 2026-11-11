class ProductoRetazo {
  final String id;
  final String code;
  final String name;
  final double stock;
  final String unit;
  final bool active;
  final bool piecesManaged;
  final String? kind; // ALUMINIO, VIDRIO

  ProductoRetazo({
    required this.id,
    required this.code,
    required this.name,
    required this.stock,
    required this.unit,
    required this.active,
    required this.piecesManaged,
    this.kind,
  });

  factory ProductoRetazo.fromJson(Map<String, dynamic> json) {
    return ProductoRetazo(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      stock: (json['stock'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit']?.toString() ?? 'UNIDAD',
      active: json['active'] != false,
      piecesManaged: json['piecesManaged'] == true || json['pieces_managed'] == true,
      kind: json['kind']?.toString(),
    );
  }
}

class PiezaRetazo {
  final String id;
  final double? lengthM;
  final double? widthCm;
  final double? heightCm;
  final String state; // DISPONIBLE, TRANSFORMADO, CONSUMIDO, DESCARTADO, PREPARADO, ENTREGADO
  final String? location;
  final String? code;

  PiezaRetazo({
    required this.id,
    this.lengthM,
    this.widthCm,
    this.heightCm,
    required this.state,
    this.location,
    this.code,
  });

  String get dimensionesTexto {
    if (lengthM != null && lengthM! > 0) {
      return '${lengthM!.toStringAsFixed(2)} m (Perfil)';
    }
    if (widthCm != null && heightCm != null) {
      return '${widthCm!.toStringAsFixed(1)} × ${heightCm!.toStringAsFixed(1)} cm';
    }
    return 'Pieza física estándar';
  }

  factory PiezaRetazo.fromJson(Map<String, dynamic> json) {
    return PiezaRetazo(
      id: json['id']?.toString() ?? '',
      lengthM: (json['lengthM'] as num?)?.toDouble() ?? (json['length_m'] as num?)?.toDouble(),
      widthCm: (json['widthCm'] as num?)?.toDouble() ?? (json['width_cm'] as num?)?.toDouble(),
      heightCm: (json['heightCm'] as num?)?.toDouble() ?? (json['height_cm'] as num?)?.toDouble(),
      state: json['state']?.toString() ?? 'DISPONIBLE',
      location: json['location']?.toString(),
      code: json['code']?.toString(),
    );
  }
}

