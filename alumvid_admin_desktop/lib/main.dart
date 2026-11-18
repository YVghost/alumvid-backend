import 'screens/cambiar_password_screen.dart';
import 'package:flutter/material.dart';
import 'models/user.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Apariencia.instancia.cargar();

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
    Theme.of(context); // Rebuild semantic colors when the appearance changes.

    return ListenableBuilder(
      listenable: Apariencia.instancia,
      builder: (context, _) => MaterialApp(
        title: 'AlumVid — Centro de Comando Logístico',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: Apariencia.instancia.modo,
        home: usuarioInicial != null && usuarioInicial!.isAdmin
            ? (usuarioInicial!.mustChangePassword
                  ? const CambiarPasswordScreen()
                  : AdminDashboardScreen(user: usuarioInicial!))
            : const LoginScreen(),
      ),
    );
  }
}
