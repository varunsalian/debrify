import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/collections/collection_focus_glow.dart';
import 'package:debrify/widgets/home/card_focus_rise.dart';

void main() {
  testWidgets('collection glow retains focus ring across tile shapes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      final font = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
      await font.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: Color(0xFFA78BFA)),
          ),
          home: AppThemeScope(
            theme: AppThemes.legacy,
            child: RepaintBoundary(
              key: const ValueKey('visual'),
              child: Scaffold(
                backgroundColor: const Color(0xFF111018),
                body: Padding(
                  padding: const EdgeInsets.all(44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Collection focus glow',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 24),
                      ),
                      const SizedBox(height: 40),
                      for (final ratio in [16 / 9, 1.0, 2 / 3]) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final state in [
                              (false, true, 'Resting'),
                              (true, true, 'Focused · glow on'),
                              (true, false, 'Focused · glow off'),
                            ])
                              SizedBox(
                                width: 260,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      height: 118,
                                      width: 118 * ratio,
                                      child: CollectionFocusGlow(
                                        active: state.$1,
                                        enabled: state.$2,
                                        child: CardFocusRise(
                                          active: state.$1,
                                          isTelevision: true,
                                          aspectRatio: ratio,
                                          children: const [
                                            DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Color(0xFF43245B),
                                                    Color(0xFF191329),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      state.$3,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 30),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('visual')),
        matchesGoldenFile('goldens/collection_focus_glow.png'),
      );
    } finally {
      debugDisableShadows = oldShadows;
    }
  });
}
