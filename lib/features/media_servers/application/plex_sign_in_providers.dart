import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../utils/platform_util.dart';
import '../data/plex/plex_sign_in.dart';

/// Composition for the Plex sign-in: the only place that names the concrete
/// plex.tv adapter. Tests override these.
final plexSignInGatewayProvider = Provider<PlexSignInGateway>(
  (ref) => PlexAccountSignIn(),
);

final plexSignInClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final plexSignInDelayProvider = Provider<Future<void> Function(Duration)>(
  (ref) => Future<void>.delayed,
);

/// The active profile session; a change abandons the sign-in.
final plexSignInScopeProvider = Provider<Object? Function()>(
  (ref) =>
      () => ProfileRuntime.scope.value,
);

/// Opens plex.tv/link in the browser where a browser is at hand. Null on
/// TVs, where people use their phone instead.
final plexOpenLinkProvider = Provider<Future<bool> Function()?>(
  (ref) => PlatformUtil.isTelevision
      ? null
      : () => launchUrl(
          Uri.parse('https://plex.tv/link'),
          mode: LaunchMode.externalApplication,
        ),
);
