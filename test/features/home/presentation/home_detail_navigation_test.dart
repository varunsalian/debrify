import 'dart:async';

import 'package:debrify/features/home/data/home_catalog_origin_repository.dart';
import 'package:debrify/features/home/models/home_catalog_origin.dart';
import 'package:debrify/features/home/presentation/home_detail_navigation.dart';
import 'package:debrify/features/home/presentation/home_detail_route.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const item = StremioMeta(
  id: 'tt1234567',
  imdbId: 'tt1234567',
  name: 'Title',
  type: 'series',
);
final addon = StremioAddon(
  id: 'addon',
  name: 'Addon',
  baseUrl: '',
  manifestUrl: '',
);

class Origin extends HomeCatalogOriginRepository {
  Origin(this.result)
    : super(
        nativeAddon: addon,
        isOwnerCurrent: () => true,
        scopeProgress: (item, _, _) async => item,
        readCustomOrigin: (_) async => null,
      );
  final Future<HomeCatalogOrigin> result;
  @override
  Future<HomeCatalogOrigin> prepare(
    StremioMeta item,
    StremioAddon addon, {
    required bool Function() isCurrent,
  }) => result;
}

class Fixture {
  Fixture(this.tester, Future<HomeCatalogOrigin> prepared)
    : navigation = HomeDetailNavigation(Origin(prepared));
  final WidgetTester tester;
  final HomeDetailNavigation navigation;
  final navigator = GlobalKey<NavigatorState>();
  final calls = <String>[];
  bool active = true;
  late BuildContext context;
  HomeDetailRoute? route;
  Future<bool> Function(String)? remove;

  Future<void> mount() => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    ),
  );

  Future<void> open() => navigation.open(
    context: context,
    item: item,
    addon: addon,
    routeName: 'detail',
    isCurrent: () => active,
    hasLocalHistory: (_) => true,
    removeLocalHistory: (id) {
      calls.add('remove:$id');
      return remove?.call(id) ?? Future.value(true);
    },
    onHistoryRemoved: () async => calls.add('refresh'),
    showMessage: calls.add,
    onClosed: () => calls.add('closed'),
    prepareBuilder: (resolved, origin, detailRoute) {
      expectSync(resolved, same(item));
      expectSync(origin, same(addon));
      expectSync(detailRoute.isActive, isFalse);
      route = detailRoute;
      calls.add('prepare');
      return (_) {
        calls.add('build');
        return const Scaffold(body: Text('Detail'));
      };
    },
  );
}

void main() {
  testWidgets('prepares snapshots before push and refreshes once on return', (
    tester,
  ) async {
    final f = Fixture(
      tester,
      Future.value(HomeCatalogOrigin.ready(item, addon)),
    );
    await f.mount();
    final pending = f.open();
    await tester.pumpAndSettle();
    expect(f.calls.take(2), ['prepare', 'build']);
    expect(f.route!.isActive, isTrue);
    f.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await pending;
    expect(f.calls.where((event) => event == 'closed'), hasLength(1));
  });

  testWidgets('retired preparation never constructs a route or snapshots', (
    tester,
  ) async {
    final release = Completer<HomeCatalogOrigin>();
    final f = Fixture(tester, release.future);
    await f.mount();
    final pending = f.open();
    f.active = false;
    release.complete(HomeCatalogOrigin.ready(item, addon));
    await tester.pumpAndSettle();
    await pending;
    expect(f.calls, isEmpty);
  });

  testWidgets(
    'unverified origin retains the retry message without navigation',
    (tester) async {
      final f = Fixture(
        tester,
        Future.value(const HomeCatalogOrigin.unverified(item)),
      );
      await f.mount();
      await f.open();
      expect(f.calls, ['Could not verify series episodes. Please retry.']);
      expect(f.navigator.currentState!.canPop(), isFalse);
    },
  );

  for (final retire in [false, true]) {
    testWidgets(
      'accepted missing-origin deletion refreshes only current view: $retire',
      (tester) async {
        final release = Completer<bool>();
        final f = Fixture(
          tester,
          Future.value(const HomeCatalogOrigin.unavailable(item)),
        )..remove = (_) => release.future;
        await f.mount();
        final pending = f.open();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove from Continue Watching'));
        await tester.pumpAndSettle();
        expect(f.calls, ['remove:tt1234567']);
        f.active = !retire;
        release.complete(true);
        await tester.pumpAndSettle();
        await pending;
        expect(f.calls, ['remove:tt1234567', if (!retire) 'refresh']);
        expect(f.route, isNull);
      },
    );
  }
}
