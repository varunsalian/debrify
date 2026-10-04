import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/addon_hub_fixture.dart';

void main() {
  testWidgets(
    'same-source forced Retry publishes both responses and stale error after source return',
    (t) async {
      await hubCase(t, (f) async {
        f.responses[addonHubOfficialUrl] = http.Response('failure', 500);
        await f.mount(t);
        await f.dropdown(t, 'Installed', 'Official');
        expect(f.member('marketError'), 'Failed to load addons (500)');
        final old = Completer<http.Response>();
        f.held[addonHubOfficialUrl] = old;
        await f.tap(t, 'Retry');
        await f.until(t, () => f.requests.length == 2);
        f.held.remove(addonHubOfficialUrl);
        f.responses[addonHubOfficialUrl] = f.json([
          hubMarketEntry('new8', 'New result'),
        ]);
        final load = f.member('loadMarket') as dynamic;
        final next = load(f.member('source'), force: true) as Future<void>;
        await f.until(t, () => f.ids('market').contains('new8'));
        await next;
        old.complete(f.json([hubMarketEntry('old6', 'Old result')]));
        await f.until(t, () => f.ids('market').contains('old6'));
        expect(f.ids('market'), ['old6']);
        final error = Completer<http.Response>();
        f.held[addonHubOfficialUrl] = error;
        final older = load(f.member('source'), force: true) as Future<void>;
        await f.until(t, () => f.requests.length == 4);
        await f.dropdown(t, 'Official', 'Installed', wait: false);
        await f.dropdown(t, 'Installed', 'Official', wait: false);
        f.held.remove(addonHubOfficialUrl);
        final newer = load(f.member('source'), force: true) as Future<void>;
        await f.until(t, () => f.ids('market').contains('new8'));
        await newer;
        error.complete(http.Response('late error', 503));
        await f.until(t, () => f.member('marketError') != null);
        await older;
        expect(f.member('marketError'), 'Failed to load addons (503)');
        expect(f.ids('market'), ['new8']);
        await f.dropdown(t, 'Official', 'Installed');
        await f.dropdown(t, 'Installed', 'Official');
        expect(f.requests, List.filled(5, 'GET $addonHubOfficialUrl'));
        expect(find.text('Retry'), findsOneWidget);
      }, warm: false);
    },
  );
}
