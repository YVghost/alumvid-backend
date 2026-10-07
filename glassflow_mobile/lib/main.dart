import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const GlassFlowApp());
}

class GlassFlowApp extends StatelessWidget {
  const GlassFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GlassFlow Chofer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        primaryColor: const Color(0xFF2563EB),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2563EB),
          secondary: Color(0xFF059669),
          surface: Color(0xFF111827),
        ),
        fontFamily: 'sans-serif',
      ),
      home: const LoginScreen(),
    );
  }
}
