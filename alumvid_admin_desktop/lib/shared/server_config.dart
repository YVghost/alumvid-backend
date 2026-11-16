/// URLs públicas de las apps. Nunca contiene contraseñas de base de datos.
class ServerConfig {
  static String host(String input) {
    final u = Uri.tryParse(input.trim());
    if (u == null ||
        !['http', 'https'].contains(u.scheme) ||
        u.host.isEmpty ||
        u.userInfo.isNotEmpty ||
        u.hasQuery ||
        u.hasFragment ||
        !['', '/', '/api/v1', '/api/v1/'].contains(u.path)) {
      throw const FormatException(
        'Usa http://IP-PC:8080 o https://tu-gateway.up.railway.app',
      );
    }
    return u.replace(path: '').toString().replaceFirst(RegExp(r'/+$'), '');
  }

  static bool isLocal(Uri u) {
    final h = u.host.toLowerCase();
    if (h == 'localhost' || h == '::1' || h.endsWith('.local')) return true;
    final p = h.split('.').map(int.tryParse).toList();
    return p.length == 4 &&
        p.every((v) => v != null) &&
        (p[0] == 10 ||
            p[0] == 127 ||
            (p[0] == 192 && p[1] == 168) ||
            (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31));
  }

  static Uri websocket(String base, {bool sockJs = false}) {
    final u = Uri.parse(host(base));
    // Mantener compatibilidad local con el broker directo; Railway usa WSS por el dominio público.
    final directLocal =
        u.scheme == 'http' && isLocal(u) && [8080, 8085].contains(u.port);
    return u.replace(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      port: directLocal
          ? 8083
          : u.hasPort
          ? u.port
          : null,
      path: sockJs ? '/ws-logistica/websocket' : '/ws-logistica',
    );
  }
}
