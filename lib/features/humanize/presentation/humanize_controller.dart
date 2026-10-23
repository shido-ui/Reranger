import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../../../humanize/humanize_adapter.dart';
import '../../../humanize/local_humanize_adapter.dart';

/// Exactly 3 verified plain-language looks mapping to concrete latent strengths.
enum HumanizeLook {
  naturalistic(
    displayName: 'Naturalistic',
    description: 'De-glazes plastic AI skin; restores subtle micro-texture.',
    defaultStrength: 0.20,
    defaultPreserveComposition: true,
  ),
  handPainted(
    displayName: 'Hand-painted',
    description: 'Softens digital edges with organic painterly brush tooth.',
    defaultStrength: 0.35,
    defaultPreserveComposition: true,
  ),
  artistic(
    displayName: 'Artistic Reinterpretation',
    description: 'Expressive re-synthesis with dynamic lighting and textures.',
    defaultStrength: 0.55,
    defaultPreserveComposition: false,
  );

  final String displayName;
  final String description;
  final double defaultStrength;
  final bool defaultPreserveComposition;

  const HumanizeLook({
    required this.displayName,
    required this.description,
    required this.defaultStrength,
    required this.defaultPreserveComposition,
  });
}

/// Authentic observable UI status values.
enum HumanizeUiStatus {
  initial,
  idle,
  unsupportedHardware,
  modelNotInstalled,
  loadingModel,
  running,
  completed,
  cancelled,
  error,
}

/// State controller managing Humanize Studio UX, parameters, and lifecycle.
class HumanizeController extends ChangeNotifier {
  final HumanizeAdapter _adapter;

  HumanizeUiStatus _status = HumanizeUiStatus.initial;
  HumanizeLook _selectedLook = HumanizeLook.naturalistic;
  double _strength = HumanizeLook.naturalistic.defaultStrength;
  bool _preserveComposition = true;
  String _prompt = '';
  String _negativePrompt = 'plastic, artificial, blur, oversaturated';
  int? _seed = 42;

  bool _isComparing = false;
  HumanizeProgress? _progress;
  String? _errorMessage;
  String? _unavailabilityReason;

  Uint8List? _sourceImageBytes;
  Uint8List? _resultImageBytes;
  int _sourceWidth = 512;
  int _sourceHeight = 512;

  CancellationToken? _cancelToken;

  HumanizeController({HumanizeAdapter? adapter})
    : _adapter = adapter ?? LocalHumanizeAdapter();

  HumanizeUiStatus get status => _status;
  HumanizeLook get selectedLook => _selectedLook;
  double get strength => _strength;
  bool get preserveComposition => _preserveComposition;
  String get prompt => _prompt;
  String get negativePrompt => _negativePrompt;
  int? get seed => _seed;
  bool get isComparing => _isComparing;
  HumanizeProgress? get progress => _progress;
  String? get errorMessage => _errorMessage;
  String? get unavailabilityReason => _unavailabilityReason;
  Uint8List? get sourceImageBytes => _sourceImageBytes;
  Uint8List? get resultImageBytes => _resultImageBytes;
  int get sourceWidth => _sourceWidth;
  int get sourceHeight => _sourceHeight;

  /// Returns PNG-encoded bytes suitable for Flutter image display.
  Uint8List? get displaySourceBytes {
    if (_sourceImageBytes == null) return null;
    if (_sourceImageBytes!.length == _sourceWidth * _sourceHeight * 4) {
      final image = img.Image.fromBytes(
        width: _sourceWidth,
        height: _sourceHeight,
        bytes: _sourceImageBytes!.buffer,
        order: img.ChannelOrder.rgba,
      );
      return Uint8List.fromList(img.encodePng(image));
    }
    return _sourceImageBytes;
  }

  bool get isRunning => _status == HumanizeUiStatus.running;
  bool get isGated =>
      _status == HumanizeUiStatus.unsupportedHardware ||
      _status == HumanizeUiStatus.modelNotInstalled;

