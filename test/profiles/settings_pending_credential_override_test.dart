import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/screens/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a working provider credential wins over a pending shared grant', () {
    const pending = <ConnectionResourceType>{ConnectionResourceType.realDebrid};
    const provider = <ConnectionResourceType>{
      ConnectionResourceType.realDebrid,
    };

    expect(
      shouldApplyPendingCredentialOverride(
        pendingTypes: pending,
        providerTypes: provider,
        ownCredentialPresent: true,
      ),
      isFalse,
    );
    expect(
      shouldApplyPendingCredentialOverride(
        pendingTypes: pending,
        providerTypes: provider,
        ownCredentialPresent: false,
      ),
      isTrue,
    );
  });

  test('expired own Trakt credential keeps its Expired status', () {
    var status = 'Expired';

    if (shouldApplyPendingCredentialOverride(
      pendingTypes: const <ConnectionResourceType>{
        ConnectionResourceType.trakt,
      },
      providerTypes: const <ConnectionResourceType>{
        ConnectionResourceType.trakt,
      },
      ownCredentialPresent: true,
    )) {
      status = 'Attention';
    }

    expect(status, 'Expired');
  });
}
