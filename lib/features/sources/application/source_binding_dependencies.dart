import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/manual_source_preparation.dart';
import '../data/source_acquisition.dart';

final sourceAcquisitionProvider = Provider<SourceAcquisition>(
  (ref) => const SourceAcquisition(),
);

final manualSourcePreparationProvider = Provider<ManualSourcePreparation>(
  (ref) => ManualSourcePreparation(
    acquisition: ref.watch(sourceAcquisitionProvider),
  ),
  dependencies: [sourceAcquisitionProvider],
);
