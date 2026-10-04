import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/addon_hub_fixture.dart';

void main() {
  testWidgets(
    'cold Community paginates in order deduplicates and launches visible attribution',
    (t) async {
      await hubCase(t, (f) async {
        f.onRequest = (r) async {
          if (r.url.host == 'stremio-addons.net') {
            final page = r.url.queryParameters['page'];
            return f.json({
              'addons': page == '1'
                  ? f.market
                  : [f.market.first, hubMarketEntry('a6', 'Fourth')],
              'pagination': {'totalPages': 2},
            });
          }
          return f.respond(r);
        };
        await f.mount(t);
        await f.dropdown(t, 'Installed', 'Community');
        expect(f.requests, [
          'GET $addonHubCommunityUrl',
          'GET ${addonHubCommunityUrl.replaceFirst('page=1', 'page=2')}',
        ]);
        expect(f.ids('market'), ['m7', 'z9', 'b3', 'a6']);
        expect(StremioMarketplaceService.instance.communityFromNet, isTrue);
        expect(find.textContaining('stremio-addons.net'), findsOneWidget);
        await t.tap(find.textContaining('stremio-addons.net'));
        await t.pump();
        expect(f.urls.calls.single.$1, 'https://stremio-addons.net');
        await f.dropdown(t, 'Community', 'Installed');
        await f.dropdown(t, 'Installed', 'Community');
        expect(f.requests, hasLength(2));
      }, warm: false);
    },
  );
}
