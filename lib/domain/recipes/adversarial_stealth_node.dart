import 'dart:typed_data';

import 'render_graph_node.dart';
import 'render_pipeline_failure.dart';

/// Robust Stealth Engine V2:
/// ARMOR (Universal Adversarial Perturbation) node applying targeted frequency-domain
/// perturbations in the DCT (Discrete Cosine Transform) domain to alter CNN-based AI detector
/// confidence scores (e.g., ZeroGPT, Hive, AI or Not) without causing visible color banding (SSIM > 0.95).
class ARMORAttackNode extends RenderGraphNode {
  static const String nodeType = 'ARMORAttackNode';

  final double strength; // Perturbation magnitude in [0.0, 1.0]
  final bool applyFrequencyPerturbation;
  final bool multiDomain;
  final bool latentSanitization;
  final double maxLInf;
  final bool useEot;
  final bool bilateralSanitization;

  ARMORAttackNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.strength = 0.5,
    this.applyFrequencyPerturbation = true,
    this.multiDomain = true,
    this.latentSanitization = true,
    this.maxLInf = 16.0,
    this.useEot = true,
    this.bilateralSanitization = true,
    String? type,
  }) : super(
         type: type ?? nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'strength': strength,
           'applyFrequencyPerturbation': applyFrequencyPerturbation,
           'multiDomain': multiDomain,
           'latentSanitization': latentSanitization,
           'maxLInf': maxLInf,
           'useEot': useEot,
           'bilateralSanitization': bilateralSanitization,
         },
       );

  @override
  void validate() {
    if (inputNodeIds.length != 1) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds.length,
        expectedCriteria: 'Exactly 1 upstream input node',
      );
    }
    if (strength < 0.0 || strength > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'strength',
        actualValue: strength,
        expectedCriteria: 'Floating point value in [0.0, 1.0]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory ARMORAttackNode.fromJson(Map<String, dynamic> json) {
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return ARMORAttackNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: (json['inputNodeIds'] as List<dynamic>).first as String,
      strength: (params['strength'] as num?)?.toDouble() ?? 0.5,
      applyFrequencyPerturbation:
          params['applyFrequencyPerturbation'] as bool? ?? true,
      multiDomain: params['multiDomain'] as bool? ?? true,
      latentSanitization: params['latentSanitization'] as bool? ?? true,
      maxLInf: (params['maxLInf'] as num?)?.toDouble() ?? 16.0,
      useEot: params['useEot'] as bool? ?? true,
      bilateralSanitization: params['bilateralSanitization'] as bool? ?? true,
    );
  }
}

/// Backward compatibility alias for legacy serialized graphs
@Deprecated('Use ARMORAttackNode instead for Robust Stealth Engine V2')
class AdversarialStealthNode extends ARMORAttackNode {
  static const String legacyNodeType = 'AdversarialStealthNode';

  AdversarialStealthNode({
    required super.id,
    super.version = 1,
    required super.inputNodeId,
    super.strength = 0.5,
    super.applyFrequencyPerturbation = true,
  }) : super(type: legacyNodeType);

  factory AdversarialStealthNode.fromJson(Map<String, dynamic> json) {
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return AdversarialStealthNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: (json['inputNodeIds'] as List<dynamic>).first as String,
      strength: (params['strength'] as num?)?.toDouble() ?? 0.5,
      applyFrequencyPerturbation:
          params['applyFrequencyPerturbation'] as bool? ?? true,
    );
  }
}

/// Robust Stealth Engine V2 Realism Fusion node:
/// Injects simulated Bayer pattern sensel noise and subtle radial chromatic aberration.
/// Masks adversarial perturbations as legitimate camera hardware sensor/lens artifacts.
class SensorNoiseNode extends RenderGraphNode {
  static const String nodeType = 'SensorNoiseNode';

  final double noiseIntensity; // Bayer CFA shot noise intensity in [0.0, 1.0]
  final double
  chromaticAberration; // Radial lens chromatic dispersion in [0.0, 1.0]

  SensorNoiseNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.noiseIntensity = 0.3,
    this.chromaticAberration = 0.3,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'noiseIntensity': noiseIntensity,
           'chromaticAberration': chromaticAberration,
         },
       );

  @override
  void validate() {
    if (inputNodeIds.length != 1) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds.length,
        expectedCriteria: 'Exactly 1 upstream input node',
      );
    }
    if (noiseIntensity < 0.0 || noiseIntensity > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'noiseIntensity',
        actualValue: noiseIntensity,
        expectedCriteria: 'Floating point value in [0.0, 1.0]',
      );
    }
    if (chromaticAberration < 0.0 || chromaticAberration > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'chromaticAberration',
        actualValue: chromaticAberration,
        expectedCriteria: 'Floating point value in [0.0, 1.0]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory SensorNoiseNode.fromJson(Map<String, dynamic> json) {
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return SensorNoiseNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: (json['inputNodeIds'] as List<dynamic>).first as String,
      noiseIntensity: (params['noiseIntensity'] as num?)?.toDouble() ?? 0.3,
      chromaticAberration:
          (params['chromaticAberration'] as num?)?.toDouble() ?? 0.3,
    );
  }
}

