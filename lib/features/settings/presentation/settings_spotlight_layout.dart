import 'dart:async';
import 'package:debrify/screens/settings/settings_spotlight_shell.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'settings_categories.dart';
import 'settings_layout.dart';

Widget buildSpotlightLayout(SettingsLayout layout, BuildContext context) {
  final attention = layout.providerConnections.where(
    settingsConnectionNeedsAttention,
  );
  final attentionCount = attention.length;
  final readyCount = layout.providerConnections
      .where(settingsConnectionIsReady)
      .length;
  final firstAttention = attention.isEmpty ? null : attention.first;
  final summaryTone = attentionCount == 0
      ? SettingsSummaryTone.good
      : SettingsSummaryTone.attention;
  final summaryTitle = attentionCount > 0
      ? '$attentionCount connection${attentionCount == 1 ? '' : 's'} need attention.'
      : readyCount > 0
      ? 'Everything connected looks ready.'
      : 'Connect a playback service.';
  final summarySubtitle = attentionCount > 0
      ? '${firstAttention!.title} reports ${firstAttention.status.toLowerCase()}. '
            'Review it before your next playback.'
      : readyCount > 0
      ? '$readyCount services are configured on this device.'
      : 'Add a debrid, cloud, or IPTV service to get started.';
  final summaryTarget = firstAttention ?? layout.providerConnections.first;
  return SettingsSpotlightShell(
    categories: kAdaptiveSettingsCategories,
    onOpenSearch: layout.onOpenSearch,
    compactSummary: SettingsSpotlightSummaryCard(
      eyebrow: attentionCount > 0 ? 'Connection check' : 'Service health',
      title: summaryTitle,
      subtitle: summarySubtitle,
      actionLabel: attentionCount > 0
          ? 'Review ${summaryTarget.title}'
          : readyCount > 0
          ? 'Manage connections'
          : 'Connect a service',
      tone: summaryTone,
      onTap: () => unawaited(summaryTarget.onTap()),
    ),
    categoryBuilder: layout.buildSpotlightCategory,
  );
}
