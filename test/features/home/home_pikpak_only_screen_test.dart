import 'package:debrify/features/home/application/home_pikpak_only_dependencies.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import 'data/home_pikpak_only_repository_test.dart' show pikpakRepository;

void main() {
  for (final only in [false, true]) {
    testWidgets(
      'catalog quick-play follows injected PikPak-only state: $only',
      (tester) async {
        var reads = 0;
        final home = HomeFixture(tester);
        await home.mount(
          wrap: (child) => ProviderScope(
            overrides: [
              homePikpakOnlyRepositoryProvider.overrideWith(
                (ref, session) => pikpakRepository(() async {
                  reads++;
                  return only;
                }),
              ),
            ],
            child: child,
          ),
        );
        await home.drive(() => home.slow.complete(page('Slow')));
        await home.settle();
        final card =
            tester.widget(
                  find
                      .byWidgetPredicate(
                        (widget) =>
                            widget.runtimeType.toString() == 'HomeCatalogCard' &&
                            (widget as dynamic).item.name == 'Fast 0',
                      )
                      .first,
                )
                as dynamic;
        expect(reads, greaterThan(0));
        expect(card.onQuickPlay, only ? isNull : isNotNull);
        expect(tester.takeException(), isNull);
        await home.dispose();
      },
    );
  }
}
