import 'package:flutter/material.dart';
import 'package:engreader/screens/main_layout.dart';
import 'package:engreader/screens/settings_screen.dart';

class EngReaderApp extends StatelessWidget {
  const EngReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EngReader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF3478F6),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF1C1C1E),
          surfaceContainerLow: Color(0xFFF2F2F7),
          outline: Color(0xFFD1D1D6),
          outlineVariant: Color(0xFFE5E5EA),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5A9CFF),
          onPrimary: Colors.white,
          surface: Color(0xFF1C1C1E),
          onSurface: Color(0xFFF2F2F7),
          surfaceContainerLow: Color(0xFF2C2C2E),
          outline: Color(0xFF48484A),
          outlineVariant: Color(0xFF3A3A3C),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1C1C1E),
      ),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (context) => const MainLayout(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
