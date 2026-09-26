import 'package:debrify/features/sources/presentation/source_active_filters.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final keyboard in [false, true]) {
    testWidgets(
      'clear dispatches once without mutating filters: keyboard=$keyboard',
      (tester) async {
        final filters = TorrentFilterState(
          qualities: {QualityTier.hd, QualityTier.ultraHd},
          ripSources: {RipSourceCategory.web},
          languages: {AudioLanguage.multiAudio},
          sizes: {SizeBucket.gb4to6},
          dynamicRanges: {DynamicRange.hdr},
        );
        var clears = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: Scaffold(
                body: SourceActiveFilters(
                  filters: filters,
                  accent: Colors.amber,
                  dim: Colors.grey,
                  onClear: () => clears++,
                ),
              ),
            ),
          ),
        );
        expect(
          tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
          [
            'Quality · 720p',
            'Quality · 4K',
            'Source · WEB',
            'Lang · MultiAudio',
            'Size · 4 – 6 GB',
            'Range · HDR',
            'Clear',
          ],
        );
        if (keyboard) {
          Focus.of(tester.element(find.text('Clear'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text('Clear'));
        }
        await tester.pump();
        expect(clears, 1);
        expect(filters.qualities, [QualityTier.hd, QualityTier.ultraHd]);
        expect(find.text('Range · HDR'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
