import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/settings_widgets_fixture.dart';

const _arrows = [
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
];

void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  for (final width in [390.0, 900.0]) {
    final wide = width > 520;
    for (final mdblist in [false, true]) {
      testWidgets('Ledger card edges wide=$wide mdblist=$mdblist', (
        tester,
      ) async {
        await settingsWidgetsCase(tester, (f) async {
          f.blockIgnoredArrows = true;
          f.width = width;
          f.scrollable = true;
          await tester.pumpWidget(
            f.host(f.summary(mdblist: mdblist, ledger: true)),
          );
          await tester.pump();
          final cards = {
            for (final c in tester.widgetList<ConnectionCard>(
              find.byType(ConnectionCard),
            ))
              c.info.title: c,
          };
          // [left, right, up, down] for the tracker section only.
          final expected = <String, List<String?>>{
            'Trakt': [
              null,
              wide ? 'Simkl' : null,
              'Policy',
              wide ? (mdblist ? 'MDBList' : 'Ledger') : 'Simkl',
            ],
            'Simkl': [
              wide ? 'Trakt' : null,
              null,
              wide ? 'Policy' : 'Trakt',
              !wide && mdblist ? 'MDBList' : 'Ledger',
            ],
            if (mdblist)
              'MDBList': [
                null,
                wide ? 'Ledger' : null,
                wide ? 'Trakt' : 'Simkl',
                wide ? null : 'Ledger',
              ],
            'Ledger': [
              wide && mdblist ? 'MDBList' : null,
              null,
              wide
                  ? (mdblist ? 'Simkl' : 'Trakt')
                  : (mdblist ? 'MDBList' : 'Simkl'),
              null,
            ],
          };
          final nodes = {
            for (final entry in cards.entries)
              if (entry.value.focusNode case final node?) entry.key: node,
          };
          expect(
            cards['Ledger']!.isLeftColumn,
            !wide || !mdblist,
            reason: 'Ledger partners MDBList on wide layouts',
          );
          for (final entry in expected.entries) {
            final card = cards[entry.key]!;
            final fields = [
              card.leftNeighbor,
              card.rightNeighbor,
              card.upNeighbor,
              card.downNeighbor,
            ];
            for (var i = 0; i < 4; i++) {
              final destination = entry.value[i];
              expect(
                fields[i],
                destination == null ? isNull : same(nodes[destination]),
                reason: '${entry.key} ${_arrows[i]}',
              );
              if (destination == null) continue;
              card.focusNode!.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(_arrows[i]);
              await tester.pump();
              expect(
                nodes[destination]!.hasFocus,
                isTrue,
                reason: '${entry.key} -> $destination',
              );
              await tester.pump(const Duration(milliseconds: 300));
            }
          }
          await tester.pumpWidget(f.host(const SizedBox.shrink()));
        });
      });
    }
  }
}
