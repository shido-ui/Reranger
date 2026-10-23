import '../../../domain/layers/editor_layer.dart';
import '../../../domain/layers/history_command.dart';
import '../../../domain/layers/variant_board.dart';
import '../../../domain/recipes/render_graph.dart';

/// Immutable presentation state combining layers, history, variants, and viewport comparison.
class LayerHistoryState {
  final LayerStack layerStack;
  final VariantBoard variantBoard;
  final bool canUndo;
  final bool canRedo;
  final int undoCount;
  final int redoCount;
  final bool isSplitComparisonActive;
  final double splitPosition; // Curtain divider position in [0.0, 1.0]
  final bool isRendering;
  final String? activeWarning;

  const LayerHistoryState({
    required this.layerStack,
    required this.variantBoard,
    this.canUndo = false,
    this.canRedo = false,
    this.undoCount = 0,
    this.redoCount = 0,
    this.isSplitComparisonActive = false,
    this.splitPosition = 0.5,
    this.isRendering = false,
    this.activeWarning,
  });

  LayerHistoryState copyWith({
    LayerStack? layerStack,
    VariantBoard? variantBoard,
    bool? canUndo,
    bool? canRedo,
    int? undoCount,
    int? redoCount,
    bool? isSplitComparisonActive,
    double? splitPosition,
    bool? isRendering,
    String? activeWarning,
    bool clearWarning = false,
  }) {
    return LayerHistoryState(
      layerStack: layerStack ?? this.layerStack,
      variantBoard: variantBoard ?? this.variantBoard,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      undoCount: undoCount ?? this.undoCount,
      redoCount: redoCount ?? this.redoCount,
      isSplitComparisonActive:
          isSplitComparisonActive ?? this.isSplitComparisonActive,
      splitPosition: splitPosition ?? this.splitPosition,
      isRendering: isRendering ?? this.isRendering,
      activeWarning: clearWarning
          ? null
          : (activeWarning ?? this.activeWarning),
    );
  }
}

/// Unified presentation controller governing non-destructive layers, history deltas, and variants.
class LayerHistoryController {
  final HistoryManager _history;
  LayerHistoryState _state;
  bool _renderCancelled = false;

  LayerHistoryController({
    required SourceLayer sourceLayer,
    int maxHistoryCapacity = 100,
    List<EditorLayer>? initialLayers,
    VariantBoard? initialVariantBoard,
  }) : _history = HistoryManager(maxCapacity: maxHistoryCapacity),
       _state = _initializeState(
         sourceLayer: sourceLayer,
         initialLayers: initialLayers,
         initialVariantBoard: initialVariantBoard,
       );

  static LayerHistoryState _initializeState({
    required SourceLayer sourceLayer,
    List<EditorLayer>? initialLayers,
    VariantBoard? initialVariantBoard,
  }) {
    final stack = LayerStack([sourceLayer, ...?initialLayers]);
    final board =
        initialVariantBoard ??
        VariantBoard(
          variants: [
            ProjectVariant(
              id: 'var_default',
              name: 'Original Variant',
              layerStack: stack,
              createdAt: DateTime.now().toUtc(),
            ),
          ],
          activeVariantId: 'var_default',
        );

    return LayerHistoryState(
      layerStack: stack,
      variantBoard: board,
      canUndo: false,
      canRedo: false,
      undoCount: 0,
      redoCount: 0,
      isSplitComparisonActive: false,
      splitPosition: 0.5,
      isRendering: false,
    );
  }

  LayerHistoryState get state => _state;
  bool get isRenderCancelled => _renderCancelled;

  /// Executes an edit command, updating layer stack and pushing delta to history.
  void executeCommand(EditCommand command) {
    final updatedStack = _history.executeCommand(_state.layerStack, command);
    final updatedBoard = _state.variantBoard.updateActiveStack(updatedStack);

    _state = _state.copyWith(
      layerStack: updatedStack,
      variantBoard: updatedBoard,
      canUndo: _history.canUndo,
      canRedo: _history.canRedo,
      undoCount: _history.undoCount,
      redoCount: _history.redoCount,
    );
  }

  /// Sets opacity on a layer via an undoable command.
  void setLayerOpacity(String layerId, double newOpacity) {
    final layer = _state.layerStack.layers.firstWhere((l) => l.id == layerId);
    if ((layer.opacity - newOpacity).abs() < 1e-4) return;

    executeCommand(
      SetLayerOpacityCommand(
        layerId: layerId,
        oldOpacity: layer.opacity,
        newOpacity: newOpacity.clamp(0.0, 1.0),
      ),
    );
  }

  /// Sets blend mode on an adjustment layer via an undoable command.
  void setLayerBlendMode(String layerId, BlendModeType newMode) {
    final layer = _state.layerStack.layers.firstWhere((l) => l.id == layerId);
    if (layer is AdjustmentLayer && layer.blendMode != newMode) {
      executeCommand(
        SetLayerBlendModeCommand(
          layerId: layerId,
          oldMode: layer.blendMode,
          newMode: newMode,
        ),
      );
    }
  }

