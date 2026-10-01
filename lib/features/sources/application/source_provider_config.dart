import 'dart:async';

import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/source_provider_configuration.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/torrent_provider_storage.dart';

final class SourceProviderConfig {
  const SourceProviderConfig._();

  /// Distinguishes "user dismissed the provider picker" (silent) from
  /// "no provider configured" (null → prompt to add one in Settings).
  static const String cancelled = '__cancelled__';

  /// The provider a "Load more sources" fetch should search with: the
  /// launch's own debrid provider, except non-debrid launches (bound 'local'
  /// source, addon 'stream') resolve the default configured one instead.
  /// Null (nothing configured) fails the fetch soft.
  static Future<String?> effectiveFetchProvider(String? provider) async {
    if (provider != null &&
        provider != SeriesSource.localService &&
        provider != SeriesSource.addonDirectService &&
        provider != SeriesSource.iptvDirectService &&
        provider != SeriesSource.mediaServerService &&
        provider != 'stream') {
      return provider;
    }
    return defaultConfiguredProvider();
  }

  /// Real-Debrid is `'rd'` in [SeriesSource] (Home's convention, shared
  /// storage) but `'debrid'` as this service's provider key. Map between them so
  /// bindings created in Home replay here and vice-versa.
  static String providerFromStored(String stored) =>
      stored == 'rd' ? 'debrid' : stored;

  static String storedProviderKey(String provider) =>
      AutomaticSourceBindings.storedProviderKey(provider);

  /// Providers whose bound sources this isolated engine can replay — the five
  /// debrid providers plus 'local' (on-device file/folder).
  static bool boundProviderSupported(String stored) {
    const supported = {
      'rd',
      'torbox',
      'premiumize',
      'alldebrid',
      'pikpak',
      SeriesSource.localService,
      SeriesSource.addonDirectService,
      SeriesSource.iptvDirectService,
      SeriesSource.mediaServerService,
    };
    return supported.contains(stored);
  }

  /// Providers with credentials configured (in this service's precedence
  /// order) plus the user's saved default when it's still configured — the
  /// single source of truth shared by [_pickProvider] and
  /// [_defaultConfiguredProvider], so adding a provider is a one-list edit.
  static Future<(List<String>, String?)?> configuredProviders({
    bool Function()? canContinue,
  }) => loadSourceProviderConfiguration(
    isConfigured: (provider) =>
        _isConfigured(provider, canContinue: canContinue),
    readDefault: TorrentProviderStorage.getDefaultTorrentProvider,
    canContinue: canContinue,
  );

  /// The provider a silent (no-dialog) resolution should use: the configured
  /// default, else the first configured one, else null. Uses this service's
  /// _pickProvider precedence (Premiumize before PikPak) — deliberately NOT
  /// Home's resolver order, which prefers PikPak; a silent PikPak fallback
  /// would queue real downloads on the account.
  static Future<String?> defaultConfiguredProvider({
    bool Function()? canContinue,
  }) async {
    final configuration = await configuredProviders(canContinue: canContinue);
    if (configuration == null) return null;
    final (configured, def) = configuration;
    if (configured.isEmpty) return null;
    return def ?? configured.first;
  }

  static Future<bool> _isConfigured(
    String provider, {
    bool Function()? canContinue,
  }) async {
    switch (provider) {
      case 'debrid':
        return (await RealDebridStorage.getApiKey(
              canContinue: canContinue,
            ))?.isNotEmpty ??
            false;
      case 'torbox':
        return (await TorboxStorage.getTorboxApiKey(
              canContinue: canContinue,
            ))?.isNotEmpty ??
            false;
      case 'premiumize':
        return (await PremiumizeStorage.getPremiumizeApiKey(
              canContinue: canContinue,
            ))?.isNotEmpty ??
            false;
      case 'alldebrid':
        return (await AllDebridStorage.getAllDebridApiKey(
              canContinue: canContinue,
            ))?.isNotEmpty ??
            false;
      case 'pikpak':
        return PikpakStorage.getPikPakEnabled(canContinue: canContinue);
      default:
        return false;
    }
  }
}
