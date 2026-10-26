class MovimientoInventario {
  final String id;
  final String requestId;
  final String productId;
  final String productCode;
  final String productName;
  final String unit;
  final String type; // INGRESO, SALIDA, AJUSTE
  final double quantity;
  final double delta;
  final double stockBefore;
  final double stockAfter;
  final String reason;
  final String reference;
  final String actorName;
  final DateTime? occurredAt;

  MovimientoInventario({
    required this.id,
    required this.requestId,
    required this.productId,
    this.productCode = '',
    this.productName = '',
    this.unit = '',
    required this.type,
    required this.quantity,
    required this.delta,
    required this.stockBefore,
    required this.stockAfter,
    required this.reason,
    required this.reference,
    required this.actorName,
    this.occurredAt,
  });

  factory MovimientoInventario.fromJson(Map<String, dynamic> json) {
    return MovimientoInventario(
      id: json['id']?.toString() ?? '',
      requestId: json['requestId']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      productCode: json['productCode']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '',
      type: json['type']?.toString() ?? 'INGRESO',
      quantity: double.tryParse(json['quantity']?.toString() ?? '') ?? 0.0,
      delta: double.tryParse(json['delta']?.toString() ?? '') ?? 0.0,
      stockBefore: double.tryParse(json['stockBefore']?.toString() ?? '') ?? 0.0,
      stockAfter: double.tryParse(json['stockAfter']?.toString() ?? '') ?? 0.0,
      reason: json['reason']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      actorName: json['actorName']?.toString() ?? 'Sistema',
      occurredAt: json['occurredAt'] != null ? DateTime.tryParse(json['occurredAt'].toString()) : null,
    );
  }
}
