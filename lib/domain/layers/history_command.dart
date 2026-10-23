import 'editor_layer.dart';

/// Abstract contract for a reversible, non-destructive editing command.
/// Operates on command deltas (Invariant 11) to guarantee bounded memory.
abstract class EditCommand {
  final String description;

  const EditCommand(this.description);

  /// Applies the forward transformation to the layer stack.
  LayerStack execute(LayerStack current);

  /// Reverts the transformation back to the prior state.
  LayerStack undo(LayerStack current);

  /// Estimates the approximate memory footprint in bytes of this command object.
  int estimateBytes();
}

/// Changes the opacity of a specific layer.
class SetLayerOpacityCommand extends EditCommand {
  final String layerId;
  final double oldOpacity;
  final double newOpacity;

  SetLayerOpacityCommand({
    required this.layerId,
    required this.oldOpacity,
    required this.newOpacity,
  }) : super('Set layer opacity');

  @override
  LayerStack execute(LayerStack current) {
    final layer = current.layers.firstWhere((l) => l.id == layerId);
    return current.updateLayer(layer.copyWith(opacity: newOpacity));
  }

  @override
  LayerStack undo(LayerStack current) {
    final layer = current.layers.firstWhere((l) => l.id == layerId);
    return current.updateLayer(layer.copyWith(opacity: oldOpacity));
  }

  @override
  int estimateBytes() => 64 + layerId.length;
}

/// Changes the blend mode of an adjustment layer.
class SetLayerBlendModeCommand extends EditCommand {
  final String layerId;
  final BlendModeType oldMode;
  final BlendModeType newMode;

  const SetLayerBlendModeCommand({
    required this.layerId,
    required this.oldMode,
    required this.newMode,
  }) : super('Set layer blend mode');

  @override
  LayerStack execute(LayerStack current) {
    final layer = current.layers.firstWhere((l) => l.id == layerId);
    if (layer is AdjustmentLayer) {
      return current.updateLayer(layer.copyWith(blendMode: newMode));
    }
    return current;
  }

  @override
  LayerStack undo(LayerStack current) {
    final layer = current.layers.firstWhere((l) => l.id == layerId);
    if (layer is AdjustmentLayer) {
      return current.updateLayer(layer.copyWith(blendMode: oldMode));
    }
    return current;
  }

  @override
  int estimateBytes() => 64 + layerId.length;
}

/// Toggles the visibility of a layer.
class ToggleLayerVisibilityCommand extends EditCommand {
  final String layerId;
  final bool oldVisibility;
  final bool newVisibility;

  const ToggleLayerVisibilityCommand({
    required this.layerId,
    required this.oldVisibility,
    required this.newVisibility,
  }) : super(newVisibility ? 'Show layer' : 'Hide layer');

  @override
  LayerStack execute(LayerStack current) {
    final layer = current.layers.firstWhere((l) => l.id == layerId);
    return current.updateLayer(layer.copyWith(isVisible: newVisibility));
  }

  @override
  LayerStack undo(LayerStack current) {
    final layer = current.layers.firstWhere((l) => l.id == layerId);
    return current.updateLayer(layer.copyWith(isVisible: oldVisibility));
  }

  @override
  int estimateBytes() => 48 + layerId.length;
}

/// Reorders a layer from [oldIndex] to [newIndex].
class ReorderLayersCommand extends EditCommand {
  final int oldIndex;
  final int newIndex;

  const ReorderLayersCommand({required this.oldIndex, required this.newIndex})
    : super('Reorder layer from index $oldIndex to $newIndex');

  @override
  LayerStack execute(LayerStack current) => current.reorder(oldIndex, newIndex);

  @override
  LayerStack undo(LayerStack current) => current.reorder(newIndex, oldIndex);

  @override
  int estimateBytes() => 64;
}

/// Appends a new layer to the stack.
class AddLayerCommand extends EditCommand {
  final EditorLayer layer;

  AddLayerCommand(this.layer) : super('Add layer');

  @override
  LayerStack execute(LayerStack current) => current.addLayer(layer);

  @override
  LayerStack undo(LayerStack current) => current.removeLayer(layer.id);

  @override
  int estimateBytes() => 128 + layer.id.length + layer.name.length;
}

/// Removes a layer from the stack.
class RemoveLayerCommand extends EditCommand {
  final EditorLayer layer;
  final int originalIndex;

