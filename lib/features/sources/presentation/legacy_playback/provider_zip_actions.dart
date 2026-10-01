import 'dart:async';

import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/provider_source_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/provider_accepted_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/widgets/debrid_loading_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class ProviderZipActions {
  const ProviderZipActions._();

  // ── Provider-specific power actions (TorBox / Premiumize) ───────────────────

  static Future<void> copyTorboxZipLink(
    BuildContext context,
    int torrentId, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: ProviderAcceptedActions.acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    final String? url;
    try {
      url = await actions.torboxZipUrl(torrentId);
    } catch (_) {
      return;
    }
    if (url == null || !actions.isCurrent) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted && actions.isCurrent) {
      SourceLoadingOverlays.snack(
        context,
        'ZIP download link copied to clipboard!',
      );
    }
  }

  static Future<void> downloadTorboxZip(
    BuildContext context,
    int torrentId,
    String name, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: ProviderAcceptedActions.acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    try {
      final queued = await actions.queueTorboxZip(torrentId, name);
      if (context.mounted && queued && actions.isCurrent) {
        SourceLoadingOverlays.snack(context, 'ZIP download queued.');
      }
    } catch (_) {
      if (context.mounted && actions.isCurrent) {
        SourceLoadingOverlays.snack(context, 'Failed to queue ZIP download.');
      }
    }
  }

  static Future<void> premiumizeTransfer(
    BuildContext context,
    String magnet, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: ProviderAcceptedActions.acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    try {
      final accepted = await actions.transferPremiumize(magnet);
      if (context.mounted && accepted && actions.isCurrent) {
        SourceLoadingOverlays.snack(
          context,
          'Added to Premiumize. It will be available once the download finishes.',
        );
      }
    } catch (_) {
      if (context.mounted && actions.isCurrent) {
        SourceLoadingOverlays.snack(
          context,
          'Failed to transfer to Premiumize.',
        );
      }
    }
  }

  static Future<void> premiumizeZip(
    BuildContext context,
    String magnet,
    String name, {
    required bool copyOnly,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: ProviderAcceptedActions.acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    DebridLoadingHandle? loading;
    String? url;
    var failed = false;
    try {
      url = await actions.premiumizeZipUrl(
        magnet,
        onStarted: () {
          if (context.mounted) {
            loading = DebridLoadingOverlay.showPremiumize(context, name);
          }
        },
      );
    } catch (_) {
      failed = true;
    } finally {
      loading?.dismiss();
    }
    if (failed) {
      if (context.mounted && actions.isCurrent) {
        SourceLoadingOverlays.snack(
          context,
          copyOnly ? 'Failed to generate ZIP link.' : 'Failed to generate ZIP.',
        );
      }
      return;
    }
    if (url == null || !actions.isCurrent) return;
    try {
      if (copyOnly) {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted && actions.isCurrent) {
          SourceLoadingOverlays.snack(
            context,
            'ZIP download link copied to clipboard!',
          );
        }
      } else {
        await actions.queueUrl(
          url,
          provider: 'premiumize',
          fileName: '$name.zip',
          torrentName: name,
        );
        if (context.mounted && actions.isCurrent) {
          SourceLoadingOverlays.snack(
            context,
            'ZIP download queued successfully.',
          );
        }
      }
    } catch (_) {
      if (context.mounted && actions.isCurrent) {
        SourceLoadingOverlays.snack(
          context,
          copyOnly ? 'Failed to generate ZIP link.' : 'Failed to generate ZIP.',
        );
      }
    }
  }
}
