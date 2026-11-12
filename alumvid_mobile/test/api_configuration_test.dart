import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alumvid_mobile/services/api_service.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('Android emulator uses its host bridge', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(ApiService.baseUrl, 'http://10.0.2.2:8080/api/v1');
  });
  test('Desktop uses localhost', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(ApiService.baseUrl, 'http://localhost:8080/api/v1');
  });
  test('Logout conserva la configuracion ajena a la sesion', () async {
    SharedPreferences.setMockInitialValues({'driver_id': 'test', 'driver_name': 'Chofer', 'server_host_custom': 'http://example.test'});
    await ApiService.logout();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('driver_id'), isNull);
    expect(prefs.getString('driver_name'), isNull);
    expect(prefs.getString('server_host_custom'), 'http://example.test');
  });
}
