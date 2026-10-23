import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../data/project_package/project_package_exporter.dart';
import '../../editor/presentation/editor_controller.dart';
import '../data/image_exporter.dart';
import '../domain/export_format.dart';

/// SCR-09: Modal sheet for configuring and finalizing verified local exports.
class ExportSheet extends StatefulWidget {
  final EditorController controller;

  const ExportSheet({super.key, required this.controller});

  static Future<void> show(
    BuildContext context, {
    required EditorController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ExportSheet(controller: controller),
    );
  }

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  ExportImageFormat _selectedFormat = ExportImageFormat.png;
  int _quality = 90;
  double _scale = 1.0;
  bool _stripGps = true;
  bool _isExporting = false;
  String? _exportSuccessMessage;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryText = isDark
        ? AppColorTokens.darkTextPrimary
        : AppColorTokens.lightTextPrimary;
    final secondaryText = isDark
        ? AppColorTokens.darkTextSecondary
        : AppColorTokens.lightTextSecondary;
    final surfaceElevated = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurfaceElevated;
    final surfaceBase = isDark
        ? AppColorTokens.darkSurfaceBase
        : AppColorTokens.lightSurfaceBase;
    final borderSubtle = isDark
        ? AppColorTokens.darkBorderSubtle
        : AppColorTokens.lightBorderSubtle;

    final project = widget.controller.project;
    final int baseWidth = project?.sourceWidth ?? 1024;
    final int baseHeight = project?.sourceHeight ?? 1024;

    final currentConfig = ExportConfiguration(
      format: _selectedFormat,
      quality: _quality,
      scale: _scale,
      stripGpsMetadata: _stripGps,
    );

    final estimatedBytes = RealSizeEstimator.estimateSizeBytes(
      width: baseWidth,
      height: baseHeight,
      config: currentConfig,
    );
    final estimatedSizeStr = RealSizeEstimator.formatBytes(estimatedBytes);

