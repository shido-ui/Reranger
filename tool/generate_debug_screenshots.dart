import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

void main() async {
  final inputPath = 'docs/evidence/prompt-07/samples/input_portrait.bmp';
  final inputBytes = await File(inputPath).readAsBytes();
  final decoded = img.decodeImage(inputBytes);
  if (decoded == null) {
    print('Failed to decode $inputPath');
    exit(1);
  }

  print('Decoded input portrait: ${decoded.width}x${decoded.height}');
  final sourceHash = sha256.convert(inputBytes).toString();
  final executor = RenderGraphExecutor();

  final outDir = Directory('docs/evidence/prompt-30');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  // 1. Process Watercolor Preset
  final watercolorPreset = PresetCatalog.getById('watercolor');
  if (watercolorPreset == null) {
    print('Watercolor preset not found');
    exit(1);
  }
  final wcParams = watercolorPreset.resolveParameters(null);
  final wcGraph = watercolorPreset.buildGraph(
    sourceHash,
    decoded.width,
    decoded.height,
    wcParams,
  );
  final wcResult = await executor.execute(
    graph: wcGraph,
    sourceImageBytes: inputBytes,
  );

  final wcImage = img.Image.fromBytes(
    width: wcResult.width,
    height: wcResult.height,
    bytes: wcResult.pixelBytes.buffer,
    numChannels: 4,
  );
  final wcPngBytes = img.encodePng(wcImage);
  final wcOutFile = File('docs/evidence/prompt-30/watercolor_real_photo.png');
  await wcOutFile.writeAsBytes(wcPngBytes);
  print(
    'Saved Watercolor real photo to ${wcOutFile.path} (${wcPngBytes.length} bytes)',
  );

  // 2. Process Graphite Pencil Preset
  final graphitePreset = PresetCatalog.getById('graphite_pencil');
  if (graphitePreset == null) {
    print('Graphite pencil preset not found');
    exit(1);
  }
  final gpParams = graphitePreset.resolveParameters(null);
  final gpGraph = graphitePreset.buildGraph(
    sourceHash,
    decoded.width,
    decoded.height,
    gpParams,
  );
  final gpResult = await executor.execute(
    graph: gpGraph,
    sourceImageBytes: inputBytes,
  );

  final gpImage = img.Image.fromBytes(
    width: gpResult.width,
    height: gpResult.height,
    bytes: gpResult.pixelBytes.buffer,
    numChannels: 4,
  );
  final gpPngBytes = img.encodePng(gpImage);
  final gpOutFile = File(
    'docs/evidence/prompt-30/graphite_pencil_real_photo.png',
  );
  await gpOutFile.writeAsBytes(gpPngBytes);
  print(
    'Saved Graphite Pencil real photo to ${gpOutFile.path} (${gpPngBytes.length} bytes)',
  );

  // 3. Copy to Artifact Directory for Markdown Embedding
  const artifactDir =
      '/root/.gemini/antigravity-cli/brain/131f6c3f-f2c2-4492-b5c5-d64035cddb16';
  final inputPngBytes = img.encodePng(decoded);
  await File('$artifactDir/input_portrait.png').writeAsBytes(inputPngBytes);
  await File('docs/evidence/prompt-30/input_portrait.png')
      .writeAsBytes(inputPngBytes);
  await wcOutFile.copy('$artifactDir/watercolor_real_photo.png');
  await gpOutFile.copy('$artifactDir/graphite_pencil_real_photo.png');
  print('Successfully copied all images to artifact dir: $artifactDir');
}
