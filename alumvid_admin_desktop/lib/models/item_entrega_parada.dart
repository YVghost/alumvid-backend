class ItemEntregaParada {
  final String id;
  final String tipo; // 'INVENTARIO' o 'RETAZO'
  final String productoId;
  final String productoNombre;
  final String unidad;
  final double cantidad;
  final String? piezaId;
  final String? piezaCodigo;
  final double? piezaOriginalLengthM;
  final double? piezaOriginalWidthCm;
  final double? piezaOriginalHeightCm;
  final double? corteLengthM;
  final double? corteWidthCm;
  final double? corteHeightCm;
  final String descripcionVisible;

  ItemEntregaParada({
    required this.id,
    required this.tipo,
    required this.productoId,
    required this.productoNombre,
    required this.unidad,
    required this.cantidad,
    this.piezaId,
    this.piezaCodigo,
    this.piezaOriginalLengthM,
    this.piezaOriginalWidthCm,
    this.piezaOriginalHeightCm,
    this.corteLengthM,
    this.corteWidthCm,
    this.corteHeightCm,
    required this.descripcionVisible,
  });

  String toMetaTag() {
    if (tipo == 'INVENTARIO') {
      return '[META:PID=$productoId;QTY=$cantidad;NAME=$productoNombre]';
    } else {
      String corteInfo = '';
      if (corteLengthM != null) {
        corteInfo = ';CUT_LEN=$corteLengthM';
      } else if (corteWidthCm != null) {
        corteInfo = ';CUT_WID=$corteWidthCm;CUT_HEI=${corteHeightCm ?? corteWidthCm}';
      }
      return '[META:PID=$productoId;QTY=1;PIECE=${piezaId ?? ""}$corteInfo;NAME=$productoNombre]';
    }
  }

  static List<ItemEntregaParada> parseFromComentarios(String? comentarios) {
    if (comentarios == null || !comentarios.contains('[META:')) {
      return [];
    }
    final items = <ItemEntregaParada>[];
    final regex = RegExp(r'\[META:([^\]]+)\]');
    final matches = regex.allMatches(comentarios);

    for (final m in matches) {
      final meta = m.group(1)!;
      final map = <String, String>{};
      for (final pair in meta.split(';')) {
        final kv = pair.split('=');
        if (kv.length == 2) {
          map[kv[0].trim().toUpperCase()] = kv[1].trim();
        }
      }
      final pid = map['PID'] ?? '';
      final qty = double.tryParse(map['QTY'] ?? '1') ?? 1.0;
      final name = map['NAME'] ?? 'Material';
      final pieceId = map['PIECE'];
      final cutLen = double.tryParse(map['CUT_LEN'] ?? '');
      final cutWid = double.tryParse(map['CUT_WID'] ?? '');
      final cutHei = double.tryParse(map['CUT_HEI'] ?? '');

      if (pieceId != null && pieceId.isNotEmpty) {
        String desc = 'Retazo: $name';
        if (cutLen != null) {
          desc += ' (Corte: ${cutLen.toStringAsFixed(2)} m)';
        } else if (cutWid != null) {
          desc += ' (Corte: ${cutWid.toStringAsFixed(1)} × ${cutHei?.toStringAsFixed(1) ?? cutWid.toStringAsFixed(1)} cm)';
        } else {
          desc += ' (Pieza completa)';
        }
        items.add(ItemEntregaParada(
          id: '${DateTime.now().microsecondsSinceEpoch}_${items.length}',
          tipo: 'RETAZO',
          productoId: pid,
          productoNombre: name,
          unidad: 'UNIDAD',
          cantidad: 1,
          piezaId: pieceId,
          corteLengthM: cutLen,
          corteWidthCm: cutWid,
          corteHeightCm: cutHei,
          descripcionVisible: desc,
        ));
      } else {
        items.add(ItemEntregaParada(
          id: '${DateTime.now().microsecondsSinceEpoch}_${items.length}',
          tipo: 'INVENTARIO',
          productoId: pid,
          productoNombre: name,
          unidad: 'UNIDAD',
          cantidad: qty,
          descripcionVisible: '$name ($qty UNIDADES)',
        ));
      }
    }
    return items;
  }
}
