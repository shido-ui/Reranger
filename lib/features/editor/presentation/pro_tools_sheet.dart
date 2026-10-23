import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../domain/layers/editor_layer.dart';
import '../../detector_lab/detector_lab_models.dart';
import 'editor_controller.dart';
import 'layer_history_controller.dart';

/// SCR-08: Pro Tools Modal Sheet (Level 3 Progressive Disclosure).
///
/// Dedicated studio for advanced artists and power users:
/// - Non-destructive layers & blend modes.
/// - Full undo/redo history timeline with undo-all and redo-all.
/// - Variant board for aesthetic branching without losing baseline edits.
/// - Split-screen comparison curtain (SCR-06).
/// - Output scale and format configuration.
/// - Obvious and effortless return path back to Simple mode.
class ProToolsSheet extends StatefulWidget {
  final EditorController controller;

  const ProToolsSheet({super.key, required this.controller});

  /// Displays the modal Pro Tools studio sheet.
  static Future<void> show(
    BuildContext context, {
    required EditorController controller,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProToolsSheet(controller: controller),
    );
  }

  @override
  State<ProToolsSheet> createState() => _ProToolsSheetState();
}

class _ProToolsSheetState extends State<ProToolsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _selectedFolder = 'Standard 10-Image Fixture Set (5 Real, 5 AI)';
  String _selectedAdapter = 'Mock Detector v1 (ResNet-50 Classifier)';
  BenchmarkMetrics? _benchmarkMetrics;
  bool _isRunningBenchmark = false;
  double _benchmarkProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        final primaryText = isDark
            ? AppColorTokens.darkTextPrimary
            : AppColorTokens.lightTextPrimary;
        final secondaryText = isDark
            ? AppColorTokens.darkTextSecondary
            : AppColorTokens.lightTextSecondary;
        final accentColor = isDark
            ? AppColorTokens.darkAccentPrimary
            : AppColorTokens.lightAccentPrimary;
        final surfaceElevated = isDark
            ? AppColorTokens.darkSurfaceElevated
            : AppColorTokens.lightSurfaceElevated;
        final surfaceBase = isDark
            ? AppColorTokens.darkSurfaceBase
            : AppColorTokens.lightSurfaceBase;
        final borderSubtle = isDark
            ? AppColorTokens.darkBorderSubtle
            : AppColorTokens.lightBorderSubtle;

        final layerCtrl = widget.controller.layerHistoryController;

        return Material(
          color: surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            side: BorderSide(color: borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: AppSpacingTokens.sm),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: secondaryText.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Top Bar with Done CTA
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacingTokens.md,
                      vertical: AppSpacingTokens.sm,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 20),
                        const SizedBox(width: AppSpacingTokens.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pro Tools Studio',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: primaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Layers, history & advanced controls',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),

                  // Tab Bar
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: accentColor,
                    labelColor: accentColor,
                    unselectedLabelColor: secondaryText,
                    tabs: const [
                      Tab(icon: Icon(Icons.layers_outlined), text: 'Layers'),
                      Tab(icon: Icon(Icons.history), text: 'History'),
                      Tab(
                        icon: Icon(Icons.compare_arrows),
                        text: 'Curtain & Variants',
                      ),
                      Tab(icon: Icon(Icons.tune), text: 'Output'),
                      Tab(
                        icon: Icon(Icons.shield_outlined),
                        text: 'Stealth Studio',
                      ),
                      Tab(
                        icon: Icon(Icons.science_outlined),
                        text: 'Diagnostics Lab',
                      ),
                    ],
                  ),
                  const Divider(height: 1),

                  // Tab Content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLayersTab(
                          theme,
                          primaryText,
                          secondaryText,
                          accentColor,
                          surfaceBase,
                          borderSubtle,
                          layerCtrl,
                        ),
                        _buildHistoryTab(
                          theme,
                          primaryText,
                          secondaryText,
                          accentColor,
                          surfaceBase,
                          borderSubtle,
                          layerCtrl,
                        ),
                        _buildVariantsAndCurtainTab(
                          theme,
                          primaryText,
                          secondaryText,
                          accentColor,
                          surfaceBase,
                          borderSubtle,
                          layerCtrl,
                        ),
                        _buildOutputTab(
                          theme,
                          primaryText,
                          secondaryText,
                          accentColor,
                          surfaceBase,
                          borderSubtle,
                        ),
                        _buildStealthStudioTab(
                          theme,
                          primaryText,
                          secondaryText,
                          accentColor,
                          surfaceBase,
                          borderSubtle,
                        ),
                        _buildDiagnosticsLabTab(
                          theme,
                          primaryText,
                          secondaryText,
                          accentColor,
                          surfaceBase,
                          borderSubtle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: Layers & Masks
  // ---------------------------------------------------------------------------
  Widget _buildLayersTab(
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceBase,
    Color borderSubtle,
    LayerHistoryController? layerCtrl,
  ) {
    if (layerCtrl == null) {
      return Center(
        child: Text(
          'Layer stack unavailable for this canvas.',
          style: theme.textTheme.bodyMedium?.copyWith(color: secondaryText),
        ),
      );
    }

    final layers = layerCtrl.state.layerStack.layers;

    return ListView(
      padding: const EdgeInsets.all(AppSpacingTokens.md),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Layer Stack (${layers.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                color: primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Tint Layer'),
              onPressed: () {
                final newId = 'adj_${DateTime.now().millisecondsSinceEpoch}';
                layerCtrl.addAdjustmentLayer(
                  AdjustmentLayer(
                    id: newId,
                    name: 'Color Tint ${layers.length}',
                    effectType: 'duotone',
                    opacity: 0.65,
                    blendMode: BlendModeType.multiply,
                    parameters: const {
                      'shadowR': 24,
                      'shadowG': 40,
                      'shadowB': 60,
                      'highlightR': 255,
                      'highlightG': 210,
                      'highlightB': 140,
                      'vignetteFalloff': 0.25,
                    },
                  ),
                );
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacingTokens.sm),
        for (int i = layers.length - 1; i >= 0; i--) ...[
          _buildLayerCard(
            layers[i],
            i == 0, // Root source layer
            theme,
            primaryText,
            secondaryText,
            accentColor,
            surfaceBase,
            borderSubtle,
            layerCtrl,
          ),
          const SizedBox(height: AppSpacingTokens.sm),
        ],
      ],
    );
  }

  Widget _buildLayerCard(
    EditorLayer layer,
    bool isRoot,
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceBase,
    Color borderSubtle,
    LayerHistoryController layerCtrl,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacingTokens.sm),
      decoration: BoxDecoration(
        color: surfaceBase,
        borderRadius: AppRadiusTokens.borderMd,
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isRoot ? Icons.photo : Icons.tune,
                size: 20,
                color: isRoot ? Colors.green : accentColor,
              ),
              const SizedBox(width: AppSpacingTokens.xs),
              Expanded(
                child: Text(
                  layer.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isRoot)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacingTokens.xs,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: AppRadiusTokens.borderSm,
                  ),
                  child: Text(
                    'LOCKED BASE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                )
              else ...[
                IconButton(
                  icon: Icon(
                    layer.isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                  ),
                  tooltip: layer.isVisible ? 'Hide Layer' : 'Show Layer',
                  onPressed: () {
                    layerCtrl.toggleLayerVisibility(layer.id);
                    setState(() {});
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete Layer',
                  onPressed: () {
                    layerCtrl.removeLayer(layer.id);
                    setState(() {});
                  },
                ),
              ],
            ],
          ),
          if (!isRoot && layer is AdjustmentLayer) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Opacity: ${(layer.opacity * 100).round()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryText,
                    ),
                  ),
                ),
                DropdownButton<BlendModeType>(
                  value: layer.blendMode,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: BlendModeType.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(mode.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (mode) {
                    if (mode == null) return;
                    layerCtrl.setLayerBlendMode(layer.id, mode);
                    setState(() {});
                  },
                ),
              ],
            ),
            Slider(
              min: 0.0,
              max: 1.0,
              value: layer.opacity,
              onChanged: (val) {
                layerCtrl.setLayerOpacity(layer.id, val);
                setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: History & Timeline
  // ---------------------------------------------------------------------------
  Widget _buildHistoryTab(
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceBase,
    Color borderSubtle,
    LayerHistoryController? layerCtrl,
  ) {
    final state = layerCtrl?.state;
    final canUndo = state?.canUndo ?? false;
    final canRedo = state?.canRedo ?? false;
    final undoCount = state?.undoCount ?? 0;
    final redoCount = state?.redoCount ?? 0;

    return ListView(
      padding: const EdgeInsets.all(AppSpacingTokens.md),
      children: [
        Text(
          'History & Timeline',
          style: theme.textTheme.titleSmall?.copyWith(
            color: primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xs),
        Text(
          'Non-destructive command stack tracks all parameter adjustments and layer mutations.',
          style: theme.textTheme.bodySmall?.copyWith(color: secondaryText),
        ),
        const SizedBox(height: AppSpacingTokens.md),

        // Quick Undo / Redo Row
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.undo),
                label: Text('Undo ($undoCount)'),
                onPressed: canUndo
                    ? () {
                        layerCtrl?.undo();
                        setState(() {});
                      }
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacingTokens.sm),
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.redo),
                label: Text('Redo ($redoCount)'),
                onPressed: canRedo
                    ? () {
                        layerCtrl?.redo();
                        setState(() {});
                      }
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacingTokens.sm),

        // Undo All / Redo All
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: canUndo
                    ? () {
                        layerCtrl?.undoAll();
                        setState(() {});
                      }
                    : null,
                child: const Text('Reset All to Baseline'),
              ),
            ),
            const SizedBox(width: AppSpacingTokens.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: canRedo
                    ? () {
                        layerCtrl?.redoAll();
                        setState(() {});
                      }
                    : null,
                child: const Text('Restore All Latest'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: Variants & Split Curtain (SCR-06 & SCR-14)
  // ---------------------------------------------------------------------------
  Widget _buildVariantsAndCurtainTab(
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceBase,
    Color borderSubtle,
    LayerHistoryController? layerCtrl,
  ) {
    final variants = layerCtrl?.state.variantBoard.variants ?? [];
    final activeId = layerCtrl?.state.variantBoard.activeVariantId;

    return ListView(
      padding: const EdgeInsets.all(AppSpacingTokens.md),
      children: [
        // Split-Screen Comparison (SCR-06)
        Text(
          'Split-Screen Comparison (SCR-06)',
          style: theme.textTheme.titleSmall?.copyWith(
            color: primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xs),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show Split Curtain'),
          subtitle: const Text(
            'Draggable divider comparing original and result.',
          ),
          value: widget.controller.isSplitComparisonActive,
          onChanged: (active) {
            widget.controller.setSplitComparison(active: active);
            setState(() {});
          },
        ),
        if (widget.controller.isSplitComparisonActive) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Curtain Position',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondaryText,
                ),
              ),
              Text(
                '${(widget.controller.splitPosition * 100).round()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: primaryText,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            min: 0.0,
            max: 1.0,
            value: widget.controller.splitPosition,
            onChanged: (pos) {
              widget.controller.setSplitComparison(position: pos);
              setState(() {});
            },
          ),
        ],
        const Divider(height: AppSpacingTokens.lg),

        // Variant Board (SCR-14)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Variant Board (${variants.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                color: primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Branch Variant'),
              onPressed: () {
                final count = variants.length + 1;
                layerCtrl?.createVariant('Variant $count');
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacingTokens.sm),
        for (final v in variants) ...[
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: AppRadiusTokens.borderMd,
              side: BorderSide(
                color: v.id == activeId ? accentColor : borderSubtle,
                width: v.id == activeId ? 2.0 : 1.0,
              ),
            ),
            tileColor: surfaceBase,
            leading: Icon(
              v.id == activeId ? Icons.check_circle : Icons.circle_outlined,
              color: v.id == activeId ? accentColor : secondaryText,
            ),
            title: Text(
              v.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: primaryText,
                fontWeight: v.id == activeId
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              'Created ${v.createdAt.toLocal().toString().split('.')[0]}',
              style: theme.textTheme.labelSmall?.copyWith(color: secondaryText),
            ),
            onTap: () {
              layerCtrl?.switchVariant(v.id);
              setState(() {});
            },
          ),
          const SizedBox(height: AppSpacingTokens.xs),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: Output & Canvas Settings
  // ---------------------------------------------------------------------------
  Widget _buildOutputTab(
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceBase,
    Color borderSubtle,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacingTokens.md),
      children: [
        Text(
          'Output & Render Settings',
          style: theme.textTheme.titleSmall?.copyWith(
            color: primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xs),
        Text(
          'Configure render resolution and export compression format.',
          style: theme.textTheme.bodySmall?.copyWith(color: secondaryText),
        ),
        const SizedBox(height: AppSpacingTokens.md),

        Text(
          'Render Resolution',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xs),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(
              value: 0.5,
              label: Text('50% (Fast Preview)'),
              icon: Icon(Icons.speed),
            ),
            ButtonSegment(
              value: 1.0,
              label: Text('100% (Full Master)'),
              icon: Icon(Icons.high_quality),
            ),
          ],
          selected: {widget.controller.renderScale},
          onSelectionChanged: (val) {
            widget.controller.setRenderScale(val.first);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacingTokens.lg),

        Text(
          'Export Compression Format',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xs),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'PNG',
              label: Text('PNG (Lossless)'),
              icon: Icon(Icons.image),
            ),
            ButtonSegment(
              value: 'JPEG',
              label: Text('JPEG (95% Quality)'),
              icon: Icon(Icons.compress),
            ),
          ],
          selected: {widget.controller.exportFormat},
          onSelectionChanged: (val) {
            widget.controller.setExportFormat(val.first);
            setState(() {});
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 5: Stealth Studio (PO Addendum)
  // ---------------------------------------------------------------------------
  Widget _buildStealthStudioTab(
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceBase,
    Color borderSubtle,
  ) {
    final controller = widget.controller;
    return ListView(
      padding: const EdgeInsets.all(AppSpacingTokens.md),
      children: [
        Text(
          'Stealth Studio',
          style: theme.textTheme.titleMedium?.copyWith(
            color: primaryText,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xs),
        Text(
          'Targeted FGSM mathematical perturbations to disrupt CNN-based AI detector confidence scores.',
          style: theme.textTheme.bodySmall?.copyWith(color: secondaryText),
        ),
        const SizedBox(height: AppSpacingTokens.md),

        // Warning Label (Mandatory as per PO Directive)
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
                Icons.warning_amber_rounded,
                color: Colors.amber.shade300,
                size: 20,
              ),
              const SizedBox(width: AppSpacingTokens.xs),
              Expanded(
                child: Text(
                  'This applies adversarial noise optimized to disrupt AI detection algorithms. It does not guarantee human authorship.',
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

        // Enable Toggle
        Material(
          color: surfaceBase,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadiusTokens.borderMd,
            side: BorderSide(color: borderSubtle),
          ),
          child: SwitchListTile(
            title: const Text('Enable Adversarial Stealth'),
            subtitle: const Text(
              'Injects targeted perturbation node before export',
            ),
            value: controller.isStealthEnabled,
            onChanged: (val) {
              controller.setStealthEnabled(val);
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: AppSpacingTokens.md),

        // Adversarial Strength Slider (0.0 to 1.0)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Adversarial Strength',
              style: theme.textTheme.titleSmall?.copyWith(
                color: primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              controller.stealthStrength.toStringAsFixed(2),
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryText,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        Slider(
          min: 0.0,
          max: 1.0,
          value: controller.stealthStrength,
          onChanged: (val) {
            controller.setStealthStrength(val);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacingTokens.xs),

        // Apply Frequency Perturbation Toggle
        Material(
          color: surfaceBase,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadiusTokens.borderMd,
            side: BorderSide(color: borderSubtle),
          ),
          child: SwitchListTile(
            title: const Text('Apply Frequency Perturbation'),
            subtitle: const Text(
              'Phase-modulated high-pass harmonic disruption',
            ),
            value: controller.stealthApplyFrequency,
            onChanged: (val) {
              controller.setStealthApplyFrequency(val);
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: AppSpacingTokens.md),

        // Preview Button
        OutlinedButton.icon(
          icon: Icon(
            controller.isPreviewingStealth
                ? Icons.visibility_off
                : Icons.visibility,
          ),
          label: Text(
            controller.isPreviewingStealth
                ? 'Stop Preview'
                : 'Preview Noise Impact',
          ),
          onPressed: () {
            controller.toggleStealthPreview();
            setState(() {});
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 6: Diagnostics Lab (PO Addendum)
  // ---------------------------------------------------------------------------
  Widget _buildDiagnosticsLabTab(
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceBase,
    Color borderSubtle,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacingTokens.md),
      children: [
        Text(
          'Diagnostics Lab',
          style: theme.textTheme.titleMedium?.copyWith(
            color: primaryText,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xs),
        Text(
          'Evaluate local image corpora against mock detector adapters and inspect C2PA provenance.',
          style: theme.textTheme.bodySmall?.copyWith(color: secondaryText),
        ),
        const SizedBox(height: AppSpacingTokens.md),

        // Folder Selector
        Text(
          'Test Image Folder',
          style: theme.textTheme.titleSmall?.copyWith(
            color: primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xxs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacingTokens.sm),
          decoration: BoxDecoration(
            color: surfaceBase,
            borderRadius: AppRadiusTokens.borderMd,
            border: Border.all(color: borderSubtle),
          ),
          child: DropdownButton<String>(
            isExpanded: true,
            value: _selectedFolder,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(
                value: 'Standard 10-Image Fixture Set (5 Real, 5 AI)',
                child: Text('Standard 10-Image Fixture Set (5 Real, 5 AI)'),
              ),
              DropdownMenuItem(
                value: 'Creations Gallery Local Folder',
                child: Text('Creations Gallery Local Folder'),
              ),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedFolder = val);
            },
          ),
        ),
        const SizedBox(height: AppSpacingTokens.md),

        // Detector Adapter Selector
        Text(
          'Detector Adapter',
          style: theme.textTheme.titleSmall?.copyWith(
            color: primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xxs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacingTokens.sm),
          decoration: BoxDecoration(
            color: surfaceBase,
            borderRadius: AppRadiusTokens.borderMd,
            border: Border.all(color: borderSubtle),
          ),
          child: DropdownButton<String>(
            isExpanded: true,
            value: _selectedAdapter,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(
                value: 'Mock Detector v1 (ResNet-50 Classifier)',
                child: Text('Mock Detector v1 (ResNet-50 Classifier)'),
              ),
              DropdownMenuItem(
                value: 'Mock Detector v2 (ViT-Patch Detector)',
                child: Text('Mock Detector v2 (ViT-Patch Detector)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedAdapter = val);
            },
          ),
        ),
        const SizedBox(height: AppSpacingTokens.md),

        // Run Benchmark Button
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Run Benchmark'),
          onPressed: _isRunningBenchmark ? null : _runBenchmark,
        ),
        if (_isRunningBenchmark) ...[
          const SizedBox(height: AppSpacingTokens.sm),
          LinearProgressIndicator(value: _benchmarkProgress),
          const SizedBox(height: AppSpacingTokens.xxs),
          Text(
            'Evaluating corpus: ${(_benchmarkProgress * 100).toInt()}%',
            style: theme.textTheme.labelSmall?.copyWith(color: secondaryText),
            textAlign: TextAlign.center,
          ),
        ],

        // Results Dashboard
        if (_benchmarkMetrics != null) ...[
          const SizedBox(height: AppSpacingTokens.lg),
          Text(
            'Evaluation Results Dashboard',
            style: theme.textTheme.titleSmall?.copyWith(
              color: primaryText,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacingTokens.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacingTokens.sm),
            decoration: BoxDecoration(
              color: surfaceBase,
              borderRadius: AppRadiusTokens.borderMd,
              border: Border.all(color: borderSubtle),
            ),
            child: Column(
              children: [
                _buildMetricRow(
                  'Total Images',
                  '${_benchmarkMetrics!.totalImages}',
                  primaryText,
                ),
                _buildMetricRow(
                  'Flagged as AI',
                  '${_benchmarkMetrics!.flaggedAsAi}',
                  primaryText,
                ),
                _buildMetricRow(
                  'Flagged as Real',
                  '${_benchmarkMetrics!.flaggedAsReal}',
                  primaryText,
                ),
                _buildMetricRow(
                  'False Positive Rate (FPR)',
                  '${(_benchmarkMetrics!.falsePositiveRate * 100).toStringAsFixed(1)}%',
                  primaryText,
                ),
                _buildMetricRow(
                  'False Negative Rate (FNR)',
                  '${(_benchmarkMetrics!.falseNegativeRate * 100).toStringAsFixed(1)}%',
                  primaryText,
                ),
                _buildMetricRow(
                  'AUROC Score',
                  _benchmarkMetrics!.auroc.toStringAsFixed(3),
                  primaryText,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacingTokens.md),

          // Provenance Section
          Text(
            'C2PA Provenance Signals',
            style: theme.textTheme.titleSmall?.copyWith(
              color: primaryText,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacingTokens.xs),
          Container(
            padding: const EdgeInsets.all(AppSpacingTokens.sm),
            decoration: BoxDecoration(
              color: surfaceBase,
              borderRadius: AppRadiusTokens.borderMd,
              border: Border.all(color: borderSubtle),
            ),
            child: Column(
              children: [
                _buildMetricRow(
                  'Valid C2PA Signatures',
                  '${_benchmarkMetrics!.c2paValidCount}',
                  Colors.green,
                ),
                _buildMetricRow(
                  'Corrupt / Invalid Boxes',
                  '${_benchmarkMetrics!.c2paInvalidCount}',
                  Colors.red,
                ),
                _buildMetricRow(
                  'Missing Provenance',
                  '${_benchmarkMetrics!.c2paMissingCount}',
                  Colors.amber,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runBenchmark() async {
    setState(() {
      _isRunningBenchmark = true;
      _benchmarkProgress = 0.0;
    });

    final testImages = <TestImageItem>[
      for (int i = 1; i <= 5; i++)
        TestImageItem(
          id: 'fixture_real_$i',
          path: '/mock/real_$i.png',
          bytes: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
          isGroundTruthAi: false,
        ),
      for (int i = 1; i <= 5; i++)
        TestImageItem(
          id: 'fixture_ai_$i',
          path: '/mock/ai_$i.png',
          bytes: i <= 2
              ? Uint8List.fromList([
                  ...C2paParser.c2paMagic,
                  1,
                  2,
                  3,
                  4,
                  5,
                  6,
                  7,
                  8,
                ])
              : Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]),
          isGroundTruthAi: true,
        ),
    ];

    final adapter = MockDetectorAdapter(
      name: _selectedAdapter,
      fixedConfidenceScores: {
        'fixture_real_1': 0.10,
        'fixture_real_2': 0.20,
        'fixture_real_3': 0.30,
        'fixture_real_4': 0.40,
        'fixture_real_5': 0.70,
        'fixture_ai_1': 0.40,
        'fixture_ai_2': 0.80,
        'fixture_ai_3': 0.85,
        'fixture_ai_4': 0.90,
        'fixture_ai_5': 0.95,
      },
    );

    final runner = EvaluationRunner();
    final metrics = await runner.runEvaluation(
      images: testImages,
      adapter: adapter,
      onProgress: (p, _) {
        if (mounted) setState(() => _benchmarkProgress = p);
      },
    );

    if (mounted) {
      setState(() {
        _benchmarkMetrics = metrics;
        _isRunningBenchmark = false;
        _benchmarkProgress = 1.0;
      });
    }
  }
}
