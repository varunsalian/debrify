import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_async_authorization.dart';

typedef IptvSettingsProfileActionsDeps = ({bool Function() mounted});

class IptvSettingsProfileActions {
  IptvSettingsProfileActions(this._deps);
  final IptvSettingsProfileActionsDeps _deps;

  Future<void> runProfileAction(Future<void> Function() body) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.iptv,
    );
    if (!_deps.mounted()) return;
    if (authorization == null) {
      await body();
    } else {
      await authorization.runIfCurrent(body);
    }
  }
}
