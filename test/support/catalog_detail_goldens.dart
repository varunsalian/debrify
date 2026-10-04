import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Keep comparison failure artifacts out of the recorded source tree.
/// Comparison, master paths and capture behavior are Flutter's defaults.
class CatalogDetailGoldenComparator extends LocalFileComparator {
  CatalogDetailGoldenComparator(super.testFile);

  @override
  File getFailureFile(String failure, Uri golden, Uri basedir) => File(
    '.dart_tool/catalog_detail_golden_failures/'
    '${golden.pathSegments.last}_$failure.png',
  );
}
