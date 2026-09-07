/// Which debrid provider a playback path should use — moved verbatim out of
/// [TorrentPlaybackService] (lane T4). Prefs and the cloud registry only: no
/// BuildContext, no widgets. The host keeps the *dialog* (`_pickProvider`),
/// which asks this unit for the list it offers.
library;

import '../cloud/cloud_provider_id.dart';
import '../cloud/cloud_provider_registry.dart';
import '../storage/provider_credential_prefs.dart';

class PlaybackProviderResolution {
  const PlaybackProviderResolution._();

  /// Providers with credentials configured (in this service's precedence
  /// order) plus the user's saved default when it's still configured — the
  /// single source of truth shared by the host's `_pickProvider` and
  /// [defaultConfiguredProvider], so adding a provider is a one-list edit.
  static Future<(List<String>, String?)> configuredProviders() async {
    final configured = <String>[];
    for (final p in CloudProviderId.playbackPrecedence) {
      if (await isConfigured(p.playbackId)) configured.add(p.playbackId);
    }
    if (configured.isEmpty) return (configured, null);
    final def = await ProviderCredentialPrefs.getDefaultTorrentProvider();
    final defaultProvider = (def != 'none' && configured.contains(def))
        ? def
        : null;
    return (configured, defaultProvider);
  }

  /// The provider a silent (no-dialog) resolution should use: the configured
  /// default, else the first configured one, else null. Uses this service's
  /// _pickProvider precedence (Premiumize before PikPak) — deliberately NOT
  /// Home's resolver order, which prefers PikPak; a silent PikPak fallback
  /// would queue real downloads on the account.
  static Future<String?> defaultConfiguredProvider() async {
    final (configured, def) = await configuredProviders();
    if (configured.isEmpty) return null;
    return def ?? configured.first;
  }

  static Future<bool> isConfigured(String provider) =>
      CloudProviderRegistry.instance.isConfigured(provider);
}
