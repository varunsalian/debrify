import 'dart:async';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/settings_widgets_fixture.dart';

const arrows = [
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
];

// Keep real FocusNode behavior. Track disposal only so a broken widget cannot
// mask the public usability expectation with a second disposal in host cleanup.
class _BorrowedFirstNode extends FocusNode {
  _BorrowedFirstNode() : super(debugLabel: 'first');
  bool wasDisposed = false;
  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

void main() {
  for (final width in [390.0, 520.0, 521.0, 900.0]) {
    final wide = width > 520;
    final suffix = width == 520 || width == 521 ? ' width=$width' : '';
    for (final media in [false, true]) {
      for (final mdblist in [false, true]) {
        testWidgets(
          'Connections every edge wide=$wide media=$media mdblist=$mdblist$suffix',
          (tester) async {
            await settingsWidgetsCase(tester, (f) async {
              f.blockIgnoredArrows = true;
              f.width = width;
              f.scrollable = true;
              final first = _BorrowedFirstNode();
              addTearDown(() {
                if (!first.wasDisposed) {
                  first.dispose();
                }
              });
              await tester.pumpWidget(
                f.host(f.summary(media: media, mdblist: mdblist, first: first)),
              );
              await tester.pump();
              final cards = {
                for (final c in tester.widgetList<ConnectionCard>(
                  find.byType(ConnectionCard),
                ))
                  c.info.title: c,
              };
              final expected = <String, List<String?>>{
                'Real Debrid': [
                  null,
                  wide ? 'TorBox' : null,
                  null,
                  wide ? 'Premiumize' : 'TorBox',
                ],
                'TorBox': [
                  wide ? 'Real Debrid' : null,
                  null,
                  wide ? null : 'Real Debrid',
                  wide ? 'AllDebrid' : 'Premiumize',
                ],
                'Premiumize': [
                  null,
                  wide ? 'AllDebrid' : null,
                  wide ? 'Real Debrid' : 'TorBox',
                  wide ? 'PikPak' : 'AllDebrid',
                ],
                'AllDebrid': [
                  wide ? 'Premiumize' : null,
                  null,
                  wide ? 'TorBox' : 'Premiumize',
                  wide ? 'WebDAV' : 'PikPak',
                ],
                'PikPak': [
                  null,
                  wide ? 'WebDAV' : null,
                  wide ? 'Premiumize' : 'AllDebrid',
                  wide ? 'Indexers' : 'WebDAV',
                ],
                'WebDAV': [
                  wide ? 'PikPak' : null,
                  null,
                  wide ? 'AllDebrid' : 'PikPak',
                  wide ? 'IPTV' : 'Indexers',
                ],
                'Indexers': [
                  null,
                  wide ? 'IPTV' : null,
                  wide ? 'PikPak' : 'WebDAV',
                  wide ? (media ? 'Media servers' : 'Policy') : 'IPTV',
                ],
                'IPTV': [
                  wide ? 'Indexers' : null,
                  null,
                  wide ? 'WebDAV' : 'Indexers',
                  media ? 'Media servers' : 'Policy',
                ],
                if (media) 'Media servers': [null, null, 'IPTV', 'Policy'],
                'Policy': [
                  null,
                  null,
                  media ? 'Media servers' : (wide ? 'Indexers' : 'IPTV'),
                  'Trakt',
                ],
                'Trakt': [
                  null,
                  wide ? 'Simkl' : null,
                  'Policy',
                  wide && mdblist ? 'MDBList' : 'Simkl',
                ],
                'Simkl': [
                  wide ? 'Trakt' : null,
                  null,
                  wide ? 'Policy' : 'Trakt',
                  !wide && mdblist ? 'MDBList' : null,
                ],
                if (mdblist)
                  'MDBList': [null, null, wide ? 'Trakt' : 'Simkl', null],
              };
              expect(cards.keys.toSet(), expected.keys.toSet());
              final nodes = {
                for (final entry in cards.entries)
                  entry.key: entry.value.focusNode!,
              };
              for (final entry in cards.entries) {
                final card = entry.value;
                final expectedWidth =
                    ['Policy', 'Media servers'].contains(entry.key)
                    ? width
                    : wide
                    ? (width - 10) / 2
                    : width;
                expect(
                  tester
                      .getSize(
                        find.byWidgetPredicate(
                          (w) =>
                              w is ConnectionCard && w.info.title == entry.key,
                        ),
                      )
                      .width,
                  closeTo(expectedWidth, 0.001),
                  reason: entry.key,
                );
                expect(
                  card.isLeftColumn,
                  !wide ||
                      ![
                        'TorBox',
                        'AllDebrid',
                        'WebDAV',
                        'IPTV',
                        'Simkl',
                      ].contains(entry.key),
                  reason: entry.key,
                );
                final fields = [
                  card.leftNeighbor,
                  card.rightNeighbor,
                  card.upNeighbor,
                  card.downNeighbor,
                ];
                for (var i = 0; i < 4; i++) {
                  final destination = expected[entry.key]![i];
                  expect(
                    fields[i],
                    destination == null ? isNull : same(nodes[destination]),
                    reason: '${entry.key} ${arrows[i]} field',
                  );
                  card.focusNode!.requestFocus();
                  await tester.pump();
                  f.events.clear();
                  await tester.sendKeyDownEvent(arrows[i]);
                  expect(
                    f.events.whereType<KeyDownEvent>(),
                    destination == null ? hasLength(1) : isEmpty,
                    reason: '${entry.key} ${arrows[i]} handled',
                  );
                  await tester.pump();
                  expect(
                    (destination == null
                            ? card.focusNode!
                            : nodes[destination]!)
                        .hasFocus,
                    isTrue,
                    reason: '${entry.key} -> $destination',
                  );
                  await tester.sendKeyUpEvent(arrows[i]);
                  expect(f.events.whereType<KeyUpEvent>(), hasLength(1));
                  await tester.pump(const Duration(milliseconds: 300));
                }
              }
              await tester.pumpWidget(f.host(const SizedBox.shrink()));
              expect(first.requestFocus, returnsNormally);
              expect(() => first.addListener(() {}), returnsNormally);
            });
          },
        );
      }
    }
  }
  testWidgets('ConnectionCard repeat/up are ignored; tap awaits callback', (
    tester,
  ) async {
    await settingsWidgetsCase(tester, (f) async {
      f.blockIgnoredArrows = true;
      final a = f.node('a');
      final b = f.node('b');
      await tester.pumpWidget(
        f.host(
          Column(
            children: [
              ConnectionCard(info: f.info('A'), focusNode: a, downNeighbor: b),
              ConnectionCard(info: f.info('B'), focusNode: b),
            ],
          ),
        ),
      );
      a.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      a.requestFocus();
      await tester.pump();
      f.events.clear();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(f.events.whereType<KeyRepeatEvent>(), hasLength(1));
      expect(a.hasFocus, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      expect(f.events.whereType<KeyUpEvent>(), hasLength(1));
      await tester.tap(find.text('A').last);
      await tester.pump();
      expect(f.callbacks, ['A']);
    });
  });
  testWidgets('ConnectionCard awaits the async tap completion', (tester) async {
    await settingsWidgetsCase(tester, (f) async {
      final gate = Completer<void>();
      try {
        final info = ConnectionInfo(
          title: 'Async provider',
          connected: true,
          status: 'Active',
          caption: '',
          onTap: () => gate.future,
        );
        await tester.pumpWidget(f.host(ConnectionCard(info: info)));
        final ink = tester.widget<InkWell>(find.byType(InkWell));
        final dynamic activate = ink.onTap;
        final completion = activate() as Future<void>;
        var finished = false;
        completion.then((_) {
          finished = true;
        });
        await tester.pump();
        expect(finished, isFalse);
        gate.complete();
        await tester.pump();
        expect(finished, isTrue);
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }
    });
  });
  for (final present in [false, true]) {
    for (final left in [false, true]) {
      testWidgets('sidebar callback=$present left=$left', (tester) async {
        await settingsWidgetsCase(tester, (f) async {
          MainPageBridge.focusTvSidebar = present
              ? () {
                  f.callbacks.add('sidebar');
                }
              : null;
          final node = f.node('card');
          await tester.pumpWidget(
            f.host(
              ConnectionCard(
                info: f.info('Card'),
                focusNode: node,
                isLeftColumn: left,
              ),
            ),
          );
          node.requestFocus();
          await tester.pump();
          f.events.clear();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
          expect(tester.takeException(), isNull);
          expect(f.callbacks, present && left ? ['sidebar'] : isEmpty);
          expect(
            f.events.whereType<KeyDownEvent>(),
            present && left ? isEmpty : hasLength(1),
          );
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
        });
      });
    }
  }
  testWidgets(
    'neighbour reveal is deferred post-frame with scaled tempo target and curve',
    (tester) async {
      await settingsWidgetsCase(tester, (f) async {
        f.scrollable = true;
        // The public scope carries a supported non-unit tempo into AppMotion.
        final look = AppThemes.byId('broadsheet');
        f.app = AppTheme.fromDetail(
          look.core,
          motion: look.motion.copyWith(scale: 1.15),
        );
        final a = f.node('top');
        final b = f.node('below');
        await tester.pumpWidget(
          f.host(
            Column(
              children: [
                ConnectionCard(
                  info: f.info('Top'),
                  focusNode: a,
                  downNeighbor: b,
                ),
                const SizedBox(height: 1100),
                ConnectionCard(info: f.info('Below'), focusNode: b),
                const SizedBox(height: 200),
              ],
            ),
          ),
        );
        a.requestFocus();
        await tester.pump();
        f.scroll.calls.clear();
        final rect = tester.getRect(find.text('Below'));
        expect(rect.top, greaterThan(tester.view.physicalSize.height));
        final targetRect = tester.getRect(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is ConnectionCard && w.info.title == 'Below',
            ),
            matching: find.byType(InkWell),
          ),
        );
        final expectedTarget =
            (targetRect.bottom + 24 - tester.view.physicalSize.height).clamp(
              0.0,
              f.scroll.position.maxScrollExtent,
            );
        final motion = AppMotion.of(tester.element(find.text('Top')));
        expect(motion.tokens.scale, isNot(1));
        expect(motion.reduced, isFalse);
        final expectedDuration = motion.scaled(
          const Duration(milliseconds: 200),
        );
        expect(expectedDuration, const Duration(milliseconds: 230));
        expect(expectedDuration, isNot(const Duration(milliseconds: 200)));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        expect(f.scroll.calls, isEmpty);
        await tester.pump();
        expect(f.scroll.calls, hasLength(1));
        final call = f.scroll.calls.single;
        expect(call.phase, SchedulerPhase.postFrameCallbacks);
        expect(call.duration, expectedDuration);
        expect(call.curve, Curves.easeOutCubic);
        expect(call.target, closeTo(expectedTarget, 0.01));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 300));
      });
    },
  );
  testWidgets(
    'unattached neighbour remains handled and reveal does not throw',
    (tester) async {
      await settingsWidgetsCase(tester, (f) async {
        f.blockIgnoredArrows = true;
        final attached = f.node('attached');
        final detached = f.node('detached');
        await tester.pumpWidget(
          f.host(
            ConnectionCard(
              info: f.info('Attached'),
              focusNode: attached,
              downNeighbor: detached,
            ),
          ),
        );
        attached.requestFocus();
        await tester.pump();
        expect(detached.context, isNull);
        f.events.clear();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        expect(f.events.whereType<KeyDownEvent>(), isEmpty);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(detached.context, isNull);
        expect(f.scroll.calls, isEmpty);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      });
    },
  );
}