/// Metadata Annihilation Utility:
/// Strips 100% of EXIF, XMP, and C2PA / JUMBF chunks from image byte streams (JPEG, PNG, or raw streams).
class MetadataAnnihilator {
  static const List<int> _c2paMagic = [0x63, 0x32, 0x70, 0x61]; // 'c2pa'
  static const List<int> _jumbMagic = [0x6a, 0x75, 0x6d, 0x62]; // 'jumb'
  static const List<int> _c2xxMagic = [0x63, 0x32, 0x78, 0x78]; // 'c2xx'

  static int _indexOfSequence(List<int> data, List<int> seq, [int start = 0]) {
    if (seq.isEmpty || data.length < seq.length) return -1;
    for (int i = start; i <= data.length - seq.length; i++) {
      bool match = true;
      for (int j = 0; j < seq.length; j++) {
        if (data[i + j] != seq[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  /// Strips 100% of EXIF, XMP, and C2PA metadata from [bytes].
  /// Explicit named function matching operating contract mandates.
  static Uint8List stripMetadata(Uint8List bytes) => strip(bytes);

  /// Strips 100% of EXIF, XMP, and C2PA metadata from [bytes].
  static Uint8List strip(Uint8List bytes) {
    if (bytes.length < 4) return bytes;

    // 1. JPEG: SOI is 0xFF, 0xD8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      final out = BytesBuilder(copy: false);
      out.addByte(0xFF);
      out.addByte(0xD8);

      int pos = 2;
      while (pos + 1 < bytes.length) {
        if (bytes[pos] != 0xFF) {
          pos++;
          continue;
        }
        final m = bytes[pos + 1];
        if (m == 0xFF || m == 0x00) {
          pos++;
          continue;
        }
        if (m == 0xD9) {
          // EOI
          out.addByte(0xFF);
          out.addByte(0xD9);
          break;
        }
        if (m >= 0xD0 && m <= 0xD7) {
          // RST
          out.addByte(0xFF);
          out.addByte(m);
          pos += 2;
          continue;
        }
        if (pos + 3 >= bytes.length) break;
        final segLen = (bytes[pos + 2] << 8) | bytes[pos + 3];
        if (pos + 2 + segLen > bytes.length) break;

        // APP1 (EXIF/XMP), APP11 (C2PA/JUMBF), APP13 (IPTC), COM
        bool shouldStrip = (m == 0xE1 || m == 0xEB || m == 0xED || m == 0xFE);
        if (!shouldStrip && m >= 0xE0 && m <= 0xEF) {
          final payload = bytes.sublist(pos + 4, pos + 2 + segLen);
          if (_indexOfSequence(payload, [0x45, 0x78, 0x69, 0x66]) !=
                  -1 || // Exif
              _indexOfSequence(payload, _c2paMagic) != -1 ||
              _indexOfSequence(payload, _jumbMagic) != -1 ||
              _indexOfSequence(payload, [0x4A, 0x50, 0x55, 0x4D]) != -1) {
            // JPUM
            shouldStrip = true;
          }
        }

        if (m == 0xDA) {
          // SOS (Start of Scan)
          out.add(bytes.sublist(pos, pos + 2 + segLen));
          pos += 2 + segLen;

          while (pos < bytes.length) {
            if (bytes[pos] == 0xFF && pos + 1 < bytes.length) {
              final nextM = bytes[pos + 1];
              if (nextM == 0xD9) {
                // EOI
                out.addByte(0xFF);
                out.addByte(0xD9);
                pos += 2;
                break;
              } else if (nextM == 0x00 || (nextM >= 0xD0 && nextM <= 0xD7)) {
                out.addByte(0xFF);
                out.addByte(nextM);
                pos += 2;
                continue;
              } else {
                break;
              }
            } else {
              out.addByte(bytes[pos]);
              pos++;
            }
          }
          continue;
        }

        if (!shouldStrip) {
          out.add(bytes.sublist(pos, pos + 2 + segLen));
        }
        pos += 2 + segLen;
      }
      return out.toBytes();
    }

    // 2. PNG: Signature is 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      final out = BytesBuilder(copy: false);
      out.add(bytes.sublist(0, 8));

      int pos = 8;
      while (pos + 12 <= bytes.length) {
        final chunkLen =
            (bytes[pos] << 24) |
            (bytes[pos + 1] << 16) |
            (bytes[pos + 2] << 8) |
            bytes[pos + 3];
        final totalChunk = 12 + chunkLen;
        if (pos + totalChunk > bytes.length) break;

        final chunkTypeStr = String.fromCharCodes(
          bytes.sublist(pos + 4, pos + 8),
        );
        bool shouldStrip = false;
        if (chunkTypeStr == 'eXIf' ||
            chunkTypeStr == 'iTXt' ||
            chunkTypeStr == 'tEXt' ||
            chunkTypeStr == 'zTXt' ||
            chunkTypeStr == 'c2pa' ||
            chunkTypeStr == 'caBX' ||
            chunkTypeStr == 'jumb') {
          shouldStrip = true;
        } else if (chunkLen > 0) {
          final cdata = bytes.sublist(pos + 8, pos + 8 + chunkLen);
          if (_indexOfSequence(cdata, _c2paMagic) != -1 ||
              _indexOfSequence(cdata, _jumbMagic) != -1) {
            shouldStrip = true;
          }
        }

        if (!shouldStrip) {
          out.add(bytes.sublist(pos, pos + totalChunk));
        }
        pos += totalChunk;
        if (chunkTypeStr == 'IEND') break;
      }
      return out.toBytes();
    }

    // 3. Generic / Simulated payload: Excise any C2PA / JUMBF boxes
    final out = BytesBuilder(copy: false);
    int i = 0;
    while (i < bytes.length) {
      if (i + 4 <= bytes.length &&
          (_matches(bytes, i, _c2paMagic) ||
              _matches(bytes, i, _jumbMagic) ||
              _matches(bytes, i, _c2xxMagic))) {
        i += 4;
        int skip = 0;
        while (i < bytes.length &&
            skip < 16 &&
            bytes[i] != 0xFF &&
            bytes[i] != 0x89) {
          i++;
          skip++;
        }
        continue;
      }
      out.addByte(bytes[i]);
      i++;
    }
    return out.toBytes();
  }

  static bool _matches(List<int> data, int offset, List<int> seq) {
    if (offset + seq.length > data.length) return false;
    for (int j = 0; j < seq.length; j++) {
      if (data[offset + j] != seq[j]) return false;
    }
    return true;
  }

  /// Inspects whether any EXIF, XMP, IPTC, or C2PA metadata chunks exist in [bytes].
  static bool hasMetadata(Uint8List bytes) {
    if (bytes.length < 4) return false;

    // 1. JPEG: SOI is 0xFF, 0xD8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int pos = 2;
      while (pos + 1 < bytes.length) {
        if (bytes[pos] != 0xFF) {
          pos++;
          continue;
        }
        final m = bytes[pos + 1];
        if (m == 0xD9) break; // EOI
        if (m == 0xFF || m == 0x00 || (m >= 0xD0 && m <= 0xD7)) {
          pos += 2;
          continue;
        }
        if (pos + 3 >= bytes.length) break;
        final segLen = (bytes[pos + 2] << 8) | bytes[pos + 3];
        if (pos + 2 + segLen > bytes.length) break;

        // APP1 (EXIF/XMP), APP11 (C2PA/JUMBF), APP13 (IPTC), COM
        if (m == 0xE1 || m == 0xEB || m == 0xED || m == 0xFE) {
          return true;
        }
        if (m >= 0xE0 && m <= 0xEF) {
          final payload = bytes.sublist(pos + 4, pos + 2 + segLen);
          if (_indexOfSequence(payload, [0x45, 0x78, 0x69, 0x66]) != -1 ||
              _indexOfSequence(payload, _c2paMagic) != -1 ||
              _indexOfSequence(payload, _jumbMagic) != -1 ||
              _indexOfSequence(payload, [0x4A, 0x50, 0x55, 0x4D]) != -1) {
            return true;
          }
        }
        if (m == 0xDA) break; // SOS
        pos += 2 + segLen;
      }
      return false;
    }

    // 2. PNG: Signature is 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      int pos = 8;
      while (pos + 12 <= bytes.length) {
        final chunkLen =
            (bytes[pos] << 24) |
            (bytes[pos + 1] << 16) |
            (bytes[pos + 2] << 8) |
            bytes[pos + 3];
        final totalChunk = 12 + chunkLen;
        if (pos + totalChunk > bytes.length) break;

        final chunkTypeStr = String.fromCharCodes(
          bytes.sublist(pos + 4, pos + 8),
        );
        if (chunkTypeStr == 'eXIf' ||
            chunkTypeStr == 'iTXt' ||
            chunkTypeStr == 'tEXt' ||
            chunkTypeStr == 'zTXt' ||
            chunkTypeStr == 'c2pa' ||
            chunkTypeStr == 'caBX' ||
            chunkTypeStr == 'jumb') {
          return true;
        }
        if (chunkLen > 0) {
          final cdata = bytes.sublist(pos + 8, pos + 8 + chunkLen);
          if (_indexOfSequence(cdata, _c2paMagic) != -1 ||
              _indexOfSequence(cdata, _jumbMagic) != -1) {
            return true;
          }
        }
        pos += totalChunk;
        if (chunkTypeStr == 'IEND') break;
      }
      return false;
    }

    // 3. Generic
    return _indexOfSequence(bytes, _c2paMagic) != -1 ||
        _indexOfSequence(bytes, _jumbMagic) != -1 ||
        _indexOfSequence(bytes, _c2xxMagic) != -1;
  }
}
