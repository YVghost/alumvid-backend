/// Validación de cédula, RUC y teléfono de Ecuador (misma lógica que el backend:
/// IdentificacionEcuador.java en usuarios-service y pedidos-service).
library;

enum TipoIdentificacion { cedula, rucPersonaNatural, rucSociedadPrivada, rucEntidadPublica, consumidorFinal }

class InfoIdentificacion {
  const InfoIdentificacion._(this.valida, this.tipo, this.provincia, this.mensaje);
  factory InfoIdentificacion.error(String mensaje) => InfoIdentificacion._(false, null, null, mensaje);

  final bool valida;
  final TipoIdentificacion? tipo;
  final String? provincia;

  /// Descripción para mostrar: "Cédula de Pichincha" o el motivo del error.
  final String mensaje;

  bool get esRuc => tipo == TipoIdentificacion.rucPersonaNatural ||
      tipo == TipoIdentificacion.rucSociedadPrivada ||
      tipo == TipoIdentificacion.rucEntidadPublica;
}

const consumidorFinal = '9999999999999';

const _provincias = {
  1: 'Azuay', 2: 'Bolívar', 3: 'Cañar', 4: 'Carchi', 5: 'Cotopaxi', 6: 'Chimborazo', 7: 'El Oro',
  8: 'Esmeraldas', 9: 'Guayas', 10: 'Imbabura', 11: 'Loja', 12: 'Los Ríos', 13: 'Manabí',
  14: 'Morona Santiago', 15: 'Napo', 16: 'Pastaza', 17: 'Pichincha', 18: 'Tungurahua',
  19: 'Zamora Chinchipe', 20: 'Galápagos', 21: 'Sucumbíos', 22: 'Orellana',
  23: 'Santo Domingo de los Tsáchilas', 24: 'Santa Elena', 30: 'Ecuatorianos registrados en el exterior',
};

bool _cedulaValida(String c) {
  var suma = 0;
  for (var i = 0; i < 9; i++) {
    var d = int.parse(c[i]) * (i.isEven ? 2 : 1);
    suma += d > 9 ? d - 9 : d;
  }
  return (10 - suma % 10) % 10 == int.parse(c[9]);
}

int _modulo11(String v, List<int> coeficientes) {
  var suma = 0;
  for (var i = 0; i < coeficientes.length; i++) {
    suma += int.parse(v[i]) * coeficientes[i];
  }
  final r = suma % 11;
  return r == 0 ? 0 : 11 - r;
}

/// Analiza una cédula o RUC: si es válida, su tipo y la provincia de emisión.
InfoIdentificacion analizarIdentificacion(String? valor) {
  final v = (valor ?? '').trim();
  if (v.isEmpty) return InfoIdentificacion.error('Ingresa la cédula o RUC');
  if (!RegExp(r'^\d+$').hasMatch(v)) return InfoIdentificacion.error('La cédula o RUC solo admite números');
  if (v == consumidorFinal) {
    return const InfoIdentificacion._(true, TipoIdentificacion.consumidorFinal, null, 'Consumidor final');
  }
  if (v.length != 10 && v.length != 13) return InfoIdentificacion.error('La cédula tiene 10 dígitos y el RUC 13');
  final provincia = _provincias[int.parse(v.substring(0, 2))];
  if (provincia == null) return InfoIdentificacion.error('Código de provincia inválido (${v.substring(0, 2)})');
  final tercero = int.parse(v[2]);
  if (v.length == 10) {
    if (tercero > 5) return InfoIdentificacion.error('Una cédula tiene tercer dígito entre 0 y 5');
    return _cedulaValida(v)
        ? InfoIdentificacion._(true, TipoIdentificacion.cedula, provincia, 'Cédula de $provincia')
        : InfoIdentificacion.error('Cédula inválida: el dígito verificador no coincide');
  }
  if (tercero <= 5) {
    if (!_cedulaValida(v.substring(0, 10))) return InfoIdentificacion.error('RUC inválido: la cédula base no es válida');
    if (int.parse(v.substring(10)) < 1) return InfoIdentificacion.error('RUC inválido: establecimiento 000');
    return InfoIdentificacion._(true, TipoIdentificacion.rucPersonaNatural, provincia, 'RUC de persona natural de $provincia');
  }
  if (tercero == 6) {
    if (_modulo11(v, const [3, 2, 7, 6, 5, 4, 3, 2]) != int.parse(v[8])) {
      return InfoIdentificacion.error('RUC público inválido: el dígito verificador no coincide');
    }
    if (int.parse(v.substring(9)) < 1) return InfoIdentificacion.error('RUC inválido: establecimiento 0000');
    return InfoIdentificacion._(true, TipoIdentificacion.rucEntidadPublica, provincia, 'RUC de entidad pública de $provincia');
  }
  if (tercero == 9) {
    if (_modulo11(v, const [4, 3, 2, 7, 6, 5, 4, 3, 2]) != int.parse(v[9])) {
      return InfoIdentificacion.error('RUC de sociedad inválido: el dígito verificador no coincide');
    }
    if (int.parse(v.substring(10)) < 1) return InfoIdentificacion.error('RUC inválido: establecimiento 000');
    return InfoIdentificacion._(true, TipoIdentificacion.rucSociedadPrivada, provincia, 'RUC de sociedad privada de $provincia');
  }
  return InfoIdentificacion.error('Tercer dígito inválido para un RUC ($tercero)');
}

/// Teléfono de Ecuador normalizado (09XXXXXXXX o 0[2-7]XXXXXXX), o null si no es válido.
/// Un valor vacío devuelve ''.
String? normalizarTelefono(String? valor) {
  final v = (valor ?? '').trim();
  if (v.isEmpty) return '';
  if (!RegExp(r'^[+0-9 ()\-]+$').hasMatch(v)) return null;
  var d = v.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('593')) d = '0${d.substring(3)}';
  if (RegExp(r'^09\d{8}$').hasMatch(d) || RegExp(r'^0[2-7]\d{7}$').hasMatch(d)) return d;
  return null;
}

/// Validador de formulario para teléfonos (opcional salvo [obligatorio]).
String? validarTelefono(String? valor, {bool obligatorio = false}) {
  if ((valor ?? '').trim().isEmpty) return obligatorio ? 'Ingresa un teléfono' : null;
  if (!RegExp(r'^[+0-9 ()\-]+$').hasMatch(valor!.trim())) return 'Solo números';
  return normalizarTelefono(valor) == null ? 'Celular 09XXXXXXXX o fijo 02XXXXXXX' : null;
}

/// Validador de formulario para identificación. [soloCedula] para personas (usuarios).
String? validarIdentificacion(String? valor, {bool obligatorio = true, bool soloCedula = false}) {
  if ((valor ?? '').trim().isEmpty) return obligatorio ? (soloCedula ? 'Ingresa la cédula' : 'Ingresa la cédula o RUC') : null;
  final info = analizarIdentificacion(valor);
  if (!info.valida) return info.mensaje;
  if (soloCedula && info.tipo != TipoIdentificacion.cedula) return 'Debe ser una cédula (10 dígitos)';
  return null;
}
