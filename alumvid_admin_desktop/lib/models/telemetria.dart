class TelemetriaGps {
  final String? choferId;
  final String? despachoId;
  final double latitud;
  final double longitud;
  final double velocidadKmh;
  final double rumbo;
  final String? choferNombre;
  final int timestamp;

  TelemetriaGps({
    this.choferId,
    this.despachoId,
    required this.latitud,
    required this.longitud,
    required this.velocidadKmh,
    required this.rumbo,
    this.choferNombre,
    required this.timestamp,
  });

  factory TelemetriaGps.fromJson(Map<String, dynamic> json) {
    return TelemetriaGps(
      choferId: json['choferId']?.toString(),
      despachoId: json['despachoId']?.toString(),
      latitud: (json['latitud'] as num?)?.toDouble() ?? 0.0,
      longitud: (json['longitud'] as num?)?.toDouble() ?? 0.0,
      velocidadKmh: (json['velocidadKmh'] as num?)?.toDouble() ?? 0.0,
      rumbo: (json['rumbo'] as num?)?.toDouble() ?? 0.0,
      choferNombre: json['choferNombre']?.toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
