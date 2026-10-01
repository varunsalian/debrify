import 'dart:async';

import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/provider_source_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/provider_accepted_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/features/sources/presentation/source_provider_picker.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/storage/torrent_provider_storage.dart';
import 'package:debrify/widgets/not_cached_dialog.dart';
import 'package:debrify/widgets/provider_picker_dialog.dart';
import 'package:flutter/material.dart';

final class SourceProviderChoice {
  const SourceProviderChoice._();

  static List<Color> providerGradient(String provider) {
    switch (provider) {
      case 'debrid':
        return const [Color(0xFF10B981), Color(0xFF059669)];
      case 'torbox':
        return const [Color(0xFF8B5CF6), Color(0xFF7C3AED)];
      case 'premiumize':
        return const [Color(0xFFF59E0B), Color(0xFFD97706)];
      case 'alldebrid':
        return const [Color(0xFF26A69A), Color(0xFF00796B)];
      case 'pikpak':
        return const [Color(0xFF6366F1), Color(0xFF4338CA)];
      default:
        return const [Color(0xFF6366F1), Color(0xFF4338CA)];
    }
  }

  static IconData providerIcon(String provider) {
    switch (provider) {
      case 'debrid':
        return Icons.cloud_download_rounded;
      case 'torbox':
        return Icons.flash_on_rounded;
      case 'premiumize':
        return Icons.workspace_premium_rounded;
      case 'alldebrid':
        return Icons.all_inclusive_rounded;
      case 'pikpak':
        return Icons.cloud_circle_rounded;
      default:
        return Icons.cloud_download_rounded;
    }
  }

  // ── Not-cached handling (mirrors Home UX: warn, then keep-downloading) ──────

  static Future<void> handleNotCached(
    BuildContext context,
    Object marker,
    String provider,
    String magnet, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: ProviderAcceptedActions.acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    final keep = await showNotCachedDialog(context, label(provider));
    if (!context.mounted || !actions.isCurrent) return;
    try {
      await actions.decideNotCached(marker, provider, magnet, keep: keep);
    } catch (_) {
      if (!context.mounted || !actions.isCurrent) return;
      rethrow;
    }
    if (context.mounted && keep && actions.isCurrent) {
      SourceLoadingOverlays.snack(
        context,
        'Added — it will download on ${label(provider)}. Play it once ready.',
      );
    }
  }

  // ── Provider resolution ────────────────────────────────────────────────────

  /// Resolves which provider to use. Honours the default; when none is set and
  /// more than one is configured, asks the user (mirrors Home's behaviour).
  static Future<String?> pickProvider(
    BuildContext context, {
    bool Function()? canContinue,
  }) => pickSourceProvider(
    context,
    cancelledProvider: SourceProviderConfig.cancelled,
    canContinue: canContinue,
    loadConfiguration: () =>
        SourceProviderConfig.configuredProviders(canContinue: canContinue),
    optionFor: (provider) => ProviderPickerOption(
      id: provider,
      label: label(provider),
      gradient: providerGradient(provider),
      icon: providerIcon(provider),
    ),
    remember: (provider) => TorrentProviderStorage.setDefaultTorrentProvider(
      provider,
      canContinue: canContinue,
    ),
  );

  static String label(String provider) {
    switch (provider) {
      case 'preparing':
        return 'Preparing';
      case 'debrid':
        return 'Real-Debrid';
      case 'torbox':
        return 'TorBox';
      case 'premiumize':
        return 'Premiumize';
      case 'alldebrid':
        return 'AllDebrid';
      case 'pikpak':
        return 'PikPak';
      case SeriesSource.localService:
        return 'On-device';
      case SeriesSource.addonDirectService:
        return 'Direct addon';
      case SeriesSource.iptvDirectService:
        return 'IPTV';
      case SeriesSource.mediaServerService:
        return 'Media server';
      case 'stream':
        return 'Stream';
      default:
        return provider;
    }
  }

  /// Two-letter provider glyph for the Pipeline loader's provider chip.
  static String providerCode(String provider) {
    switch (provider) {
      case 'preparing':
        return '···';
      case 'debrid':
        return 'RD';
      case 'torbox':
        return 'TB';
      case 'premiumize':
        return 'PM';
      case 'alldebrid':
        return 'AD';
      case 'pikpak':
        return 'PP';
      case 'stream':
        return 'TV';
      case SeriesSource.addonDirectService:
        return 'DL';
      case SeriesSource.iptvDirectService:
        return 'TV';
      default:
        return provider.isEmpty ? '·' : provider.substring(0, 1).toUpperCase();
    }
  }
}
