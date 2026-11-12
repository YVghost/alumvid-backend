class PedidoComercial {
  final String id;
  final int number;
  final String clientId;
  final String clientName;
  final String state; // BORRADOR, PENDIENTE_MATERIAL, RESERVADO, PARCIAL, LISTO, EN_REPARTO, RETRASADO, CANCELADO, VENCIDO, ENTREGADO
  final String deliveryMode; // ENTREGA, RETIRO
  final String? deliveryAddress;
  final String? receiverName;
  final double total;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final String? notes;

  PedidoComercial({
    required this.id,
    required this.number,
    required this.clientId,
    required this.clientName,
    required this.state,
    required this.deliveryMode,
    this.deliveryAddress,
    this.receiverName,
    required this.total,
    this.expiresAt,
    required this.createdAt,
    this.notes,
  });

  bool get isEntregaDomicilio => deliveryMode == 'ENTREGA';
  bool get isListoParaDespacho => state == 'LISTO' || state == 'RESERVADO' || state == 'PARCIAL';

  factory PedidoComercial.fromJson(Map<String, dynamic> json) {
    return PedidoComercial(
      id: json['id']?.toString() ?? '',
      number: int.tryParse(json['number']?.toString() ?? '') ?? 0,
      clientId: json['client_id']?.toString() ?? json['clientId']?.toString() ?? '',
      clientName: json['client_name']?.toString() ?? json['clientName']?.toString() ?? 'Cliente',
      state: json['state']?.toString() ?? 'RESERVADO',
      deliveryMode: json['delivery_mode']?.toString() ?? json['deliveryMode']?.toString() ?? 'ENTREGA',
      deliveryAddress: json['delivery_address']?.toString() ?? json['deliveryAddress']?.toString(),
      receiverName: json['receiver_name']?.toString() ?? json['receiverName']?.toString(),
      total: double.tryParse(json['total']?.toString() ?? '') ?? 0.0,
      expiresAt: DateTime.tryParse((json['expires_at'] ?? json['expiresAt'] ?? '').toString()),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      notes: json['notes']?.toString(),
    );
  }
}

class ClienteComercial {
  final String id;
  final String name;
  final String? identification;
  final String? phone;
  final String? email;
  final String? address;
  final bool active;

  ClienteComercial({
    required this.id,
    required this.name,
    this.identification,
    this.phone,
    this.email,
    this.address,
    required this.active,
  });

  factory ClienteComercial.fromJson(Map<String, dynamic> json) {
    return ClienteComercial(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      identification: json['identification']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      address: json['address']?.toString(),
      active: json['active'] != false,
    );
  }
}
