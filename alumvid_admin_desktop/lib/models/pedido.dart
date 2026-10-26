class Pedido {
  final String id;
  final String cliente;
  final String direccionTexto;
  final double latitudDestino;
  final double longitudDestino;
  final String estado; // PENDIENTE, EN_RUTA, ENTREGADO, CANCELADO
  final DateTime? fechaSolicitud;

  Pedido({
    required this.id,
    required this.cliente,
    required this.direccionTexto,
    required this.latitudDestino,
    required this.longitudDestino,
    required this.estado,
    this.fechaSolicitud,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) {
    DateTime? fecha;
    if (json['fechaSolicitud'] != null) {
      fecha = DateTime.tryParse(json['fechaSolicitud'].toString());
    }

    return Pedido(
      id: json['id']?.toString() ?? '',
      cliente: json['cliente']?.toString() ?? 'Cliente',
      direccionTexto: json['direccionTexto']?.toString() ?? '',
      latitudDestino: (json['latitudDestino'] as num?)?.toDouble() ?? 0.0,
      longitudDestino: (json['longitudDestino'] as num?)?.toDouble() ?? 0.0,
      estado: json['estado']?.toString() ?? 'PENDIENTE',
      fechaSolicitud: fecha,
    );
  }
}
