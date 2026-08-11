import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';

import 'golden_harness.dart';
import 'surface_gallery.dart';

/// Foundation goldens: the boundary demo under legacy, one dark theme and one
/// light theme. Regenerate deliberately with:
///   flutter test test/theme/goldens_test.dart --update-goldens
void main() {
  setUpAll(disableRuntimeFonts);

  testWidgets('boundary demo — legacy', (tester) async {
    await pumpThemed(tester, const BoundaryDemo(),
        themeId: AppThemes.legacyId);
    await expectLater(
      find.byType(BoundaryDemo),
      matchesGoldenFile('goldens/boundary_demo_legacy.png'),
    );
  });

  testWidgets('boundary demo — signal (dark theme)', (tester) async {
    await pumpThemed(tester, const BoundaryDemo(), themeId: 'signal');
    await expectLater(
      find.byType(BoundaryDemo),
      matchesGoldenFile('goldens/boundary_demo_signal.png'),
    );
  });

  testWidgets('boundary demo — broadsheet (light theme)', (tester) async {
    await pumpThemed(tester, const BoundaryDemo(), themeId: 'broadsheet');
    await expectLater(
      find.byType(BoundaryDemo),
      matchesGoldenFile('goldens/boundary_demo_broadsheet.png'),
    );
  });

  testWidgets('boundary demo — broadsheet × dim (preset on a light ground)',
      (tester) async {
    await pumpThemed(tester, const BoundaryDemo(),
        themeId: 'broadsheet', preset: TextBrightness.dim);
    await expectLater(
      find.byType(BoundaryDemo),
      matchesGoldenFile('goldens/boundary_demo_broadsheet_dim.png'),
    );
  });

  // The gallery renders REAL widgets from each themed family. The boundary
  // demo above is synthetic, which is why every golden could pass while two
  // light themes had unreadable screens — these are the pixels that would
  // have shown it. `contrast_audit_test.dart` checks the same tree
  // automatically; these exist so a human can also just look.
  for (final id in const ['legacy', 'broadsheet', 'concrete', 'noir']) {
    testWidgets('surface gallery — $id', (tester) async {
      await pumpThemed(tester, const SurfaceGallery(),
          themeId: id, surface: const Size(900, 2400));
      await expectLater(
        find.byType(SurfaceGallery),
        matchesGoldenFile('goldens/surface_gallery_$id.png'),
      );
    });
  }
}
