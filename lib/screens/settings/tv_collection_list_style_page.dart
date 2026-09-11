import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/settings_load_error.dart';

class TvCollectionListStylePage extends StatefulWidget {
  const TvCollectionListStylePage({super.key});
  @override
  State<TvCollectionListStylePage> createState() =>
      _TvCollectionListStylePageState();
}

class _TvCollectionListStylePageState extends State<TvCollectionListStylePage> {
  String? _style;
  final _nodes = {
    for (final style in ['grid', 'gallery', 'filmstrip', 'journal'])
      style: FocusNode(),
  };
  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  bool _failed = false, _saving = false;
  static const choices = {
    'grid': ('Grid', 'The existing poster grid'),
    'gallery': ('Gallery', 'A fixed title preview beside a wall of posters'),
    'filmstrip': (
      'Filmstrip',
      'Browse a vertical filmstrip beside a large hero · default',
    ),
    'journal': (
      'Journal',
      'A numbered title index with artwork on a dark background',
    ),
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final value = await StorageService.getTvCollectionListStyle();
      if (mounted) {
        setState(() => _style = value);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nodes[_style]?.requestFocus();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _select(String value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await StorageService.setTvCollectionListStyle(value);
      if (mounted) setState(() => _style = value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save this style. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nodes[value]?.requestFocus();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: 'Collection list style',
    body: _failed
        ? SettingsLoadError(onRetry: _load)
        : _style == null
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SettingsPageHeader(
                      icon: Icons.view_carousel_outlined,
                      title: 'Collection list style',
                      subtitle:
                          'How movies and series appear inside collection lists on this TV',
                    ),
                    const SizedBox(height: 24),
                    SettingsSection(
                      title: 'Style',
                      children: [
                        for (final entry in choices.entries)
                          SettingsTile(
                            focusNode: _nodes[entry.key],
                            icon: entry.key == _style
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            title: entry.value.$1,
                            subtitle: entry.value.$2,
                            enabled: !_saving,
                            onTap: () => _select(entry.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Applies when you next open a collection list. Other devices keep their own layout.',
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
