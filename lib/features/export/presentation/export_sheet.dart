import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../data/platform/platform_media_service.dart';
import '../../../data/project_package/project_package_exporter.dart';
import '../../editor/presentation/editor_controller.dart';
import '../data/image_exporter.dart';
import '../domain/export_format.dart';

/// SCR-09: Modal sheet for configuring and finalizing verified local exports.
class ExportSheet extends StatefulWidget {
  final EditorController controller;
  final PlatformMediaService mediaService;

  const ExportSheet({
    super.key,
    required this.controller,
    this.mediaService = const MethodChannelPlatformMediaService(),
  });

  static Future<void> show(
    BuildContext context, {
    required EditorController controller,
    PlatformMediaService mediaService =
        const MethodChannelPlatformMediaService(),
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          ExportSheet(controller: controller, mediaService: mediaService),
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
  double _realism = 0.0;
  bool _isExporting = false;
  String? _exportSuccessMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _realism = widget.controller.realism;
    _scale = widget.controller.renderScale;
    final fmt = widget.controller.exportFormat.toUpperCase();
    if (fmt == 'JPEG' || fmt == 'JPG') {
      _selectedFormat = ExportImageFormat.jpeg;
    } else if (fmt == 'WEBP') {
      _selectedFormat = ExportImageFormat.webp;
    } else {
      _selectedFormat = ExportImageFormat.png;
    }
  }

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
      realism: _realism,
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
                    setState(() {
                      _selectedFormat = set.first;
                      widget.controller.setExportFormat(
                        _selectedFormat.name.toUpperCase(),
                      );
                    });
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
                        if (val) {
                          setState(() {
                            _scale = 0.5;
                            widget.controller.setRenderScale(0.5);
                          });
                        }
                      },
                    ),
                    const SizedBox(width: AppSpacingTokens.xs),
                    ChoiceChip(
                      label: const Text('100% (Full Master)'),
                      selected: _scale == 1.0,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _scale = 1.0;
                            widget.controller.setRenderScale(1.0);
                          });
                        }
                      },
                    ),
                    const SizedBox(width: AppSpacingTokens.xs),
                    ChoiceChip(
                      label: const Text('200%'),
                      selected: _scale == 2.0,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _scale = 2.0;
                            widget.controller.setRenderScale(2.0);
                          });
                        }
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

                // Realism & Hardware Defense (Stealth Engine V2)
                Material(
                  color: surfaceBase,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadiusTokens.borderMd,
                    side: BorderSide(color: borderSubtle),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacingTokens.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Realism Defense',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: primaryText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${(_realism * 100).round()}%',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ARMOR UAP DCT perturbation, Bayer noise & 100% EXIF/C2PA metadata stripping.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondaryText,
                          ),
                        ),
                        Slider(
                          key: const Key('export_realism_slider'),
                          value: _realism,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          onChanged: (val) {
                            setState(() {
                              _realism = val;
                              widget.controller.setRealism(val);
                            });
                          },
                        ),
                      ],
                    ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Estimated File Size',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: secondaryText,
                            ),
                          ),
                          Text(
                            '~$estimatedSizeStr (Estimated)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: primaryText,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Estimated from typical entropy; exact output size varies with image complexity.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondaryText,
                          fontSize: 11,
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
    final project = widget.controller.project;
    if (project == null) {
      setState(() => _errorMessage = 'No active project available to export.');
      return;
    }

    setState(() {
      _isExporting = true;
      _errorMessage = null;
      _exportSuccessMessage = null;
    });

    try {
      // 1. Render at full source resolution without preview downscaling (DEF-025)
      final fullResImage = await widget.controller.renderFullResolutionOutput(
        scale: _scale,
      );

      final config = ExportConfiguration(
        format: _selectedFormat,
        quality: _quality,
        scale: 1.0, // Scale already applied by renderFullResolutionOutput
        stripGpsMetadata: _stripGps,
        realism: _realism,
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
        sourceImage: fullResImage,
        destinationPath: resolvedPath,
        config: config,
        sourceImagePath: project.sourceImagePath,
      );

      // Update project record with output reference and current active recipe (Prompt 1.B.2)
      final currentRecipe = widget.controller.buildCurrentRecipe();
      final updatedProject = project.copyWith(
        outputReferencePath: result.filePath,
        outputChecksum: result.sha256Checksum,
        recipe: currentRecipe,
        isDirty: false,
        updatedAt: DateTime.now().toUtc(),
      );

      // Attempt metadata persistence with partial failure safety (Prompt 1.B.3)
      try {
        await widget.controller.projectRepository.saveProject(updatedProject);
        widget.controller.project = updatedProject;
        widget.controller.isSaved = true;
      } catch (saveError) {
        // Partial outcome: Image export succeeded on disk, but project metadata failed to update.
        // Retain recoverable state; do NOT clear dirty journal or claim complete success (Prompt 1.B.3).
        if (mounted) {
          setState(() {
            _isExporting = false;
            _errorMessage =
                'Image saved to ${result.filePath}, but project metadata persistence failed: $saveError. Your edits remain preserved in the recovery journal.';
          });
        }
        return;
      }

      final sizeStr = RealSizeEstimator.formatBytes(result.byteLength);
      final alphaNote = result.alphaStripped ? ' (alpha composited)' : '';

      String msg;
      if (share) {
        await widget.mediaService.shareImage(
          filePath: result.filePath,
          mimeType: _selectedFormat.mimeType,
          subject: project.name,
        );
        msg =
            'Share sheet opened ($sizeStr, ${_selectedFormat.name.toUpperCase()}$alphaNote)';
      } else {
        final savedLocation = await widget.mediaService.saveImageToGallery(
          filePath: result.filePath,
          title:
              '${project.name}_export_${DateTime.now().millisecondsSinceEpoch}',
          mimeType: _selectedFormat.mimeType,
        );
        final inGallery = savedLocation != result.filePath;
        msg = inGallery
            ? 'Saved successfully to outputs! Saved to device gallery ($sizeStr, ${_selectedFormat.name.toUpperCase()}$alphaNote)'
            : 'Saved successfully to outputs! ($sizeStr, ${_selectedFormat.name.toUpperCase()}$alphaNote)';
      }

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

      final currentRecipe = widget.controller.buildCurrentRecipe();
      final projectToExport = project.copyWith(
        recipe: currentRecipe,
        updatedAt: DateTime.now().toUtc(),
      );

      final result = await exporter.exportPackage(
        project: projectToExport,
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
