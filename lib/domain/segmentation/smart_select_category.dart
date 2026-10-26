/// Semantic categories supported by SAM 2.1 zero-shot segmentation.
enum SmartSelectCategory {
  hair(hintId: 1, label: 'Hair'),
  face(hintId: 2, label: 'Face'),
  clothing(hintId: 3, label: 'Clothing'),
  background(hintId: 4, label: 'Background'),
  general(hintId: 0, label: 'Auto');

  final int hintId;
  final String label;

  const SmartSelectCategory({required this.hintId, required this.label});
}
