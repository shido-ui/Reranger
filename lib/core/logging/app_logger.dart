import 'dart:developer' as developer;

/// Privacy-Preserving Application Logger.
/// Strictly enforces Invariant 6: Zero image pixel content, zero file payload logging,
/// and zero network telemetry.
class AppLogger {
  AppLogger._();

  static const String _name = 'Reranger';

  static void info(String message) {
    developer.log(
      message,
      name: _name,
      level: 800, // INFO
    );
  }

  static void warning(String message) {
    developer.log(
      message,
      name: _name,
      level: 900, // WARNING
    );
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _name,
      level: 1000, // SEVERE
      error: error,
      stackTrace: stackTrace,
    );
  }
}