  RemoveLayerCommand(this.layer, this.originalIndex) : super('Remove layer');

  @override
  LayerStack execute(LayerStack current) => current.removeLayer(layer.id);

  @override
  LayerStack undo(LayerStack current) {
    final copy = List<EditorLayer>.from(current.layers);
    final clampedIndex = originalIndex.clamp(1, copy.length);
    copy.insert(clampedIndex, layer);
    return LayerStack(copy);
  }

  @override
  int estimateBytes() => 128 + layer.id.length + layer.name.length;
}

/// Updates the parametric configuration of an adjustment layer.
class UpdateAdjustmentParametersCommand extends EditCommand {
  final String layerId;
  final Map<String, dynamic> oldParameters;
  final Map<String, dynamic> newParameters;

  const UpdateAdjustmentParametersCommand({
    required this.layerId,
    required this.oldParameters,
    required this.newParameters,
  }) : super('Update layer parameters');

  @override
  LayerStack execute(LayerStack current) {
    final layer =
        current.layers.firstWhere((l) => l.id == layerId) as AdjustmentLayer;
    return current.updateLayer(layer.copyWith(parameters: newParameters));
  }

  @override
  LayerStack undo(LayerStack current) {
    final layer =
        current.layers.firstWhere((l) => l.id == layerId) as AdjustmentLayer;
    return current.updateLayer(layer.copyWith(parameters: oldParameters));
  }

  @override
  int estimateBytes() => 128 + layerId.length + (newParameters.length * 32);
}

/// Compound command batching multiple granular commands atomically.
class CompoundCommand extends EditCommand {
  final List<EditCommand> commands;

  CompoundCommand({required String description, required this.commands})
    : super(description);

  @override
  LayerStack execute(LayerStack current) {
    var state = current;
    for (final cmd in commands) {
      state = cmd.execute(state);
    }
    return state;
  }

  @override
  LayerStack undo(LayerStack current) {
    var state = current;
    // Undo in reverse order
    for (int i = commands.length - 1; i >= 0; i--) {
      state = commands[i].undo(state);
    }
    return state;
  }

  @override
  int estimateBytes() {
    int sum = 64;
    for (final cmd in commands) {
      sum += cmd.estimateBytes();
    }
    return sum;
  }
}

/// Bounded-memory manager maintaining undo and redo command delta stacks.
/// Strictly enforces Invariant 11: 100 edits consume < 100 KB RAM.
class HistoryManager {
  final int maxCapacity;
  final List<EditCommand> _undoStack = [];
  final List<EditCommand> _redoStack = [];

  HistoryManager({this.maxCapacity = 100})
    : assert(maxCapacity > 0, 'Capacity must be positive');

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// Applies [command], pushes to undo stack, and purges redo stack.
  LayerStack executeCommand(LayerStack current, EditCommand command) {
    final updated = command.execute(current);
    _undoStack.add(command);
    _redoStack.clear();

    // History compaction: Evict oldest command if exceeding capacity
    if (_undoStack.length > maxCapacity) {
      _undoStack.removeAt(0);
    }

    return updated;
  }

  /// Reverts the most recent command.
  LayerStack? undo(LayerStack current) {
    if (_undoStack.isEmpty) return null;
    final cmd = _undoStack.removeLast();
    _redoStack.add(cmd);
    return cmd.undo(current);
  }

  /// Re-applies the most recently reverted command.
  LayerStack? redo(LayerStack current) {
    if (_redoStack.isEmpty) return null;
    final cmd = _redoStack.removeLast();
    _undoStack.add(cmd);
    return cmd.execute(current);
  }

  /// Reverts all active commands back to baseline state.
  LayerStack undoAll(LayerStack current) {
    var state = current;
    while (canUndo) {
      state = undo(state)!;
    }
    return state;
  }

  /// Re-applies all reverted commands back to latest state.
  LayerStack redoAll(LayerStack current) {
    var state = current;
    while (canRedo) {
      state = redo(state)!;
    }
    return state;
  }

  /// Computes the total memory consumed by all command descriptors across both stacks.
  int estimateTotalMemoryBytes() {
    int total = 0;
    for (final cmd in _undoStack) {
      total += cmd.estimateBytes();
    }
    for (final cmd in _redoStack) {
      total += cmd.estimateBytes();
    }
    return total;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
