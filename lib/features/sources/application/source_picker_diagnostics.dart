import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/source_selection_diagnostics.dart';

typedef SourcePickerDiagnostics =
    void Function(String event, Map<String, Object?> fields);

/// Stateless app-scoped sink; the view captures it before any delayed reveal.
final sourcePickerDiagnosticsProvider = Provider<SourcePickerDiagnostics>(
  (ref) => logSourcePickerEvent,
);
