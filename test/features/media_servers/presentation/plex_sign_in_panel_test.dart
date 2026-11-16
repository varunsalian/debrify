import 'package:debrify/features/media_servers/application/plex_sign_in_providers.dart';
import 'package:debrify/features/media_servers/presentation/plex_sign_in_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_plex_sign_in.dart';

void main() {
  late FakePlexSignIn gateway;
  late int done;
  final label = TextEditingController(text: 'Den');

  setUp(() {
    gateway = FakePlexSignIn()..signInAfterPolls = 1;
    done = 0;
  });

  Future<void> pump(WidgetTester tester, {bool canOpenLink = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plexSignInGatewayProvider.overrideWithValue(gateway),
          plexSignInClockProvider.overrideWithValue(() => gateway.now),
          plexSignInDelayProvider.overrideWithValue(
            (_) => Future<void>.delayed(const Duration(milliseconds: 10)),
          ),
          plexSignInScopeProvider.overrideWithValue(() => 'profile'),
          plexOpenLinkProvider.overrideWithValue(
            canOpenLink ? () async => true : null,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  // Like the connect page: a focused field above the panel.
                  TextField(controller: label, autofocus: true),
                  PlexSignInPanel(label: label, onDone: () => done++),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Leaving the page disposes the sign-in; its last poll timer runs out.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    expect(gateway.attempts.every((a) => a.closed), isTrue);
  }

  String? focusedText(WidgetTester tester) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return null;
    final texts = <String>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text && widget.data != null) texts.add(widget.data!);
      element.visitChildElements(visit);
    }

    (focused as Element).visitChildElements(visit);
    return texts.isEmpty ? null : texts.first;
  }

  testWidgets('the remote can sign in, choose a server and finish', (
    tester,
  ) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusedText(tester), 'Sign in with Plex');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(find.text('AB1Z'), findsOneWidget);
    expect(
      find.text('On your phone or computer, go to plex.tv/link and enter:'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Code A B 1 Z'), findsOneWidget);
    expect(find.text('Open plex.tv/link'), findsNothing);
    expect(focusedText(tester), 'Cancel');

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Choose a server'), findsOneWidget);
    expect(focusedText(tester), 'Home');
    expect(
      find.text(
        "Allow an unencrypted connection to this server's local address",
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(gateway.connects, [('home', false, 'Den')]);
    expect(done, 1);
  });

  testWidgets('touch devices get a link button, focused first', (tester) async {
    await pump(tester, canOpenLink: true);
    await tester.tap(find.text('Sign in with Plex'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Open plex.tv/link'), findsOneWidget);
    expect(focusedText(tester), 'Open plex.tv/link');
    await leave(tester);
  });

  testWidgets('an expired code offers a new one', (tester) async {
    gateway.expireOnPoll = true;
    await pump(tester);
    await tester.tap(find.text('Sign in with Plex'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(
      find.text('This code expired before it was entered.'),
      findsOneWidget,
    );
    expect(focusedText(tester), 'Get a new code');

    gateway.expireOnPoll = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(find.text('AB2Z'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Sign in with Plex'), findsOneWidget);
    await leave(tester);
  });
}
