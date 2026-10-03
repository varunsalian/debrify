import 'dart:async';
import 'dart:io' show Platform;
import 'package:debrify/features/settings/presentation/legacy_settings/search_index/settings_search_index.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_layout_composition.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_sections.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_snacks.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summaries.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summary_refresh.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_updates.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import '../services/analytics_service.dart';
import '../services/live_recording_service.dart';
import '../services/main_page_bridge.dart';
import 'settings/settings_search.dart';
import 'settings/widgets/settings_widgets.dart';

export 'package:debrify/features/settings/application/settings_pending_credentials.dart'
    show shouldApplyPendingCredentialOverride;

/// Test access to the production builders and a delayed completion helper.
@visibleForTesting
({
  List<SettingsSearchEntry> Function() index,
  List<SettingsSearchEntry> Function() leaves,
  void Function(String) snack,
})
settingsScreenTestAccess(State<SettingsScreen> state) {
  final settings = state as _SettingsScreenState;
  return (
    index: settings._searchIndex.buildSearchIndex,
    leaves: settings._searchIndex.leafSearchEntries,
    snack: settings._snacks.showSnack,
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.summaryReadOverrides = const {}});

  @visibleForTesting
  final Map<String, Future<Object?> Function()> summaryReadOverrides;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsSections _sections =
      SettingsSections(_summaries, _firstCardFocusNode, (
        context: () => context,
        mounted: () => mounted,
        setState: setState,
        summaryReadOverrides: () => widget.summaryReadOverrides,
        focusFirstCard: focusFirstCard,
      ));
  SettingsSummaryRefresh get _summaryRefresh => _sections.summaryRefresh;
  SettingsUpdates get _updates => _sections.updates;
  SettingsSnacks get _snacks => _sections.snacks;
  SettingsSearchIndex get _searchIndex => _sections.searchIndex;
  SettingsLayoutComposition get _layoutComposition =>
      _sections.layoutComposition;

  final SettingsSummaries _summaries = SettingsSummaries();

  // Focus node for the first connection card (Real-Debrid) for TV navigation
  final FocusNode _firstCardFocusNode = FocusNode(debugLabel: 'firstCardFocus');

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? _tvContentFocusHandler;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('settings');
    _summaryRefresh.loadSummaries();
    _summaryRefresh.loadSupportConfig();
    _summaryRefresh.loadDownloadLocation();
    // IPTV recording exists where its engine can run (Android 10+, or pre-Q
    // with the grantable legacy storage path) — the search index must not
    // advertise it elsewhere.
    if (!kIsWeb && Platform.isAndroid) {
      LiveRecordingService.engineSupport().then((support) {
        if (support != 'unsupported' && mounted) {
          setState(() => _summaries.recordingSearchable = true);
        }
      });
    }

    // Register TV sidebar focus handler (tab index 8 = Settings)
    _tvContentFocusHandler = () {
      _firstCardFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(8, _tvContentFocusHandler!);
  }

  @override
  void dispose() {
    if (_tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        8,
        _tvContentFocusHandler!,
      );
    }
    _firstCardFocusNode.dispose();
    _updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The whole tab renders under the scoped settings theme so inline
    // Material widgets (progress spinners, switches) match the subpages.
    // Dialogs shown from this State's context sit ABOVE this Theme, so they
    // go through showSettingsDialog instead.
    if (_summaries.loading) {
      return Theme(
        data: settingsPageTheme(context),
        child: const SettingsSkeleton(),
      );
    }

    return Theme(
      data: settingsPageTheme(context),
      child: Column(
        children: [
          if (_summaries.summaryLoadFailed ||
              _summaries.summaryFailures.isNotEmpty)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "Some items couldn't load — open them to retry or sign in.",
                  key: const ValueKey('settings-summary-attention'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          Expanded(
            child: _summaries.isAndroidTv
                ? _layoutComposition.buildTvLayout()
                : _layoutComposition.buildLayout(context),
          ),
        ],
      ),
    );
  }

  void focusFirstCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _firstCardFocusNode.requestFocus();
      }
    });
  }
}
