import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';

class AddonHubInstalledState {
  final StremioService stremio = StremioService.instance;

  // Installed addons.
  List<StremioAddon> installed = const [];

  bool installedLoading = true;

  String? metadataProviderPreference;

  /// Whether any debrid/cloud provider is configured — drives the "Needs debrid"
  /// honesty badge on stream addons (debrify can't play torrents P2P).
  bool hasDebrid = true;

  int installedLoadRevision = 0;
}
