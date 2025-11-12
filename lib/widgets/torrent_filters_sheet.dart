import 'package:flutter/material.dart';

import '../models/torrent_filter_state.dart';

class TorrentFiltersSheet extends StatefulWidget {
  final TorrentFilterState initialState;

  const TorrentFiltersSheet({super.key, required this.initialState});

  @override
  State<TorrentFiltersSheet> createState() => _TorrentFiltersSheetState();
}

class _TorrentFiltersSheetState extends State<TorrentFiltersSheet> {
  late Set<QualityTier> _selectedQualities;
  late Set<RipSourceCategory> _selectedSources;
  final FocusNode _clearButtonFocusNode = FocusNode();
  final FocusNode _closeButtonFocusNode = FocusNode();
  final FocusNode _applyButtonFocusNode = FocusNode();
  final List<FocusNode> _qualityChipFocusNodes = [];
  final List<FocusNode> _ripChipFocusNodes = [];

  @override
  void initState() {
    super.initState();
    _selectedQualities = widget.initialState.qualities.toSet();
    _selectedSources = widget.initialState.ripSources.toSet();

    // Create focus nodes for quality chips
    for (int i = 0; i < _qualityOptions.length; i++) {
      _qualityChipFocusNodes.add(FocusNode(debugLabel: 'quality-chip-$i'));
    }

    // Create focus nodes for rip source chips
    for (int i = 0; i < _ripOptions.length; i++) {
      _ripChipFocusNodes.add(FocusNode(debugLabel: 'rip-chip-$i'));
    }
  }

  @override
  void dispose() {
    _clearButtonFocusNode.dispose();
    _closeButtonFocusNode.dispose();
    _applyButtonFocusNode.dispose();
    for (final node in _qualityChipFocusNodes) {
      node.dispose();
    }
    for (final node in _ripChipFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _toggleQuality(QualityTier tier) {
    setState(() {
      if (!_selectedQualities.add(tier)) {
        _selectedQualities.remove(tier);
      }
    });
  }

  void _toggleSource(RipSourceCategory source) {
    setState(() {
      if (!_selectedSources.add(source)) {
        _selectedSources.remove(source);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _selectedQualities.clear();
      _selectedSources.clear();
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      TorrentFilterState(
        qualities: _selectedQualities.toSet(),
        ripSources: _selectedSources.toSet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.75,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filter Results',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Focus(
                        focusNode: _clearButtonFocusNode,
                        child: TextButton(
                          onPressed:
                              _selectedQualities.isEmpty &&
                                  _selectedSources.isEmpty
                              ? null
                              : _clearAll,
                          child: const Text('Clear'),
                        ),
                      ),
                      Focus(
                        focusNode: _closeButtonFocusNode,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quality',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _qualityOptions
                            .asMap()
                            .entries
                            .map(
                              (entry) {
                                final index = entry.key;
                                final option = entry.value;
                                return Focus(
                                  focusNode: _qualityChipFocusNodes[index],
                                  child: FilterChip(
                                    label: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(option.title),
                                        Text(
                                          option.subtitle,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    selected: _selectedQualities.contains(
                                      option.value,
                                    ),
                                    onSelected: (_) => _toggleQuality(option.value),
                                  ),
                                );
                              },
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Rip / Source',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _ripOptions
                            .asMap()
                            .entries
                            .map(
                              (entry) {
                                final index = entry.key;
                                final option = entry.value;
                                return Focus(
                                  focusNode: _ripChipFocusNodes[index],
                                  child: FilterChip(
                                    label: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(option.title),
                                        Text(
                                          option.subtitle,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    selected: _selectedSources.contains(
                                      option.value,
                                    ),
                                    onSelected: (_) => _toggleSource(option.value),
                                  ),
                                );
                              },
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: Focus(
                  focusNode: _applyButtonFocusNode,
                  child: ElevatedButton.icon(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Apply Filters'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipOption<T> {
  final T value;
  final String title;
  final String subtitle;

  const _ChipOption(this.value, this.title, this.subtitle);
}

const _qualityOptions = <_ChipOption<QualityTier>>[
  _ChipOption(QualityTier.ultraHd, '4K / 2160p', 'UHD, 2160p, 4K'),
  _ChipOption(QualityTier.fullHd, '1080p', 'Full HD, BluRay, WEB-DL'),
  _ChipOption(QualityTier.hd, '720p', 'HD, WEBRip, HDTV'),
  _ChipOption(QualityTier.sd, '480p & Below', 'SD, CAM, older rips'),
];

const _ripOptions = <_ChipOption<RipSourceCategory>>[
  _ChipOption(
    RipSourceCategory.web,
    'WEB / WEB-DL',
    'Streaming captures, WEBRip',
  ),
  _ChipOption(
    RipSourceCategory.bluRay,
    'BluRay / BRRip',
    'BDRip, BluRay remuxes',
  ),
  _ChipOption(
    RipSourceCategory.hdrip,
    'HDRip / HDTV',
    'HDRip, HDTV, HC sources',
  ),
  _ChipOption(RipSourceCategory.dvdrip, 'DVDRip', 'DVD sources, SD rips'),
  _ChipOption(RipSourceCategory.cam, 'CAM / TS', 'CAM, HDCAM, telesync'),
  _ChipOption(RipSourceCategory.other, 'Other', 'Unclassified / scene'),
];