  /// Initializes controller, verifies capabilities, and checks hardware gating.
  Future<void> initialize({
    required Uint8List sourceImageBytes,
    required int width,
    required int height,
  }) async {
    _sourceImageBytes = sourceImageBytes;
    _sourceWidth = width;
    _sourceHeight = height;

    try {
      final caps = await _adapter.getCapabilities();
      if (!caps.isSupported) {
        if (caps.hardwareTier == HardwareTier.unsupportedOomRisk) {
          _status = HumanizeUiStatus.unsupportedHardware;
        } else {
          _status = HumanizeUiStatus.modelNotInstalled;
        }
        _unavailabilityReason = caps.unavailabilityReason ?? 'Humanize Studio is currently unavailable. No verified on-device neural diffusion weights are installed.';
      } else {
        final hasModel = await _adapter.isModelAvailable();
        if (!hasModel &&
            _adapter.lifecycleState != HumanizeLifecycleState.ready) {
          _status = HumanizeUiStatus.modelNotInstalled;
          _unavailabilityReason =
              'Humanize neural model weights are not installed on device. '
              'In accordance with Invariants 7 & 9, placeholder arithmetic or simulated filters cannot be presented as neural inference.';
        } else {
          _status = HumanizeUiStatus.idle;
        }
      }
    } catch (e) {
      _status = HumanizeUiStatus.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Selects one of the 3 plain-language looks, updating default strength and anchoring.
  void selectLook(HumanizeLook look) {
    if (isRunning) return;
    _selectedLook = look;
    _strength = look.defaultStrength;
    _preserveComposition = look.defaultPreserveComposition;
    notifyListeners();
  }

  /// Sets transformation strength parameter ($s \in [0.0, 1.0]$).
  void setStrength(double value) {
    if (isRunning) return;
    _strength = value.clamp(0.0, 1.0);
    // If composition preservation is active, guide beginners to stay <= 0.35
    if (_preserveComposition && _strength > 0.35) {
      _preserveComposition = false;
    }
    notifyListeners();
  }

  /// Toggles composition preservation anchor ($z_0$).
  void setPreserveComposition(bool value) {
    if (isRunning) return;
    _preserveComposition = value;
    if (_preserveComposition && _strength > 0.35) {
      _strength = 0.35;
    }
    notifyListeners();
  }

  void setPrompt(String value) {
    _prompt = value;
    notifyListeners();
  }

  void setNegativePrompt(String value) {
    _negativePrompt = value;
    notifyListeners();
  }

  void setSeed(int? value) {
    _seed = value;
    notifyListeners();
  }

  void setComparing(bool comparing) {
    _isComparing = comparing;
    notifyListeners();
  }

  /// Runs non-blocking cancellable on-device neural transformation.
  Future<void> humanize() async {
    if (_sourceImageBytes == null || isRunning) return;

    final caps = await _adapter.getCapabilities();
    if (!caps.isSupported) {
      _status = HumanizeUiStatus.unsupportedHardware;
      _unavailabilityReason = caps.unavailabilityReason;
      notifyListeners();
      return;
    }

    _status = HumanizeUiStatus.running;
    _errorMessage = null;
    _cancelToken = CancellationToken();
    notifyListeners();

    try {
      Uint8List rawRgba;
      if (_sourceImageBytes!.length == _sourceWidth * _sourceHeight * 4) {
        rawRgba = _sourceImageBytes!;
      } else {
        final decoded = img.decodeImage(_sourceImageBytes!);
        if (decoded != null) {
          rawRgba = decoded.getBytes(order: img.ChannelOrder.rgba);
        } else {
          rawRgba = _sourceImageBytes!;
        }
      }

      final input = HumanizeInput(
        sourceRgba: rawRgba,
        width: _sourceWidth,
        height: _sourceHeight,
        strength: _strength,
        prompt: _prompt,
        negativePrompt: _negativePrompt,
        seed: _seed ?? DateTime.now().millisecondsSinceEpoch,
        steps: 6,
      );

      final result = await _adapter.runInference(
        input,
        cancelToken: _cancelToken,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );

      final outImage = img.Image.fromBytes(
        width: result.width,
        height: result.height,
        bytes: result.outputRgba.buffer,
        order: img.ChannelOrder.rgba,
      );
      _resultImageBytes = Uint8List.fromList(img.encodePng(outImage));
      _status = HumanizeUiStatus.completed;
    } on InferenceCancelledException {
      _status = HumanizeUiStatus.cancelled;
    } on HardwareTierUnsupportedException catch (e) {
      _status = HumanizeUiStatus.unsupportedHardware;
      _unavailabilityReason = e.message;
    } on ModelNotFoundException catch (e) {
      _status = HumanizeUiStatus.modelNotInstalled;
      _unavailabilityReason = e.message;
    } on ModelNotLoadedException catch (e) {
      _status = HumanizeUiStatus.modelNotInstalled;
      _unavailabilityReason = e.message;
    } catch (e) {
      _status = HumanizeUiStatus.error;
      _errorMessage = e.toString();
    } finally {
      _cancelToken = null;
      notifyListeners();
    }
  }

  /// Cancels in-progress neural inference immediately.
  void cancel() {
    if (!isRunning) return;
    _cancelToken?.cancel();
    _status = HumanizeUiStatus.cancelled;
    notifyListeners();
  }

  /// Forwards app lifecycle state changes to reclaim volatile memory.
  Future<void> onAppLifecycleChanged(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (isRunning) {
        cancel();
      }
      await _adapter.onAppBackgrounded();
    }
  }
}
