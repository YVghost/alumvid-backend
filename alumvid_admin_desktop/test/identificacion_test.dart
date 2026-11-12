import 'package:alumvid_admin_desktop/shared/identificacion.dart';
import 'package:flutter_test/flutter_test.dart';

// Mismos vectores sintéticos que IdentificacionEcuadorTest.java (backend).
void main() {
  test('cédulas válidas indican provincia', () {
    final r = analizarIdentificacion('1712345675');
    expect(r.valida, isTrue);
    expect(r.tipo, TipoIdentificacion.cedula);
    expect(r.provincia, 'Pichincha');
    expect(analizarIdentificacion('0912345675').provincia, 'Guayas');
    expect(analizarIdentificacion('3011111113').provincia, 'Ecuatorianos registrados en el exterior');
  });

  test('RUC por tipo', () {
    expect(analizarIdentificacion('1712345675001').tipo, TipoIdentificacion.rucPersonaNatural);
    expect(analizarIdentificacion('1791234561001').tipo, TipoIdentificacion.rucSociedadPrivada);
    expect(analizarIdentificacion('1760000150001').tipo, TipoIdentificacion.rucEntidadPublica);
    expect(analizarIdentificacion('9999999999999').tipo, TipoIdentificacion.consumidorFinal);
  });

  test('rechaza letras y números mal formados', () {
    for (final malo in ['hola', 'r', 'DEMO-1', '17123456A5', '0000000000', '1712345670', '2512345675',
        '1762345675', '171234567', '1712345675000', '1791234560001', '1760000190001']) {
      expect(analizarIdentificacion(malo).valida, isFalse, reason: malo);
    }
    expect(validarIdentificacion('1712345675001', soloCedula: true), isNotNull);
  });

  test('teléfonos', () {
    expect(normalizarTelefono('+593 99 123 4567'), '0991234567');
    expect(normalizarTelefono('(02) 234-5678'), '022345678');
    for (final malo in ['abc', '099123456a', '12345', '0812345678']) {
      expect(normalizarTelefono(malo), isNull, reason: malo);
    }
    expect(validarTelefono(''), isNull);
    expect(validarTelefono('abc'), 'Solo números');
  });
}