  /// Toggles visibility on a layer via an undoable command.
  void toggleLayerVisibility(String layerId) {
    final layer = _state.layerStack.layers.firstWhere((l) => l.id == layerId);
    executeCommand(
      ToggleLayerVisibilityCommand(
        layerId: layerId,
        oldVisibility: layer.isVisible,
        newVisibility: !layer.isVisible,
      ),
    );
  }

  /// Reorders layer from [oldIndex] to [newIndex] via an undoable command.
  void reorderLayers(int oldIndex, int newIndex) {
    executeCommand(
      ReorderLayersCommand(oldIndex: oldIndex, newIndex: newIndex),
    );
  }

  /// Adds a new adjustment layer to the stack via an undoable command.
  void addAdjustmentLayer(AdjustmentLayer layer) {
    executeCommand(AddLayerCommand(layer));
  }

  /// Removes a layer by ID via an undoable command.
  void removeLayer(String layerId) {
    final index = _state.layerStack.layers.indexWhere((l) => l.id == layerId);
    if (index <= 0) return; // Cannot remove root source layer
    final layer = _state.layerStack.layers[index];
    executeCommand(RemoveLayerCommand(layer, index));
  }

  /// Reverts the most recent command.
  void undo() {
    final revertedStack = _history.undo(_state.layerStack);
    if (revertedStack == null) return;

    final updatedBoard = _state.variantBoard.updateActiveStack(revertedStack);
    _state = _state.copyWith(
      layerStack: revertedStack,
      variantBoard: updatedBoard,
      canUndo: _history.canUndo,
      canRedo: _history.canRedo,
      undoCount: _history.undoCount,
      redoCount: _history.redoCount,
    );
  }

  /// Re-applies the most recently reverted command.
  void redo() {
    final reappliedStack = _history.redo(_state.layerStack);
    if (reappliedStack == null) return;

    final updatedBoard = _state.variantBoard.updateActiveStack(reappliedStack);
    _state = _state.copyWith(
      layerStack: reappliedStack,
      variantBoard: updatedBoard,
      canUndo: _history.canUndo,
      canRedo: _history.canRedo,
      undoCount: _history.undoCount,
      redoCount: _history.redoCount,
    );
  }

  /// Reverts all active edits back to baseline.
  void undoAll() {
    final baseline = _history.undoAll(_state.layerStack);
    final updatedBoard = _state.variantBoard.updateActiveStack(baseline);
    _state = _state.copyWith(
      layerStack: baseline,
      variantBoard: updatedBoard,
      canUndo: false,
      canRedo: _history.canRedo,
      undoCount: 0,
      redoCount: _history.redoCount,
    );
  }

  /// Re-applies all edits back to latest state.
  void redoAll() {
    final latest = _history.redoAll(_state.layerStack);
    final updatedBoard = _state.variantBoard.updateActiveStack(latest);
    _state = _state.copyWith(
      layerStack: latest,
      variantBoard: updatedBoard,
      canUndo: _history.canUndo,
      canRedo: false,
      undoCount: _history.undoCount,
      redoCount: 0,
    );
  }

  /// Creates a new variant and switches to it.
  void createVariant(String name, {int? seed, bool isStochastic = false}) {
    final newId = 'var_${DateTime.now().millisecondsSinceEpoch}';
    final updatedBoard = _state.variantBoard.createVariant(
      id: newId,
      name: name,
      layerStack: _state.layerStack,
      randomSeed: seed,
      isStochastic: isStochastic,
      makeActive: true,
    );

    _history.clear(); // Fresh history stack for new variant branch
    _state = _state.copyWith(
      variantBoard: updatedBoard,
      canUndo: false,
      canRedo: false,
      undoCount: 0,
      redoCount: 0,
      activeWarning: isStochastic
          ? 'Stochastic AI model: minor variations across device neural runtimes may occur.'
          : null,
      clearWarning: !isStochastic,
    );
  }

  /// Switches active variant without re-decoding immutable source media.
  void switchVariant(String variantId) {
    final updatedBoard = _state.variantBoard.switchVariant(variantId);
    final active = updatedBoard.activeVariant;

    _history.clear(); // Resets local undo stack for switched branch
    _state = _state.copyWith(
      layerStack: active.layerStack,
      variantBoard: updatedBoard,
      canUndo: false,
      canRedo: false,
      undoCount: 0,
      redoCount: 0,
      activeWarning: active.stochasticWarning,
      clearWarning: active.stochasticWarning == null,
    );
  }

  /// Configures split-screen before/after comparison mode.
  void setSplitComparison(bool active, {double position = 0.5}) {
    _state = _state.copyWith(
      isSplitComparisonActive: active,
      splitPosition: position.clamp(0.0, 1.0),
    );
  }

  /// Signals cancellation for in-flight render job.
  void cancelRender() {
    _renderCancelled = true;
    _state = _state.copyWith(isRendering: false);
  }

  void startRender() {
    _renderCancelled = false;
    _state = _state.copyWith(isRendering: true);
  }

  /// Builds composite [RenderGraph] representing current active layer stack.
  RenderGraph buildRenderGraph() => _state.layerStack.toRenderGraph();
}
