import 'despacho.dart';

class Ruta {
  final String id;
  final String codigoRuta;
  final String? choferId;
  final String? choferNombre;
  final String? choferTelefono;
  final String estado; // PENDIENTE, EN_CURSO, COMPLETADA, CANCELADA
  final DateTime? fechaCreacion;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final String? comentarios;
  final List<Despacho> paradas;

  Ruta({
    required this.id,
    required this.codigoRuta,
    this.choferId,
    this.choferNombre,
    this.choferTelefono,
    required this.estado,
    this.fechaCreacion,
    this.fechaInicio,
    this.fechaFin,
    this.comentarios,
    required this.paradas,
  });

  bool get isEnCurso => estado == 'EN_CURSO';
  bool get isPendiente => estado == 'PENDIENTE';
  bool get isCompletada => estado == 'COMPLETADA';

  int get totalParadas => paradas.length;
  int get paradasEntregadas => paradas.where((p) => p.isEntregado).length;
  double get porcentajeAvance => totalParadas == 0 ? 0.0 : (paradasEntregadas / totalParadas);

  factory Ruta.fromJson(Map<String, dynamic> json) {
    List<Despacho> listaParadas = [];
    if (json['paradas'] is List) {
      listaParadas = (json['paradas'] as List).map((p) => Despacho.fromJson(p)).toList();
      listaParadas.sort((a, b) => a.ordenParada.compareTo(b.ordenParada));
    }

    return Ruta(
      id: json['id']?.toString() ?? '',
      codigoRuta: json['codigoRuta']?.toString() ?? 'Ruta',
      choferId: json['choferId']?.toString(),
      choferNombre: json['choferNombre']?.toString(),
      choferTelefono: json['choferTelefono']?.toString(),
      estado: json['estado']?.toString() ?? 'PENDIENTE',
      fechaCreacion: json['fechaCreacion'] != null ? DateTime.tryParse(json['fechaCreacion'].toString()) : null,
      fechaInicio: json['fechaInicio'] != null ? DateTime.tryParse(json['fechaInicio'].toString()) : null,
      fechaFin: json['fechaFin'] != null ? DateTime.tryParse(json['fechaFin'].toString()) : null,
      comentarios: json['comentarios']?.toString(),
      paradas: listaParadas,
    );
  }
}
