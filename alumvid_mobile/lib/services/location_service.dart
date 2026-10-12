import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Position> determinarPosicionActual() async {
    bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      throw Exception('El servicio de localizacion GPS se encuentra desactivado en el dispositivo.');
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        throw Exception('Los permisos de localizacion GPS fueron denegados por el usuario.');
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      throw Exception('Los permisos de localizacion estan permanentemente bloqueados en la configuracion del sistema.');
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 4),
      ),
    );
  }
}
