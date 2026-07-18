import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/torrent_filter_state.dart';
import '../../services/storage_service.dart';
import '../../services/analytics_service.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import 'widgets/settings_widgets.dart';

class FilterSettingsPage extends StatefulWidget {
  const FilterSettingsPage({super.key});

  @override
  State<FilterSettingsPage> createState() => _FilterSettingsPageState();
}

class _FilterSettingsPageState extends State<FilterSettingsPage> {
  bool _loading = true;
  bool _quickPlayHonors = true;
  final Set<QualityTier> _selectedQualities = {};
  final Set<RipSourceCategory> _selectedSources = {};
  final Set<AudioLanguage> _selectedLanguages = {};

  // Focus nodes for D-pad navigation
  final List<FocusNode> _qualityFocusNodes = [];
  final List<FocusNode> _sourceFocusNodes = [];
  final List<FocusNode> _languageFocusNodes = [];
  final FocusNode _clearAllFocusNode = FocusNode(debugLabel: 'clear-all');
  bool _clearAllFocused = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('filter_settings');
    _initFocusNodes();
    _clearAllFocusNode.addListener(_onClearAllFocusChange);
    _loadSettings();
  }

  void _onClearAllFocusChange() {
    if (mounted) {
      setState(() {
        _clearAllFocused = _clearAllFocusNode.hasFocus;
      });
    }
  }

  void _initFocusNodes() {
    // Quality focus nodes
    for (int i = 0; i < QualityTier.values.length; i++) {
      _qualityFocusNodes.add(FocusNode(debugLabel: 'quality-$i'));
    }
    // Source focus nodes
    for (int i = 0; i < RipSourceCategory.values.length; i++) {
      _sourceFocusNodes.add(FocusNode(debugLabel: 'source-$i'));
    }
    // Language focus nodes
    for (int i = 0; i < _languageOptions.length; i++) {
      _languageFocusNodes.add(FocusNode(debugLabel: 'language-$i'));
    }
  }

  @override
  void dispose() {
    _clearAllFocusNode.removeListener(_onClearAllFocusChange);
    _clearAllFocusNode.dispose();
    for (final node in _qualityFocusNodes) {
      node.dispose();
    }
    for (final node in _sourceFocusNodes) {
      node.dispose();
    }
    for (final node in _languageFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final qualities = await StorageService.getDefaultFilterQualities();
      final sources = await StorageService.getDefaultFilterRipSources();
      final languages = await StorageService.getDefaultFilterLanguages();
      final quickPlayHonors = await StorageService.getQuickPlayHonorsFilters();

      setState(() {
        _quickPlayHonors = quickPlayHonors;
        // Convert stored strings back to enums
        for (final q in qualities) {
          final tier = QualityTier.values.where((e) => e.name == q).firstOrNull;
          if (tier != null) _selectedQualities.add(tier);
        }
        for (final s in sources) {
          final source = RipSourceCategory.values
              .where((e) => e.name == s)
              .firstOrNull;
          if (source != null) _selectedSources.add(source);
        }
        for (final l in languages) {
          final lang = AudioLanguage.values
              .where((e) => e.name == l)
              .firstOrNull;
          if (lang != null) _selectedLanguages.add(lang);
        }
        _loading = false;
      });
      // TV entry focus: land DPAD users on the first chip instead of nothing.
      if (PlatformUtil.isAndroidTvCached) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Don't yank focus if it already landed on a real node (only the
          // route's FocusScope holds focus while nothing is focused yet).
          final primary = FocusManager.instance.primaryFocus;
          if (primary != null && primary is! FocusScopeNode) return;
          if (_qualityFocusNodes.isNotEmpty) {
            _qualityFocusNodes.first.requestFocus();
          }
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _setQuickPlayHonors(bool value) async {
    setState(() => _quickPlayHonors = value);
    await StorageService.setQuickPlayHonorsFilters(value);
  }

  Future<void> _toggleQuality(QualityTier tier) async {
    setState(() {
      if (!_selectedQualities.add(tier)) {
        _selectedQualities.remove(tier);
      }
    });
    await _saveQualities();
  }

  Future<void> _toggleSource(RipSourceCategory source) async {
    setState(() {
      if (!_selectedSources.add(source)) {
        _selectedSources.remove(source);
      }
    });
    await _saveSources();
  }

  Future<void> _toggleLanguage(AudioLanguage language) async {
    setState(() {
      if (!_selectedLanguages.add(language)) {
        _selectedLanguages.remove(language);
      }
    });
    await _saveLanguages();
  }

  Future<void> _saveQualities() async {
    await StorageService.setDefaultFilterQualities(
      _selectedQualities.map((e) => e.name).toList(),
    );
  }

  Future<void> _saveSources() async {
    await StorageService.setDefaultFilterRipSources(
      _selectedSources.map((e) => e.name).toList(),
    );
  }

  Future<void> _saveLanguages() async {
    await StorageService.setDefaultFilterLanguages(
      _selectedLanguages.map((e) => e.name).toList(),
    );
  }

  Future<void> _clearAll() async {
    // Clearing unmounts the AppBar "Clear All" button (it's only built while
    // filters exist) — if it held DPAD/keyboard focus, hand focus to the
    // first chip so the user isn't stranded on nothing.
    final reseedFocus = _clearAllFocusNode.hasFocus;
    setState(() {
      _selectedQualities.clear();
      _selectedSources.clear();
      _selectedLanguages.clear();
    });
    if (reseedFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _qualityFocusNodes.isNotEmpty) {
          _qualityFocusNodes.first.requestFocus();
        }
      });
    }
    await Future.wait([_saveQualities(), _saveSources(), _saveLanguages()]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Filter Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasFilters =
        _selectedQualities.isNotEmpty ||
        _selectedSources.isNotEmpty ||
        _selectedLanguages.isNotEmpty;

    return SettingsPageScaffold(
      title: 'Filter Settings',
      actions: [
        if (hasFilters)
          Focus(
            focusNode: _clearAllFocusNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (isActivateKey(event.logicalKey) ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                _clearAll();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                border: _clearAllFocused
                    ? Border.all(color: kSettingsAccent, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(8),
              ),
              // ExcludeFocus: the outer Focus node handles DPAD; without it
              // the button's own node makes this two traversal stops on TV.
              child: ExcludeFocus(
                child: TextButton(
                  onPressed: _clearAll,
                  child: const Text('Clear All'),
                ),
              ),
            ),
          ),
      ],
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SettingsPageHeader(
                    icon: Icons.filter_list_rounded,
                    title: 'Default Filters',
                    subtitle: 'Set default filters for torrent search results',
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    context,
                    title: 'Quality',
                    subtitle: 'Filter by video resolution',
                    children: _buildQualityChips(),
                  ),
                  const SizedBox(height: 20),
                  _buildSection(
                    context,
                    title: 'Rip / Source',
                    subtitle: 'Filter by release type',
                    children: _buildSourceChips(),
                  ),
                  const SizedBox(height: 20),
                  _buildSection(
                    context,
                    title: 'Language',
                    subtitle: 'Filter by audio language',
                    children: _buildLanguageChips(),
                  ),
                  const SizedBox(height: 20),
                  SettingsSection(
                    title: '',
                    children: [
                      SettingsToggleTile(
                        icon: Icons.bolt_rounded,
                        title: 'Apply filters to Quick Play',
                        subtitle: 'Play prefers sources matching these filters',
                        value: _quickPlayHonors,
                        onChanged: _setQuickPlayHonors,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const SettingsInfoBanner(
                    text:
                        'These filters will be applied by default when searching for torrents. You can still change filters in the search page.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSettingsPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSettingsLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: kSettingsDim)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }

  List<Widget> _buildQualityChips() {
    return _qualityOptions.asMap().entries.map((entry) {
      final index = entry.key;
      final option = entry.value;
      return _DpadFilterChip(
        focusNode: _qualityFocusNodes[index],
        label: option.title,
        subtitle: option.subtitle,
        selected: _selectedQualities.contains(option.value),
        onSelected: () => _toggleQuality(option.value),
      );
    }).toList();
  }

  List<Widget> _buildSourceChips() {
    return _sourceOptions.asMap().entries.map((entry) {
      final index = entry.key;
      final option = entry.value;
      return _DpadFilterChip(
        focusNode: _sourceFocusNodes[index],
        label: option.title,
        subtitle: option.subtitle,
        selected: _selectedSources.contains(option.value),
        onSelected: () => _toggleSource(option.value),
      );
    }).toList();
  }

  List<Widget> _buildLanguageChips() {
    return _languageOptions.asMap().entries.map((entry) {
      final index = entry.key;
      final option = entry.value;
      return _DpadFilterChip(
        focusNode: _languageFocusNodes[index],
        label: option.title,
        selected: _selectedLanguages.contains(option.value),
        onSelected: () => _toggleLanguage(option.value),
      );
    }).toList();
  }
}

/// D-pad compatible FilterChip with focus handling
class _DpadFilterChip extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onSelected;

  const _DpadFilterChip({
    required this.focusNode,
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_DpadFilterChip> createState() => _DpadFilterChipState();
}

class _DpadFilterChipState extends State<_DpadFilterChip> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (isActivateKey(event.logicalKey) ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onSelected();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          color: _isFocused ? kSettingsPanel2 : null,
          border: _isFocused
              ? Border.all(color: kSettingsAccent, width: 2)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        // ExcludeFocus: FilterChip is itself focusable, which would make each
        // chip TWO DPAD stops (outer Focus + chip). The outer node owns focus
        // and activation; the chip keeps touch/mouse taps.
        child: ExcludeFocus(
          child: FilterChip(
            label: widget.subtitle != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.label),
                      Text(
                        widget.subtitle!,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  )
                : Text(widget.label),
            selected: widget.selected,
            onSelected: (_) => widget.onSelected(),
          ),
        ),
      ),
    );
  }
}

// Option classes
class _QualityOption {
  final QualityTier value;
  final String title;
  final String subtitle;
  const _QualityOption(this.value, this.title, this.subtitle);
}

class _SourceOption {
  final RipSourceCategory value;
  final String title;
  final String subtitle;
  const _SourceOption(this.value, this.title, this.subtitle);
}

class _LanguageOption {
  final AudioLanguage value;
  final String title;
  const _LanguageOption(this.value, this.title);
}

// Options lists
const _qualityOptions = <_QualityOption>[
  _QualityOption(QualityTier.ultraHd, '4K / 2160p', 'UHD, 2160p, 4K'),
  _QualityOption(QualityTier.fullHd, '1080p', 'Full HD, BluRay, WEB-DL'),
  _QualityOption(QualityTier.hd, '720p', 'HD, WEBRip, HDTV'),
  _QualityOption(QualityTier.sd, '480p & Below', 'SD, CAM, older rips'),
];

const _sourceOptions = <_SourceOption>[
  _SourceOption(
    RipSourceCategory.web,
    'WEB / WEB-DL',
    'Streaming captures, WEBRip',
  ),
  _SourceOption(
    RipSourceCategory.bluRay,
    'BluRay / BRRip',
    'BDRip, BluRay remuxes',
  ),
  _SourceOption(
    RipSourceCategory.hdrip,
    'HDRip / HDTV',
    'HDRip, HDTV, HC sources',
  ),
  _SourceOption(RipSourceCategory.dvdrip, 'DVDRip', 'DVD sources, SD rips'),
  _SourceOption(RipSourceCategory.cam, 'CAM / TS', 'CAM, HDCAM, telesync'),
  _SourceOption(RipSourceCategory.other, 'Other', 'Unclassified / scene'),
];

const _languageOptions = <_LanguageOption>[
  _LanguageOption(AudioLanguage.english, 'English'),
  _LanguageOption(AudioLanguage.hindi, 'Hindi'),
  _LanguageOption(AudioLanguage.spanish, 'Spanish'),
  _LanguageOption(AudioLanguage.french, 'French'),
  _LanguageOption(AudioLanguage.german, 'German'),
  _LanguageOption(AudioLanguage.russian, 'Russian'),
  _LanguageOption(AudioLanguage.chinese, 'Chinese'),
  _LanguageOption(AudioLanguage.japanese, 'Japanese'),
  _LanguageOption(AudioLanguage.korean, 'Korean'),
  _LanguageOption(AudioLanguage.italian, 'Italian'),
  _LanguageOption(AudioLanguage.portuguese, 'Portuguese'),
  _LanguageOption(AudioLanguage.arabic, 'Arabic'),
  _LanguageOption(AudioLanguage.multiAudio, 'Multi-Audio'),
];
