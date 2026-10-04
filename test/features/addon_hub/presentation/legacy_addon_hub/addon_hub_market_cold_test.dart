import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/addon_hub_fixture.dart';

void main() {
  testWidgets(
    'cold Official request aliases service list and cached source roundtrip',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        expect(f.clients, hasLength(1));
        expect(f.setupRequests, isEmpty);
        await f.dropdown(t, 'Installed', 'Official');
        expect(f.requests, ['GET $addonHubOfficialUrl']);
        expect(f.ids('market'), ['m7', 'z9', 'b3']);
        final cached = await StremioMarketplaceService.instance.fetchOfficial();
        expect(
          (f.member('marketIdenticalTo') as bool Function(Object))(cached),
          isTrue,
        );
        await f.dropdown(t, 'Official', 'Installed');
        await f.dropdown(t, 'Installed', 'Official');
        expect(f.requests, ['GET $addonHubOfficialUrl']);
      }, warm: false);
    },
  );
}
