import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/addon_hub_fixture.dart';

void main() {
  testWidgets(
    'cold Community fallback owns separate cached URL and hides attribution',
    (t) async {
      await hubCase(t, (f) async {
        f.responses[addonHubCommunityUrl] = http.Response('failure', 500);
        await f.mount(t);
        await f.dropdown(t, 'Installed', 'Community');
        expect(f.requests, [
          'GET $addonHubCommunityUrl',
          'GET $addonHubFallbackUrl',
        ]);
        expect(f.ids('market'), ['m7', 'z9', 'b3']);
        expect(StremioMarketplaceService.instance.communityFromNet, isFalse);
        expect(find.textContaining('stremio-addons.net'), findsNothing);
        await f.dropdown(t, 'Community', 'Installed');
        await f.dropdown(t, 'Installed', 'Community');
        expect(f.requests, hasLength(2));
        await StremioMarketplaceService.instance.fetchCommunity(
          forceRefresh: true,
        );
        expect(f.requests, [
          'GET $addonHubCommunityUrl',
          'GET $addonHubFallbackUrl',
          'GET $addonHubCommunityUrl',
          'GET $addonHubFallbackUrl',
        ]);
      }, warm: false);
    },
  );
}
