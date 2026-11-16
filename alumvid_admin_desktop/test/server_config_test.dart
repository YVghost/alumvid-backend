import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alumvid_admin_desktop/shared/server_config.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart';

void main() {
  test('Railway HTTPS usa WSS y conserva el dominio sin añadir 8083', () {
    expect(
      ServerConfig.websocket('https://api.up.railway.app').toString(),
      'wss://api.up.railway.app/ws-logistica',
    );
    expect(
      ServerConfig.websocket(
        'https://api.up.railway.app/api/v1',
        sockJs: true,
      ).toString(),
      'wss://api.up.railway.app/ws-logistica/websocket',
    );
    expect(
      ServerConfig.websocket('https://api.up.railway.app:8443').port,
      8443,
    );
  });
  test('El entorno local conserva el broker directo', () {
    expect(
      ServerConfig.websocket('http://192.168.1.10:8080').toString(),
      'ws://192.168.1.10:8083/ws-logistica',
    );
    expect(
      ServerConfig.host('https://api.up.railway.app/api/v1/'),
      'https://api.up.railway.app',
    );
    expect(
      () => ServerConfig.host('https://user:password@api.test'),
      throwsFormatException,
    );
  });
  test(
    'Se puede alternar Railway y local sin sobrescribir perfiles ni sesiones sincronizadas',
    () async {
      SharedPreferences.setMockInitialValues({
        'admin_auth_token': 'synchronized-token',
      });
      await ApiService.setBaseHost('https://api.up.railway.app');
      await ApiService.setBaseHost('http://localhost:8080');
      expect(await ApiService.getRailwayServer(), 'https://api.up.railway.app');
      expect(await ApiService.getLocalServer(), 'http://localhost:8080');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('admin_auth_token'), 'synchronized-token');
    },
  );
}
