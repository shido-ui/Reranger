import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DeviceRamTier {
  flagship, // >= 8 GB RAM
  constrained, // 6 GB to 8 GB RAM
  unsupported, // < 6 GB RAM
}

/// In-app capability abstraction representing system and hardware state
/// without leaking low-level platform details into presentation widgets.
class AppCapabilities {
  final DeviceRamTier ramTier;
  final bool isOfflineOnly;
  final bool isClassicalEngineOperational;
  final bool isNeuralHumanizeSupported;
  final String activeAbi;
  final int totalRamGb;

  const AppCapabilities({
    required this.ramTier,
    required this.isOfflineOnly,
    required this.isClassicalEngineOperational,
    required this.isNeuralHumanizeSupported,
    required this.activeAbi,
    required this.totalRamGb,
  });

  /// Default baseline factory for supported Android ARM64 targets.
  factory AppCapabilities.defaultProfile() {
    return const AppCapabilities(
      ramTier: DeviceRamTier.flagship,
      isOfflineOnly: true,
      isClassicalEngineOperational: true,
      isNeuralHumanizeSupported: true,
      activeAbi: 'arm64-v8a',
      totalRamGb: 12,
    );
  }
}

/// Riverpod provider for application capabilities and device hardware status.
final appCapabilitiesProvider = Provider<AppCapabilities>((ref) {
  return AppCapabilities.defaultProfile();
});
