import 'chofer.dart';
import 'pedido.dart';

class Despacho {
  final String id;
  final String? rutaId;
  final int ordenParada;
  final Pedido? pedido;
  final Chofer? chofer;
  final DateTime? fechaAsignacion;
  final DateTime? fechaInicioRuta;
  final DateTime? fechaEntrega;
  final String? fotoPodUrl;
  final String? firmaUrl;
  final double? latitudEntrega;
  final double? longitudEntrega;
  final double? desviacionMetros;
  final bool? alertaDesviacion;
  final String estado; // PENDIENTE, EN_CURSO, ENTREGADO, CANCELADA
  final String? comentarios;

  Despacho({
    required this.id,
    this.rutaId,
    required this.ordenParada,
    this.pedido,
    this.chofer,
    this.fechaAsignacion,
    this.fechaInicioRuta,
    this.fechaEntrega,
    this.fotoPodUrl,
    this.firmaUrl,
    this.latitudEntrega,
    this.longitudEntrega,
    this.desviacionMetros,
    this.alertaDesviacion,
    required this.estado,
    this.comentarios,
  });

  bool get isEntregado => estado == 'ENTREGADO';
  bool get isEnCurso => estado == 'EN_CURSO';
  bool get hasAlertaDesviacion => alertaDesviacion == true;
  String get pedidoId => pedido?.id ?? id;

  factory Despacho.fromJson(Map<String, dynamic> json) {
    return Despacho(
      id: json['id']?.toString() ?? '',
      rutaId: json['rutaId']?.toString(),
      ordenParada: (json['ordenParada'] as num?)?.toInt() ?? 1,
      pedido: json['pedido'] != null ? Pedido.fromJson(json['pedido']) : null,
      chofer: json['chofer'] != null ? Chofer.fromJson(json['chofer']) : null,
      fechaAsignacion: json['fechaAsignacion'] != null ? DateTime.tryParse(json['fechaAsignacion'].toString()) : null,
      fechaInicioRuta: json['fechaInicioRuta'] != null ? DateTime.tryParse(json['fechaInicioRuta'].toString()) : null,
      fechaEntrega: json['fechaEntrega'] != null ? DateTime.tryParse(json['fechaEntrega'].toString()) : null,
      fotoPodUrl: json['fotoPodUrl']?.toString(),
      firmaUrl: json['firmaUrl']?.toString(),
      latitudEntrega: (json['latitudEntrega'] as num?)?.toDouble(),
      longitudEntrega: (json['longitudEntrega'] as num?)?.toDouble(),
      desviacionMetros: (json['desviacionMetros'] as num?)?.toDouble(),
      alertaDesviacion: json['alertaDesviacion'] == true,
      estado: json['estado']?.toString() ?? 'PENDIENTE',
      comentarios: json['comentarios']?.toString(),
    );
  }
}
