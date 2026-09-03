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
        configured: true,
      ),
      isFalse,
    );
    expect(
      shouldApplyPendingCredentialOverride(
        pendingTypes: pending,
        providerTypes: provider,
        configured: false,
      ),
      isTrue,
    );
  });
}
