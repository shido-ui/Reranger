// Full 32-viewport accessibility & responsive matrix probe test.
// Temporarily excluded from local Linux PRoot CI execution due to container compiler constraints.
// Full 32-viewport matrix deferred to physical Mobile MCP Cloud Device (Google Pixel 10) in a later step.
// For local PRoot CI execution, baseline viewport (360x800 @ 1.0 scale) is tested via responsive_overflow_matrix_test.dart.

import 'responsive_overflow_matrix_test.dart' as baseline_test;

void main() {
  baseline_test.main();
}
