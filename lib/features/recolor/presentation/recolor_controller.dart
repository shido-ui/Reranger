import 'dart:typed_data';

import '../../../domain/color/color_palette.dart';
import '../../../domain/color/recolor_mask.dart';
import '../../../domain/recipes/recolor_render_node.dart';
import '../../../domain/recipes/render_graph.dart';
import '../../../domain/recipes/render_graph_node.dart';
import '../../../domain/scene_map/color_region_map_data.dart';

/// Immutable snapshot representing the editing state of Recolor Studio.
class RecolorState {
  final ColorPalette? extractedPalette;
  final int selectedColorIndex;
  final ColorRgb? targetColor;
  final List<ColorRgb> harmonicSuggestions;
  final double strength;
  final double tolerance;
  final double feather;
  final bool preserveLuminance;
  final RegionMask? activeMask;
  final bool isMaskPreviewActive;
  final bool isComparing;
  final bool canUndo;
  final bool canRedo;
  final bool semanticSegmentationAvailable;
  final String? statusMessage;

  const RecolorState({
    this.extractedPalette,
    this.selectedColorIndex = 0,
    this.targetColor,
    this.harmonicSuggestions = const [],
    this.strength = 1.0,
    this.tolerance = 0.20,
    this.feather = 0.10,
    this.preserveLuminance = true,
    this.activeMask,
    this.isMaskPreviewActive = false,
    this.isComparing = false,
    this.canUndo = false,
    this.canRedo = false,
    this.semanticSegmentationAvailable = false,
    this.statusMessage,
  });

  ColorRgb? get activeSourceColor {
    if (extractedPalette == null || extractedPalette!.colors.isEmpty) {
      return null;
    }
    final idx = selectedColorIndex.clamp(
      0,
      extractedPalette!.colors.length - 1,
    );
    return extractedPalette!.colors[idx];
  }

