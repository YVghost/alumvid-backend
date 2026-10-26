class Producto {
  final String id;
  final String code;
  final String name;
  final String category;
  final String unit; // UNIDAD, METRO, METRO_CUADRADO, ROLLO, KILOGRAMO, LITRO
  final String description;
  final String supplier;
  final String externalCode;
  final String location;
  final double minStock;
  final double stock;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Producto({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.unit,
    required this.description,
    required this.supplier,
    required this.externalCode,
    required this.location,
    required this.minStock,
    required this.stock,
    required this.active,
    this.createdAt,
    this.updatedAt,
  });

  bool get isStockBajo => stock <= minStock && stock > 0;
  bool get isAgotado => stock <= 0;

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'VIDRIO',
      unit: json['unit']?.toString() ?? 'UNIDAD',
      description: json['description']?.toString() ?? '',
      supplier: json['supplier']?.toString() ?? '',
      externalCode: json['externalCode']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      minStock: double.tryParse(json['minStock']?.toString() ?? '') ?? 0.0,
      stock: double.tryParse(json['stock']?.toString() ?? '') ?? 0.0,
      active: json['active'] != false,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'category': category,
      'unit': unit,
      'description': description,
      'supplier': supplier,
      'externalCode': externalCode,
      'location': location,
      'minStock': minStock,
      'active': active,
    };
  }
}
