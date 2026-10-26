class EventoAuditoria {
  final String id;
  final String? actorId;
  final String? targetId;
  final String action;
  final String detail;
  final DateTime? occurredAt;

  EventoAuditoria({
    required this.id,
    this.actorId,
    this.targetId,
    required this.action,
    required this.detail,
    this.occurredAt,
  });

  factory EventoAuditoria.fromJson(Map<String, dynamic> json) {
    return EventoAuditoria(
      id: json['id']?.toString() ?? '',
      actorId: json['actorId']?.toString(),
      targetId: json['targetId']?.toString(),
      action: json['action']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      occurredAt: json['occurredAt'] != null ? DateTime.tryParse(json['occurredAt'].toString()) : null,
    );
  }
}
