import 'dart:async';

import 'package:debrify/features/stremio_tv/models/stremio_tv_playback_records.dart';

import 'package:debrify/features/stremio_tv/presentation/stremio_tv_source_picker_controls.dart';

import 'package:debrify/models/torrent.dart';

import 'package:debrify/theme/app_theme_scope.dart';

import 'package:debrify/utils/formatters.dart';

import 'package:debrify/utils/source_quality.dart';

import 'package:flutter/material.dart';

// ─── Manual Source Picker (shown when auto-play fails) ────────────────────
class _ManualSourcePickerSheet extends StatefulWidget {
  final List<Torrent> sources;
  final Future<String?> Function(Torrent) resolver;
  final Future<bool> Function(String url) validateDirectUrl;

  const _ManualSourcePickerSheet({
    required this.sources,
    required this.resolver,
    required this.validateDirectUrl,
  });

  @override
  State<_ManualSourcePickerSheet> createState() =>
      _ManualSourcePickerSheetState();
}

class _ManualSourcePickerSheetState
    extends State<StremioTvManualSourcePickerSheet> {
  int? _resolvingIndex; // index in widget.sources (original)
  int? _failedIndex; // index of last failed source
  final _firstItemFocusNode = FocusNode();
  final _firstTabFocusNode = FocusNode();
  int _activeTab = 0; // 0 = All, 1 = Direct, 2 = Torrent

  late List<Torrent> _directSources;
  late List<Torrent> _torrentSources;

  @override
  void initState() {
    super.initState();
    _directSources = widget.sources.where((t) => t.isDirectStream).toList();
    _torrentSources = widget.sources
        .where((t) => t.streamType == StreamType.torrent)
        .toList();
    // Auto-focus first item after build (for DPAD)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstItemFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstItemFocusNode.dispose();
    _firstTabFocusNode.dispose();
    super.dispose();
  }

  List<Torrent> get _filteredSources {
    switch (_activeTab) {
      case 1:
        return _directSources;
      case 2:
        return _torrentSources;
      default:
        return widget.sources;
    }
  }

  String _parseQuality(String name) {
    return sourceQualityBadgeForName(name) ?? 'HD';
  }

  Color _qualityColor(String quality) {
    // Ordered most-capable-first, indexed by tier — the list's ORDER is the
    // contract, so this switch maps position, not hue.
    final tiers = AppThemeScope.of(context).stremioTv.qualityTier;
    switch (quality) {
      case '4K':
        return tiers[0];
      case '1080p':
        return tiers[1];
      case '720p':
        return tiers[2];
      case '480p':
        return tiers[3];
      default:
        return tiers[4];
    }
  }

  Future<void> _onSourceTap(Torrent source) async {
    if (_resolvingIndex != null) return;
    final originalIndex = widget.sources.indexOf(source);
    setState(() {
      _resolvingIndex = originalIndex;
      _failedIndex = null;
    });

    try {
      final url = await widget.resolver(source);
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        // Validate direct URLs with HEAD check (size >= 50MB)
        if (source.isDirectStream) {
          final valid = await widget.validateDirectUrl(url);
          if (!mounted) return;
          if (!valid) {
            setState(() {
              _resolvingIndex = null;
              _failedIndex = originalIndex;
            });
            return;
          }
        }
        Navigator.of(context).pop(
          StremioTvResolvedSourceChoice(url: url, sourceIndex: originalIndex),
        );
      } else {
        setState(() {
          _resolvingIndex = null;
          _failedIndex = originalIndex;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolvingIndex = null;
        _failedIndex = originalIndex;
      });
    }
  }

  Widget _buildTab(
    String label,
    int count,
    int tabIndex, {
    FocusNode? focusNode,
  }) {
    final isActive = _activeTab == tabIndex;
    return StremioTvSourcePickerTab(
      focusNode: focusNode,
      label: '$label ($count)',
      isActive: isActive,
      onTap: () {
        setState(() => _activeTab = tabIndex);
        // Re-focus first item in the new tab's list
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _firstItemFocusNode.requestFocus();
        });
      },
      onDownPress: () => _firstItemFocusNode.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final filtered = _filteredSources;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF101016),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: app.core.tx.withAlpha(0x3D),
              borderRadius: app.shape.br(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFFB74D),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Auto-play failed — select a source',
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                _buildTab(
                  'All',
                  widget.sources.length,
                  0,
                  focusNode: _firstTabFocusNode,
                ),
                const SizedBox(width: 8),
                if (_directSources.isNotEmpty) ...[
                  _buildTab('Direct', _directSources.length, 1),
                  const SizedBox(width: 8),
                ],
                if (_torrentSources.isNotEmpty)
                  _buildTab('Torrent', _torrentSources.length, 2),
              ],
            ),
          ),
          Divider(color: app.core.tx.withAlpha(0x1F), height: 1),
          // Source list
          Flexible(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No sources in this category',
                        style: TextStyle(
                          color: app.core.tx.withAlpha(0x62),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final source = filtered[i];
                      final quality = _parseQuality(source.displayTitle);
                      final qColor = _qualityColor(quality);
                      final originalIndex = widget.sources.indexOf(source);
                      final isResolving = _resolvingIndex == originalIndex;
                      final size = source.sizeBytes > 0
                          ? Formatters.formatFileSize(source.sizeBytes)
                          : null;
                      final isDirect = source.isDirectStream;

                      final isFailed = _failedIndex == originalIndex;

                      return StremioTvSourcePickerItem(
                        focusNode: i == 0 ? _firstItemFocusNode : null,
                        isFirst: i == 0,
                        onUpToTabs: () => _firstTabFocusNode.requestFocus(),
                        quality: quality,
                        qualityColor: qColor,
                        title: source.displayTitle,
                        meta: [
                          if (isDirect) 'Direct' else 'Torrent',
                          if (size != null) size,
                          if (!isDirect && source.seeders > 0)
                            '${source.seeders} seeders',
                          if (source.source.isNotEmpty) source.source,
                        ].join(' · '),
                        isResolving: isResolving,
                        isFailed: isFailed,
                        onTap: isResolving ? null : () => _onSourceTap(source),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

typedef StremioTvManualSourcePickerSheet = _ManualSourcePickerSheet;
