import 'dart:async';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_kinds.dart';
import 'package:debrify/features/debrify_tv/presentation/debrify_tv_choice_chip.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/debrify_tv_filters.dart';
import 'package:flutter/material.dart';

class DebrifyTvSettingsChips {
  final DebrifyTvDependencies _deps;
  DebrifyTvSettingsChips(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  /// Quality + size pickers for Debrify TV playback. One shared setting for
  /// both channels and quick play, so the same feed rules apply wherever you
  /// start watching. Nothing selected in a row = that facet is off.
  Widget tvFilterChips({StateSetter? dialogSetState}) {
    void applyFilters(DebrifyTvFilters next) {
      _deps.setState(() => _owners.settings.tvFilters = next);
      // "At your quality" is computed WITH the filter; stale memos would
      // keep the old filter's count while playback uses the new one.
      _sections.stage.invalidateSpotlightStats();
      dialogSetState?.call(() {});
    }

    void toggleQuality(QualityTier quality) {
      final next = Set<QualityTier>.from(_owners.settings.tvFilters.qualities);
      if (!next.remove(quality)) next.add(quality);
      applyFilters(
        DebrifyTvFilters(
          qualities: next,
          sizes: _owners.settings.tvFilters.sizes,
        ),
      );
      unawaited(
        DebrifyTvStorage.setDebrifyTvFilterQualities(
          next.map((e) => e.name).toList(),
        ),
      );
    }

    void toggleSize(SizeBucket bucket) {
      final next = Set<SizeBucket>.from(_owners.settings.tvFilters.sizes);
      if (!next.remove(bucket)) next.add(bucket);
      applyFilters(
        DebrifyTvFilters(
          qualities: _owners.settings.tvFilters.qualities,
          sizes: next,
        ),
      );
      unawaited(
        DebrifyTvStorage.setDebrifyTvFilterSizes(
          next.map((e) => e.name).toList(),
        ),
      );
    }

    final labelStyle = Theme.of(_deps.context()).textTheme.bodySmall?.copyWith(
      color: AppThemeScope.of(_deps.context()).debrifyTv.textMeta,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Playback filters',
          style: Theme.of(
            _deps.context(),
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          'Applies to channels and quick play. If nothing matches, Debrify TV '
          'plays what it can rather than showing an empty channel.',
          style: labelStyle,
        ),
        const SizedBox(height: 10),
        Text('Quality', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final quality in QualityTier.values)
              debrifyTvChoiceChip(
                label: DebrifyTvFilters.qualityLabel(quality),
                selected: _owners.settings.tvFilters.qualities.contains(
                  quality,
                ),
                enabled: !_owners.session.isBusy,
                onPressed: () => toggleQuality(quality),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('File size (per episode/movie)', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final bucket in SizeBucket.values)
              debrifyTvChoiceChip(
                label: DebrifyTvFilters.sizeLabel(bucket),
                selected: _owners.settings.tvFilters.sizes.contains(bucket),
                enabled: !_owners.session.isBusy,
                onPressed: () => toggleSize(bucket),
              ),
          ],
        ),
      ],
    );
  }

  Widget providerChoiceChips(
    DebrifyTvSettingsScope scope, {
    StateSetter? dialogSetState,
  }) {
    final bool isQuickScope = scope == DebrifyTvSettingsScope.quickPlay;
    final String currentProvider = isQuickScope
        ? _owners.settings.quickProvider
        : _owners.settings.provider;

    void handleSelection(String value) {
      if (!_sections.settings.isProviderSelectable(value)) {
        return;
      }
      if (isQuickScope) {
        if (_owners.settings.quickProvider == value) {
          return;
        }
        _deps.setState(() {
          _owners.settings.quickProvider = value;
        });
        dialogSetState?.call(() {});
        return;
      }

      if (_owners.settings.provider == value) {
        return;
      }
      _deps.setState(() {
        _owners.settings.provider = value;
      });
      dialogSetState?.call(() {});
      unawaited(DebrifyTvStorage.saveDebrifyTvProvider(value));
    }

    Widget providerChip({
      required String value,
      required String label,
      required bool available,
      required String unavailableMessage,
    }) {
      return Tooltip(
        message: available ? 'Use $label for Debrify TV' : unavailableMessage,
        child: debrifyTvChoiceChip(
          label: label,
          selected: currentProvider == value,
          enabled: available && !_owners.session.isBusy,
          onPressed: () => handleSelection(value),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        providerChip(
          value: DebrifyTvConstants.providerRealDebrid,
          label: 'Real Debrid',
          available: _owners.settings.rdAvailable,
          unavailableMessage:
              'Enable Real Debrid and add an API key in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerTorbox,
          label: 'Torbox',
          available: _owners.settings.torboxAvailable,
          unavailableMessage: 'Enable Torbox and add an API key in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerPikPak,
          label: 'PikPak',
          available: _owners.settings.pikpakAvailable,
          unavailableMessage: 'Log in to PikPak in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerPremiumize,
          label: 'Premiumize',
          available: _owners.settings.premiumizeAvailable,
          unavailableMessage:
              'Enable Premiumize and add an API key in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerAllDebrid,
          label: 'AllDebrid',
          available: _owners.settings.allDebridAvailable,
          unavailableMessage:
              'Enable AllDebrid and add an API key in Settings.',
        ),
      ],
    );
  }
}
