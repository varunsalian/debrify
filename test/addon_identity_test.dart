import 'package:debrify/widgets/addon_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final large in [false, true]) {
    testWidgets('missing logo keeps readable identity: large=$large', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [
        const Expanded(child: Text('Original source text')),
        AddonIdentity(name: 'AIO Streams', logo: 'invalid', large: large),
      ]))));
      expect(find.text('AS'), findsOneWidget);
      expect(find.text('AIO Streams'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
