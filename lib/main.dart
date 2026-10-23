import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/errors/error_boundary.dart';
import 'core/logging/app_logger.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Custom global error boundary catching layout and rendering errors
  ErrorWidget.builder = (FlutterErrorDetails details) {
    AppLogger.error(
      'Unhandled UI exception in ErrorWidget builder',
      details.exception,
      details.stack,
    );
    return ErrorBoundary(details: details);
  };

  AppLogger.info(
    'Starting Reranger Application (Offline-First Creative Studio)',
  );
  runApp(const ProviderScope(child: RerangerApp()));
}

class RerangerApp extends StatelessWidget {
  const RerangerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Reranger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Default studio dark theme
      routerConfig: appRouter,
    );
  }
}
