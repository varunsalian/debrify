import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/data/home_bound_counts_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture;

void main() {
  testWidgets(
    'displayed catalog cards receive bound badges from the injected reader',
    (tester) async {
      final calls = <String>[];
      final home = HomeFixture(tester);
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            homeBoundCountsRepositoryProvider.overrideWith(
              (ref, session) => HomeBoundCountsRepository(
                readCount: (id, current) async {
                  calls.add(id);
                  return 2;
                },
              ),
            ),
          ],
          child: child,
        ),
      );
      await home.drive(
        () => home.slow.complete(
          http.Response(
            jsonEncode({
              'metas': [
                {
                  'id': 'tmdb:movie:1234567',
                  'type': 'movie',
                  'name': 'Bound fixture',
                },
              ],
            }),
            200,
          ),
        ),
      );
      await home.settle();
      final card =
          tester.widget(
                find
                    .byWidgetPredicate(
                      (widget) =>
                          widget.runtimeType.toString() == 'HomeCatalogCard' &&
                          (widget as dynamic).item.name == 'Bound fixture',
                    )
                    .first,
              )
              as dynamic;
      expect(calls, contains('tmdb:movie:1234567'));
      expect(card.hasBoundSource, isTrue);
      expect(tester.takeException(), isNull);
      await home.dispose();
    },
  );
}