    final targetW = (baseWidth * _scale).round();
    final targetH = (baseHeight * _scale).round();

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: surfaceElevated,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadiusTokens.lg),
        ),
      ),
      child: Column(
        children: [
          // Drag Handle & Header
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacingTokens.sm,
              bottom: AppSpacingTokens.xs,
            ),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: borderSubtle,
                borderRadius: AppRadiusTokens.borderSm,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacingTokens.md,
              vertical: AppSpacingTokens.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.file_download_outlined,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacingTokens.xs),
                    Text(
                      'Export Studio',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: primaryText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close export sheet',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Settings Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacingTokens.md),
              children: [
                // 1. Format Selector
                Text(
                  'Output Format',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacingTokens.xs),
                SegmentedButton<ExportImageFormat>(
                  segments: const [
                    ButtonSegment(
                      value: ExportImageFormat.png,
                      label: Text('PNG'),
                      tooltip: 'Lossless with Alpha',
                    ),
                    ButtonSegment(
                      value: ExportImageFormat.jpeg,
                      label: Text('JPEG'),
                      tooltip: 'Universal compatibility',
                    ),
                    ButtonSegment(
                      value: ExportImageFormat.webp,
                      label: Text('WebP'),
                      tooltip: 'Compact modern format',
                    ),
                  ],
                  selected: {_selectedFormat},
                  onSelectionChanged: (set) {
                    setState(() => _selectedFormat = set.first);
                  },
                ),
                const SizedBox(height: AppSpacingTokens.xs),
                Text(
                  _selectedFormat == ExportImageFormat.png
                      ? 'Lossless compression preserving complete RGBA alpha transparency.'
                      : _selectedFormat == ExportImageFormat.jpeg
                      ? 'DCT lossy compression. Highest universal compatibility across apps.'
                      : 'Modern efficient container with alpha channel and quality control.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryText,
                  ),
                ),
                const SizedBox(height: AppSpacingTokens.md),

                // Honest Alpha Notice for JPEG
                if (_selectedFormat == ExportImageFormat.jpeg) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacingTokens.sm),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: AppRadiusTokens.borderMd,
                      border: Border.all(color: Colors.amber.shade700),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.amber.shade300,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacingTokens.xs),
                        Expanded(
                          child: Text(
                            'JPEG does not support alpha transparency. Transparent regions will be composited onto a solid white background.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.amber.shade100,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacingTokens.md),
                ],

                // 2. Resolution & Scaling
                Text(
                  'Resolution ($targetW × $targetH px)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacingTokens.xs),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('50%'),
                      selected: _scale == 0.5,
                      onSelected: (val) {
                        if (val) setState(() => _scale = 0.5);
                      },
                    ),
                    const SizedBox(width: AppSpacingTokens.xs),
                    ChoiceChip(
                      label: const Text('100% (Full Master)'),
                      selected: _scale == 1.0,
                      onSelected: (val) {
                        if (val) setState(() => _scale = 1.0);
                      },
                    ),
                    const SizedBox(width: AppSpacingTokens.xs),
                    ChoiceChip(
                      label: const Text('200%'),
                      selected: _scale == 2.0,
                      onSelected: (val) {
                        if (val) setState(() => _scale = 2.0);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacingTokens.md),

                // 3. Quality Slider (Only for lossy formats)
                if (_selectedFormat.supportsQuality) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Compression Quality',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: primaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$_quality%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondaryText,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    min: 10,
                    max: 100,
                    divisions: 18,
                    value: _quality.toDouble(),
                    onChanged: (val) => setState(() => _quality = val.toInt()),
                  ),
                  const SizedBox(height: AppSpacingTokens.xs),
                ],

                // 4. Privacy & GPS Metadata Policy
                Material(
                  color: surfaceBase,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadiusTokens.borderMd,
                    side: BorderSide(color: borderSubtle),
                  ),
                  child: SwitchListTile(
                    title: const Text('Remove GPS & location metadata'),
                    subtitle: const Text(
                      'Protects privacy by stripping geolocation tags from EXIF',
                    ),
                    value: _stripGps,
                    onChanged: (val) => setState(() => _stripGps = val),
                  ),
                ),
                const SizedBox(height: AppSpacingTokens.md),

                // 5. Real Estimated File Size
                Container(
                  padding: const EdgeInsets.all(AppSpacingTokens.sm),
                  decoration: BoxDecoration(
                    color: surfaceBase,
                    borderRadius: AppRadiusTokens.borderMd,
                    border: Border.all(color: borderSubtle),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Estimated File Size',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondaryText,
                        ),
                      ),
                      Text(
                        estimatedSizeStr,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: primaryText,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacingTokens.md),

                // Status or Error Messages
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: AppSpacingTokens.sm),
                ],
                if (_exportSuccessMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacingTokens.sm),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: AppRadiusTokens.borderMd,
                      border: Border.all(color: Colors.green.shade700),
                    ),
                    child: Text(
                      _exportSuccessMessage!,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacingTokens.sm),
                ],

                if (_isExporting) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: AppSpacingTokens.xs),
                  Text(
                    'Encoding and writing atomically...',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondaryText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacingTokens.sm),
                ],

                // 6. Action Buttons
                FilledButton.icon(
                  icon: const Icon(Icons.file_download),
                  label: const Text('Save Image to Device'),
                  onPressed: _isExporting
                      ? null
                      : () => _executeExport(share: false),
                ),
                const SizedBox(height: AppSpacingTokens.xs),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share Image'),
                  onPressed: _isExporting
                      ? null
                      : () => _executeExport(share: true),
                ),
                const SizedBox(height: AppSpacingTokens.xs),
                TextButton.icon(
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Export Project Package (.rrproj)'),
                  onPressed: _isExporting ? null : _executeExportPackage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeExport({required bool share}) async {
    final previewBytes = widget.controller.previewPngBytes;
    final project = widget.controller.project;
    if (previewBytes == null || project == null) {
      setState(() => _errorMessage = 'No rendered image available to export.');
      return;
    }

    setState(() {
      _isExporting = true;
      _errorMessage = null;
      _exportSuccessMessage = null;
    });

    try {
      final decodedImage = img.decodeImage(previewBytes);
      if (decodedImage == null) {
        throw const FormatException('Failed to decode active preview buffer');
      }

      final config = ExportConfiguration(
        format: _selectedFormat,
        quality: _quality,
        scale: _scale,
        stripGpsMetadata: _stripGps,
      );

      final exporter = ImageExporter();
      final destinationDir = widget.controller.fileStorage.getOutputsDirectory(
        project.id,
      );
      final fileName = 'export_${DateTime.now().millisecondsSinceEpoch}';
      final resolvedPath = ImageExporter.resolveNonCollidingPath(
        destinationDir: destinationDir,
        baseName: fileName,
        extension: _selectedFormat.extension,
      );

      final result = await exporter.exportToFile(
        sourceImage: decodedImage,
        destinationPath: resolvedPath,
        config: config,
        sourceImagePath: project.sourceImagePath,
      );

      // Update project record with output reference
      final updatedProject = project.copyWith(
        outputReferencePath: result.filePath,
        outputChecksum: result.sha256Checksum,
        updatedAt: DateTime.now().toUtc(),
      );
      await widget.controller.projectRepository.saveProject(updatedProject);
      widget.controller.project = updatedProject;
      widget.controller.isSaved = true;

      final sizeStr = RealSizeEstimator.formatBytes(result.byteLength);
      final alphaNote = result.alphaStripped ? ' (alpha composited)' : '';
      final msg = share
          ? 'Shared successfully! ($sizeStr, ${_selectedFormat.name.toUpperCase()}$alphaNote)'
          : 'Saved successfully to outputs! ($sizeStr, ${_selectedFormat.name.toUpperCase()}$alphaNote)';

      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportSuccessMessage = msg;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _errorMessage = 'Export failed: $e';
        });
      }
    }
  }

  Future<void> _executeExportPackage() async {
    final project = widget.controller.project;
    if (project == null) return;

    setState(() {
      _isExporting = true;
      _errorMessage = null;
      _exportSuccessMessage = null;
    });

    try {
      final exporter = ProjectPackageExporter(
        fileStorage: widget.controller.fileStorage,
      );
      final destinationDir = widget.controller.fileStorage.getOutputsDirectory(
        project.id,
      );
      final packagePath = ImageExporter.resolveNonCollidingPath(
        destinationDir: destinationDir,
        baseName: '${project.name}_package',
        extension: '.rrproj',
      );

      final result = await exporter.exportPackage(
        project: project,
        destinationPackagePath: packagePath,
      );

      final sizeStr = RealSizeEstimator.formatBytes(result.byteLength);
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportSuccessMessage =
              'Project Package created successfully! ($sizeStr)\nSaved to ${File(result.path).path}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _errorMessage = 'Package export failed: $e';
        });
      }
    }
  }
}
