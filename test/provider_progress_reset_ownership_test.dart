import 'dart:async';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/widgets/clear_provider_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final duringWrite in [false, true]) {
    testWidgets(
      'provider reset captures origin before confirmation: accepted=$duringWrite',
      (tester) async {
        final origin = ProfileScope(
          profileId: 'origin',
          dataGeneration: 1,
          sessionEpoch: 1,
        );
        final other = ProfileScope(
          profileId: 'other',
          dataGeneration: 1,
          sessionEpoch: 2,
        );
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeCommitted(origin);
        addTearDown(ProfileRuntime.debugReset);
        final release = Completer<void>();
        final scopes = <ProfileScope?>[];
        Future<void>? pending;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    pending = showClearProviderProgressDialog(
                      context,
                      const StremioMeta(
                        id: 'tt1',
                        name: 'Fixture',
                        type: 'movie',
                      ),
                      TrackingSource.simkl,
                      reset: () async {
                        scopes.add(ProfileRuntime.capture());
                        await release.future;
                        scopes.add(ProfileRuntime.capture());
                        return [];
                      },
                    );
                  },
                  child: const Text('Reset'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Reset'));
        await tester.pumpAndSettle();
        if (duringWrite) {
          await tester.tap(find.text('Clear progress'));
          await tester.pump();
          expect(scopes, [origin]);
        }
        ProfileSessionMemory.clearAll();
        ProfileRuntime.publish(other);
        if (!duringWrite) await tester.tap(find.text('Clear progress'));
        release.complete();
        await pending;
        await tester.pumpAndSettle();
        expect(scopes, duringWrite ? [origin, origin] : isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('Clearing watch progress…'), findsNothing);
      },
    );
  }
}
