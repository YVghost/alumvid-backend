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
}
