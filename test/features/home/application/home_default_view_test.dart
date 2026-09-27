import 'dart:async';
import 'package:debrify/features/home/application/home_default_view.dart';
import 'package:debrify/features/search/models/search_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final saved in [
    null,
    'catalog',
    'lists',
    'trakt',
    'KEYWORD',
    'keyword',
  ]) {
    test(
      'saved $saved selects only the exact supported keyword value',
      () async {
        final selected = <SearchMode>[];
        final operation = HomeDefaultView(
          readSaved: () async => saved,
          keywordAllowed: () => true,
          isOwnerCurrent: () => true,
        );
        await operation.load(
          isTelevision: false,
          isHome: true,
          isCurrent: () => true,
          select: selected.add,
        );
        expect(selected, [
          saved == 'keyword' ? SearchMode.keyword : SearchMode.catalog,
        ]);
      },
    );
  }

  test(
    'TV selects synchronously without reading storage or keyword policy',
    () async {
      final selected = <SearchMode>[];
      final operation = HomeDefaultView(
        readSaved: () => throw StateError('unexpected read'),
        keywordAllowed: () => throw StateError('unexpected policy'),
        isOwnerCurrent: () => true,
      );
      final pending = operation.load(
        isTelevision: true,
        isHome: false,
        isCurrent: () => true,
        select: selected.add,
      );
      expect(selected, [SearchMode.catalog]);
      await pending;
    },
  );

  test('permission is evaluated after storage completes', () async {
    final response = Completer<String?>();
    var allowed = true;
    final selected = <SearchMode>[];
    final operation = HomeDefaultView(
      readSaved: () => response.future,
      keywordAllowed: () => allowed,
      isOwnerCurrent: () => true,
    );
    final pending = operation.load(
      isTelevision: false,
      isHome: true,
      isCurrent: () => true,
      select: selected.add,
    );
    allowed = false;
    response.complete('keyword');
    await pending;
    expect(selected, [SearchMode.catalog]);
  });

  test('newer request retires an older pending default', () async {
    final response = Completer<String?>();
    var reads = 0;
    final selected = <SearchMode>[];
    final operation = HomeDefaultView(
      readSaved: () => ++reads == 1 ? response.future : Future.value('keyword'),
      keywordAllowed: () => true,
      isOwnerCurrent: () => true,
    );
    final old = operation.load(
      isTelevision: false,
      isHome: true,
      isCurrent: () => true,
      select: selected.add,
    );
    await operation.load(
      isTelevision: false,
      isHome: true,
      isCurrent: () => true,
      select: selected.add,
    );
    response.complete('catalog');
    await old;
    expect(selected, [SearchMode.keyword]);
  });

  for (final reason in ['owner', 'view', 'dispose']) {
    test(
      '$reason retirement suppresses late mode selection and policy reads',
      () async {
        final response = Completer<String?>();
        var owner = true;
        var view = true;
        final operation = HomeDefaultView(
          readSaved: () => response.future,
          keywordAllowed: () => throw StateError('retired policy'),
          isOwnerCurrent: () => owner,
        );
        final pending = operation.load(
          isTelevision: false,
          isHome: true,
          isCurrent: () => view,
          select: (_) => fail('retired selection'),
        );
        switch (reason) {
          case 'owner':
            owner = false;
          case 'view':
            view = false;
          case 'dispose':
            operation.dispose();
        }
        response.complete('keyword');
        await pending;
      },
    );
  }

  test(
    'rejected action neither reads storage nor cancels a valid pending read',
    () async {
      final response = Completer<String?>();
      var reads = 0;
      final selected = <SearchMode>[];
      final operation = HomeDefaultView(
        readSaved: () {
          reads++;
          return response.future;
        },
        keywordAllowed: () => true,
        isOwnerCurrent: () => true,
      );
      final accepted = operation.load(
        isTelevision: false,
        isHome: true,
        isCurrent: () => true,
        select: selected.add,
      );
      await operation.load(
        isTelevision: false,
        isHome: true,
        isCurrent: () => false,
        select: (_) => fail('rejected selection'),
      );
      response.complete('keyword');
      await accepted;
      expect(reads, 1);
      expect(selected, [SearchMode.keyword]);
    },
  );

  test('non-Home retains its existing post-read no-selection guard', () async {
    var reads = 0;
    final operation = HomeDefaultView(
      readSaved: () async {
        reads++;
        return 'keyword';
      },
      keywordAllowed: () => throw StateError('non-Home policy'),
      isOwnerCurrent: () => true,
    );
    await operation.load(
      isTelevision: false,
      isHome: false,
      isCurrent: () => true,
      select: (_) => fail('non-Home selection'),
    );
    expect(reads, 1);
  });

  test('failed read propagates without selecting a mode', () async {
    final operation = HomeDefaultView(
      readSaved: () async => throw StateError('storage'),
      keywordAllowed: () => true,
      isOwnerCurrent: () => true,
    );
    await expectLater(
      operation.load(
        isTelevision: false,
        isHome: true,
        isCurrent: () => true,
        select: (_) => fail('failed selection'),
      ),
      throwsStateError,
    );
  });
}
