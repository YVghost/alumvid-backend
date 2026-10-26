import 'package:flutter/material.dart';
import 'models/user.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Verificar si ya existe una sesión activa de administrador
  AppUser? usuarioGuardado;
  final token = await ApiService.getToken();
  if (token != null && token.isNotEmpty) {
    usuarioGuardado = await ApiService.getCurrentUser();
  }

  runApp(AlumVidAdminApp(usuarioInicial: usuarioGuardado));
}

class AlumVidAdminApp extends StatelessWidget {
  final AppUser? usuarioInicial;

  const AlumVidAdminApp({super.key, this.usuarioInicial});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlumVid — Centro de Comando Logístico',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: usuarioInicial != null && usuarioInicial!.isAdmin
          ? AdminDashboardScreen(user: usuarioInicial!)
          : const LoginScreen(),
    );
  }
}
