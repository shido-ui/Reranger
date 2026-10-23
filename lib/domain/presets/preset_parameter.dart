/// Specification of an adjustable preset slider parameter.
/// Enforces beginner-first sensible defaults (Invariant 3) and bounded input validation.
class PresetParameter {
  final String id;
  final String label;
  final double min;
  final double max;
  final double defaultValue;
  final double step;
  final String? unit;

  const PresetParameter({
    required this.id,
    required this.label,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.step = 0.01,
    this.unit,
  }) : assert(id.length > 0, 'Parameter ID cannot be empty'),
       assert(min <= max, 'min ($min) must be <= max ($max)'),
       assert(
         defaultValue >= min && defaultValue <= max,
         'Default ($defaultValue) must be in [$min, $max]',
       );

  /// Clamps an input value to the valid range [min, max].
  double clamp(double value) {
    if (!value.isFinite) return defaultValue;
    return value.clamp(min, max);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'min': min,
    'max': max,
    'defaultValue': defaultValue,
    'step': step,
    'unit': unit,
  };

  factory PresetParameter.fromJson(Map<String, dynamic> json) {
    return PresetParameter(
      id: json['id'] as String,
      label: json['label'] as String,
      min: (json['min'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
      defaultValue: (json['defaultValue'] as num).toDouble(),
      step: (json['step'] as num?)?.toDouble() ?? 0.01,
      unit: json['unit'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresetParameter &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          min == other.min &&
          max == other.max &&
          defaultValue == other.defaultValue;

  @override
  int get hashCode => Object.hash(id, min, max, defaultValue);
}
