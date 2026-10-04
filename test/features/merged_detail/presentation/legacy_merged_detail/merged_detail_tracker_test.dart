import 'dart:async';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/merged_detail_fixture.dart';

void main() {
  testWidgets(
    'pills distinguish Checking Not tracked Status unavailable and Rated',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.menus = true;
        f.heldTraktStatus = Completer<TraktTitleStatus?>();
        f.heldSimklStatus = Completer<SimklTitleStatus?>();
        f.heldMdblistStatus = Completer<MdblistTitleStatus?>();
        await f.mount(t);
        expect(
          [f.model.traktLabel, f.model.simklLabel, f.model.mdblistLabel],
          ['Checking…', 'Checking…', 'Checking…'],
        );
        f.heldTraktStatus!.complete(null);
        f.heldSimklStatus!.complete(null);
        f.heldMdblistStatus!.complete(null);
        await f.until(
          t,
          () =>
              f.model.traktLabel == 'Not tracked' &&
              f.model.mdblistLabel == 'Not tracked',
        );
        expect(
          [f.model.traktLabel, f.model.simklLabel, f.model.mdblistLabel],
          ['Not tracked', 'Not tracked', 'Not tracked'],
        );
        f.heldTraktStatus = null;
        f.heldSimklStatus = null;
        f.heldMdblistStatus = null;
        f.traktStatus = const TraktTitleStatus();
        (f.access['refresh'] as void Function())();
        await f.until(t, () => f.model.traktLabel == 'Status unavailable');
        expect(f.model.traktTracked, false);
        f.traktStatus = const TraktTitleStatus(rating: 8);
        f.simklStatus = const SimklTitleStatus(rating: 7);
        f.mdblistStatus = const MdblistTitleStatus(id: 1, rating: 6);
        (f.access['refresh'] as void Function())();
        await f.until(t, () => f.model.mdblistLabel == 'Rated');
        expect(
          [f.model.traktLabel, f.model.simklLabel, f.model.mdblistLabel],
          ['Rated', 'Rated', 'Rated'],
        );
        expect(
          [f.model.traktRating, f.model.simklRating, f.model.mdblistRating],
          [8, 7, 6],
        );
      });
    },
  );
  for (final provider in ['app', 'trakt', 'simkl', 'mdblist']) {
    testWidgets(
      '$provider clear-progress action refreshes each host loader in order',
      (t) async {
        await mergedDetailCase(t, (f) async {
          f.menus = true;
          await f.mount(t);
          f.calls.clear();
          switch (provider) {
            case 'app':
              f.model.onAppMenu!();
            case 'trakt':
              f.model.onTraktMenu!();
            case 'simkl':
              f.model.onSimklMenu!();
            case 'mdblist':
              f.model.onMdblistMenu!();
          }
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          final label = provider == 'app'
              ? 'Clear watch progress'
              : 'Clear watch progress on ${provider == 'mdblist'
                    ? 'MDBList'
                    : provider == 'trakt'
                    ? 'Trakt'
                    : 'Simkl'}';
          final row = find.text(label);
          await t.ensureVisible(row);
          await t.pump(const Duration(milliseconds: 200));
          await t.tap(row);
          await f.until(t, () => f.calls.contains('resume'));
          expect(
            f.calls
                .where(
                  (c) => ['resume', 'trakt', 'simkl', 'mdblist'].contains(c),
                )
                .take(4)
                .toList(),
            ['resume', 'trakt', 'simkl', 'mdblist'],
          );
          expect(
            f.calls.first,
            '${provider == 'app' ? 'trakt' : provider}Action:${provider == 'trakt' ? 'clearTraktProgress' : 'clearWatchProgress'}',
          );
          if (provider == 'mdblist') {
            await f.until(
              t,
              () => f.calls.where((c) => c == 'mdblist').length == 2,
            );
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));
            expect(find.text(label), findsNothing);
            expect(f.calls.where((c) => c == 'mdblist').toList(), [
              'mdblist',
              'mdblist',
            ]);
          }
        });
      },
    );
  }
  for (final provider in ['trakt', 'simkl']) {
    testWidgets(
      '$provider rating without inline callback delegates onAction rate',
      (t) async {
        await mergedDetailCase(t, (f) async {
          f.menus = true;
          f.item = const StremioMeta(
            id: 'rating-original',
            type: 'movie',
            name: 'Original Rating',
          );
          await f.mount(t);
          f.calls.clear();
          if (provider == 'trakt') {
            f.model.onTraktMenu!();
          } else {
            f.model.onSimklMenu!();
          }
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          final rating = find.text('8').last;
          await t.ensureVisible(rating);
          await t.pump(const Duration(milliseconds: 100));
          await t.tap(rating);
          await f.until(
            t,
            () => f.calls.contains(
              '$provider'
              'Action:rate',
            ),
          );
          expect(f.calls, [
            '$provider'
                'Action:rate',
            provider,
          ]);
        });
      },
    );
  }
  testWidgets(
    'Simkl active status removes from its list and keeps the sheet open',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.menus = true;
        f.simklStatus = const SimklTitleStatus(currentStatus: 'plantowatch');
        await f.mount(t);
        f.calls.clear();
        f.model.onSimklMenu!();
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        f.onAction = (value) async {
          if (value == 'simklAction:removeFromList') {
            f.simklStatus = const SimklTitleStatus();
          }
        };
        await t.ensureVisible(find.text('Plan to Watch').last);
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(find.text('Plan to Watch').last);
        await f.until(t, () => f.model.simklLabel == 'Not tracked');
        expect(f.calls, ['simklAction:removeFromList', 'simkl']);
        expect(find.text('Simkl').last, findsOneWidget);
        await t.pump();
        expect(
          t.widgetList<Switch>(find.byType(Switch)).where((s) => s.value),
          isEmpty,
        );
      });
    },
  );
  for (final provider in ['trakt', 'simkl']) {
    testWidgets(
      '$provider paused-session removal pops before dispatching the host action',
      (t) async {
        await mergedDetailCase(t, (f) async {
          f.menus = true;
          f.paused = true;
          await f.mount(t);
          final events = <String>[];
          f.onAction = (value) async {
            events.add('${f.observer.events.last}:$value');
          };
          if (provider == 'trakt') {
            f.model.onTraktMenu!();
          } else {
            f.model.onSimklMenu!();
          }
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          final label = provider == 'trakt'
              ? 'Remove from Trakt Continue Watching'
              : 'Remove from Continue Watching';
          await t.ensureVisible(find.text(label));
          await t.pump(const Duration(milliseconds: 100));
          await t.tap(find.text(label));
          await f.until(t, () => events.isNotEmpty);
          expect(events, [
            'pop:null:$provider'
                'Action:${provider == 'trakt' ? 'removeFromTraktPlayback' : 'removeFromContinueWatching'}',
          ]);
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          expect(find.text(label), findsNothing);
        });
      },
    );
  }
}