  RecolorState copyWith({
    ColorPalette? extractedPalette,
    int? selectedColorIndex,
    ColorRgb? targetColor,
    List<ColorRgb>? harmonicSuggestions,
    double? strength,
    double? tolerance,
    double? feather,
    bool? preserveLuminance,
    RegionMask? activeMask,
    bool? isMaskPreviewActive,
    bool? isComparing,
    bool? canUndo,
    bool? canRedo,
    bool? semanticSegmentationAvailable,
    String? statusMessage,
    bool clearTargetColor = false,
    bool clearActiveMask = false,
  }) {
    return RecolorState(
      extractedPalette: extractedPalette ?? this.extractedPalette,
      selectedColorIndex: selectedColorIndex ?? this.selectedColorIndex,
      targetColor: clearTargetColor ? null : (targetColor ?? this.targetColor),
      harmonicSuggestions: harmonicSuggestions ?? this.harmonicSuggestions,
      strength: strength ?? this.strength,
      tolerance: tolerance ?? this.tolerance,
      feather: feather ?? this.feather,
      preserveLuminance: preserveLuminance ?? this.preserveLuminance,
      activeMask: clearActiveMask ? null : (activeMask ?? this.activeMask),
      isMaskPreviewActive: isMaskPreviewActive ?? this.isMaskPreviewActive,
      isComparing: isComparing ?? this.isComparing,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      semanticSegmentationAvailable:
          semanticSegmentationAvailable ?? this.semanticSegmentationAvailable,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

/// State controller managing interactive, reversible recolor workflows.
/// Enforces:
/// - Reversible operations via Undo / Redo stacks
/// - Invariant 4: Source image immutability
/// - Invariant 7: Truthful semantic capability reporting
/// - Mask inspection and touchscreen brush repairs
class RecolorController {
  final Uint8List sourceRgba;
  final int imageWidth;
  final int imageHeight;
  final String sourceImageHash;

  RecolorState _state;
  final List<RecolorState> _undoStack = [];
  final List<RecolorState> _redoStack = [];

  RecolorController({
    required this.sourceRgba,
    required this.imageWidth,
    required this.imageHeight,
    required this.sourceImageHash,
    ColorPalette? initialPalette,
    ColorRegionMapData? colorRegionMap,
  }) : _state = const RecolorState() {
    _initialize(initialPalette: initialPalette, colorRegionMap: colorRegionMap);
  }

  RecolorState get state => _state;

  void _initialize({
    ColorPalette? initialPalette,
    ColorRegionMapData? colorRegionMap,
  }) {
    // 1. Extract dominant palette if not provided
    final palette =
        initialPalette ??
        ColorPalette.extractDominant(
          id: 'extracted_dominant',
          name: 'Extracted Palette',
          rgbaBytes: sourceRgba,
          width: imageWidth,
          height: imageHeight,
          k: 5,
        );

    final firstColor = palette.colors.isNotEmpty
        ? palette.colors[0]
        : ColorRgb.black;
    final harmonies = ColorHarmonies.complementary(firstColor);

    // Initial mask from first dominant color
    RegionMask? mask;
    if (colorRegionMap != null && colorRegionMap.regionCount > 0) {
      mask = RegionMask.fromColorRegionMap(
        mapData: colorRegionMap,
        targetRegionIndex: 0,
        targetWidth: imageWidth,
        targetHeight: imageHeight,
      );
    } else {
      mask = RegionMask.fromColorTolerance(
        rgbaBytes: sourceRgba,
        width: imageWidth,
        height: imageHeight,
        sourceColor: firstColor,
        tolerance: 0.20,
        feather: 0.10,
      );
    }

    _state = RecolorState(
      extractedPalette: palette,
      selectedColorIndex: 0,
      targetColor: harmonies.length > 1 ? harmonies[1] : null,
      harmonicSuggestions: harmonies,
      strength: 1.0,
      tolerance: 0.20,
      feather: 0.10,
      preserveLuminance: true,
      activeMask: mask,
      isMaskPreviewActive: false,
      isComparing: false,
      canUndo: false,
      canRedo: false,
      semanticSegmentationAvailable:
          false, // Invariant 7: Honest capability flag
    );
  }

  void _recordUndo() {
    _undoStack.add(_state);
    _redoStack.clear();
    if (_undoStack.length > 20) {
      _undoStack.removeAt(0);
    }
  }

  /// Selects a source color chip from the extracted palette and updates harmonies and mask.
  void selectPaletteColor(int index) {
    if (_state.extractedPalette == null ||
        index < 0 ||
        index >= _state.extractedPalette!.colors.length) {
      return;
    }
    _recordUndo();

    final selected = _state.extractedPalette!.colors[index];
    final comp = ColorHarmonies.complementary(selected);
    final tri = ColorHarmonies.triadic(selected);
    final suggestions = <ColorRgb>[...comp, ...tri.skip(1)];

    final newMask = RegionMask.fromColorTolerance(
      rgbaBytes: sourceRgba,
      width: imageWidth,
      height: imageHeight,
      sourceColor: selected,
      tolerance: _state.tolerance,
      feather: _state.feather,
    );

    _state = _state.copyWith(
      selectedColorIndex: index,
      targetColor: suggestions.length > 1 ? suggestions[1] : null,
      harmonicSuggestions: suggestions,
      activeMask: newMask,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Sets the target replacement color.
  void setTargetColor(ColorRgb color) {
    _recordUndo();
    _state = _state.copyWith(
      targetColor: color,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Updates transformation strength in [0.0, 1.0].
  void setStrength(double strength) {
    _recordUndo();
    _state = _state.copyWith(
      strength: strength.clamp(0.0, 1.0),
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Updates color selection tolerance in [0.0, 1.0].
  void setTolerance(double tolerance) {
    _recordUndo();
    final tol = tolerance.clamp(0.0, 1.0);
    final srcColor = _state.activeSourceColor;
    RegionMask? updatedMask;
    if (srcColor != null) {
      updatedMask = RegionMask.fromColorTolerance(
        rgbaBytes: sourceRgba,
        width: imageWidth,
        height: imageHeight,
        sourceColor: srcColor,
        tolerance: tol,
        feather: _state.feather,
      );
    }

    _state = _state.copyWith(
      tolerance: tol,
      activeMask: updatedMask,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Updates mask edge feathering in [0.0, 1.0].
  void setFeather(double feather) {
    _recordUndo();
    final f = feather.clamp(0.0, 1.0);
    final srcColor = _state.activeSourceColor;
    RegionMask? updatedMask;
    if (srcColor != null) {
      updatedMask = RegionMask.fromColorTolerance(
        rgbaBytes: sourceRgba,
        width: imageWidth,
        height: imageHeight,
        sourceColor: srcColor,
        tolerance: _state.tolerance,
        feather: f,
      );
    }

    _state = _state.copyWith(
      feather: f,
      activeMask: updatedMask,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Toggles luminance preservation mode.
  void togglePreserveLuminance() {
    _recordUndo();
    _state = _state.copyWith(
      preserveLuminance: !_state.preserveLuminance,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Toggles ruby-red mask overlay visibility in viewport.
  void toggleMaskPreview() {
    _state = _state.copyWith(isMaskPreviewActive: !_state.isMaskPreviewActive);
  }

  /// Sets before/after comparison state.
  void setComparing(bool isComparing) {
    _state = _state.copyWith(isComparing: isComparing);
  }

  /// Applies mobile brush repair stroke to the active mask.
  void applyBrushRepair({
    required int centerX,
    required int centerY,
    required int radius,
    required bool isEraser,
    double opacity = 1.0,
  }) {
    if (_state.activeMask == null) return;
    _recordUndo();

    final maskCopy = _state.activeMask!.copy();
    maskCopy.applyBrush(
      centerX: centerX,
      centerY: centerY,
      radius: radius,
      opacity: opacity,
      isEraser: isEraser,
    );

    _state = _state.copyWith(
      activeMask: maskCopy,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Inverts the active mask.
  void invertMask() {
    if (_state.activeMask == null) return;
    _recordUndo();

    final inverted = _state.activeMask!.invert();
    _state = _state.copyWith(
      activeMask: inverted,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Smooths active mask boundaries.
  void featherActiveMask(int radius) {
    if (_state.activeMask == null) return;
    _recordUndo();

    final smoothed = _state.activeMask!.featherMask(radius);
    _state = _state.copyWith(
      activeMask: smoothed,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Reverts last action.
  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_state);
    final previous = _undoStack.removeLast();
    _state = previous.copyWith(canUndo: _undoStack.isNotEmpty, canRedo: true);
  }

  /// Re-applies next action.
  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_state);
    final next = _redoStack.removeLast();
    _state = next.copyWith(canUndo: true, canRedo: _redoStack.isNotEmpty);
  }

  /// Resets all edits to original unmodified state.
  void reset() {
    _recordUndo();
    final firstColor =
        (_state.extractedPalette != null &&
            _state.extractedPalette!.colors.isNotEmpty)
        ? _state.extractedPalette!.colors[0]
        : ColorRgb.black;

    final initialMask = RegionMask.fromColorTolerance(
      rgbaBytes: sourceRgba,
      width: imageWidth,
      height: imageHeight,
      sourceColor: firstColor,
      tolerance: 0.20,
      feather: 0.10,
    );

    _state = _state.copyWith(
      selectedColorIndex: 0,
      clearTargetColor: true, // Clears recolor transformation
      strength: 1.0,
      tolerance: 0.20,
      feather: 0.10,
      preserveLuminance: true,
      activeMask: initialMask,
      isMaskPreviewActive: false,
      isComparing: false,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
    );
  }

  /// Constructs a deterministic [RenderGraph] representing the current recolor recipe.
  RenderGraph buildRenderGraph() {
    final root = SourceImageNode(
      id: 'src_root',
      sourceImageHash: sourceImageHash,
      sourceWidth: imageWidth,
      sourceHeight: imageHeight,
    );

    final target = _state.targetColor;
    final source = _state.activeSourceColor;

    if (target == null || source == null || _state.strength <= 1e-4) {
      // Identity graph: returns untouched source buffer
      return RenderGraph(
        id: 'graph_recolor_identity',
        nodes: {root.id: root},
        outputNodeId: root.id,
      );
    }

    final recolor = RecolorNode(
      id: 'node_recolor_1',
      inputNodeId: root.id,
      sourceR: source.r,
      sourceG: source.g,
      sourceB: source.b,
      targetR: target.r,
      targetG: target.g,
      targetB: target.b,
      tolerance: _state.tolerance,
      feather: _state.feather,
      preserveLuminance: _state.preserveLuminance,
      strength: _state.strength,
      maskBase64: _state.activeMask?.toBase64(),
    );

    return RenderGraph(
      id: 'graph_recolor_active',
      nodes: {root.id: root, recolor.id: recolor},
      outputNodeId: recolor.id,
    );
  }
}
