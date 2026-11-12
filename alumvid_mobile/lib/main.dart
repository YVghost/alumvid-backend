import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/sesion.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await ApiService.initialize();
  // Si hay una sesión guardada y válida se entra directo (sin volver a escribir la clave).
  Sesion? sesion;
  try {
    sesion = await Sesion.restaurar();
  } catch (_) {
    sesion = null;
  }
  runApp(AlumVidApp(sesion: sesion));
}

class AlumVidApp extends StatelessWidget {
  const AlumVidApp({super.key, this.sesion});
  final Sesion? sesion;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlumVid',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: sesion == null ? const LoginScreen() : pantallaInicial(sesion!),
    );
  }
}
