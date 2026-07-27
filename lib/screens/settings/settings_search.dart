import 'package:flutter/material.dart';

import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';

/// One searchable settings destination.
///
/// An entry is either a navigable action ([onTap] — opens a subpage, a
/// connection page, or a link) or an inline toggle ([toggleValue] +
/// [onToggle], rendered as a live switch in the results). The [category]
/// groups it under a header, and [keywords] widen the match so conceptual
/// searches ("sd card", "4k", "scrobble", "epg") land on the right row even
/// when those words aren't in the visible title/subtitle.
class SettingsSearchEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String category;
  final List<String> keywords;
  final bool destructive;

  /// Navigable action. Mutually exclusive with the toggle fields.
  final Future<void> Function()? onTap;

  /// Reads the toggle's current value at render time (so the switch reflects
  /// live state after a flip). Non-null iff this is a toggle entry.
  final bool Function()? toggleValue;
  final ValueChanged<bool>? onToggle;

  const SettingsSearchEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.category,
    this.keywords = const [],
    this.destructive = false,
    this.onTap,
    this.toggleValue,
    this.onToggle,
  }) : assert(
         onTap != null || onToggle != null,
         'A search entry must be navigable or a toggle',
       ),
       // A toggle entry is rendered via toggleValue!() — require it so a
       // half-built toggle can't null-throw at render.
       assert(
         onToggle == null || toggleValue != null,
         'A toggle entry must supply toggleValue',
       );

  bool get isToggle => onToggle != null;

  /// Lowercase haystack of everything a query can match against.
  String get _haystack =>
      '$title $subtitle $category ${keywords.join(' ')}'.toLowerCase();

  /// AND semantics: every whitespace-separated term must appear somewhere in
  /// the haystack, so "download sd" narrows rather than widens.
  bool matches(List<String> terms) {
    if (terms.isEmpty) return true;
    final hay = _haystack;
    return terms.every(hay.contains);
  }
}

/// Full-screen settings search: a field on top, live-filtered results below,
/// grouped by category. Reuses [SettingsTile] / [SettingsToggleTile] so a
/// result looks and behaves exactly like the same row on its home screen —
/// tapping a navigable result opens its page; a toggle result flips in place.
///
/// TV: the field is a [TvTextField] shell (OK opens the Debrify keyboard).
/// DOWN from the field drops into the first result; from there the framework's
/// directional traversal walks the list (and scrolls each focused row into
/// view). Phone: autofocus raises the IME and results filter as you type.
class SettingsSearchPage extends StatefulWidget {
  final List<SettingsSearchEntry> entries;

  const SettingsSearchPage({super.key, required this.entries});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldNode = FocusNode(debugLabel: 'settings-search-field');

  /// Attached to the first result row so the field's DOWN arrow can drop onto
  /// it deterministically on TV (a bare directional hop can miss on the first
  /// press before the list has laid out).
  final FocusNode _firstResultNode = FocusNode(
    debugLabel: 'settings-search-first-result',
  );

  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _fieldNode.dispose();
    _firstResultNode.dispose();
    super.dispose();
  }

  List<String> get _terms =>
      _query.trim().toLowerCase().split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();

  List<SettingsSearchEntry> get _filtered {
    final terms = _terms;
    return widget.entries.where((e) => e.matches(terms)).toList();
  }

  void _focusFirstResult() {
    // A FocusNode's context is NOT cleared when its row unmounts (e.g. the
    // query filtered results to empty), so `!= null` can be a stale true —
    // gate on `context?.mounted`, the same guard the TV pane uses.
    if (_firstResultNode.context?.mounted ?? false) {
      _firstResultNode.requestFocus();
    }
  }

  Future<void> _activate(SettingsSearchEntry e) async {
    // Close search first so BACK from the opened page returns to the settings
    // root, not back into a stale results list.
    Navigator.of(context).pop();
    await e.onTap?.call();
  }

  void _toggle(SettingsSearchEntry e, bool value) {
    e.onToggle?.call(value);
    // The parent handler flips its field synchronously before persisting, so a
    // rebuild re-reads the new value through [toggleValue].
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return SettingsPageScaffold(
      title: 'Search Settings',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TvTextField(
              controller: _controller,
              focusNode: _fieldNode,
              autofocus: true,
              hintText: 'Search settings…',
              textInputAction: TextInputAction.search,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  // ExcludeFocus so the clear button never becomes a DPAD stop
                  // on TV; taps still work on phone.
                  : ExcludeFocus(
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Clear',
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
                    ),
              onChanged: (v) => setState(() => _query = v),
              onDownArrow: _focusFirstResult,
              onSubmitted: (_) => _focusFirstResult(),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyResults(query: _query.trim())
                : _buildResults(filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(List<SettingsSearchEntry> filtered) {
    // Flatten into a single scroll list of category-label + row widgets, so
    // directional traversal walks straight down without pane boundaries. The
    // first *row* (not label) gets [_firstResultNode].
    final children = <Widget>[];
    String? lastCategory;
    bool firstRowAssigned = false;

    for (final e in filtered) {
      if (e.category != lastCategory) {
        children.add(
          Padding(
            padding: EdgeInsets.only(
              left: 2,
              right: 2,
              top: lastCategory == null ? 4 : 20,
              bottom: 4,
            ),
            child: SettingsSectionLabel(e.category),
          ),
        );
        lastCategory = e.category;
      }

      final FocusNode? node = firstRowAssigned ? null : _firstResultNode;
      firstRowAssigned = true;

      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: e.isToggle
              ? SettingsToggleTile(
                  icon: e.icon,
                  title: e.title,
                  subtitle: e.subtitle,
                  value: e.toggleValue!(),
                  onChanged: (v) => _toggle(e, v),
                  focusNode: node,
                )
              : SettingsTile(
                  icon: e.icon,
                  title: e.title,
                  subtitle: e.subtitle,
                  destructive: e.destructive,
                  onTap: () => _activate(e),
                  focusNode: node,
                ),
        ),
      );
    }

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: children,
      ),
    );
  }
}

/// Shown only when a non-empty query matches nothing — a blank query matches
/// every entry (so the full index is browsable on open) and never reaches here.
class _EmptyResults extends StatelessWidget {
  final String query;
  const _EmptyResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: kSettingsDim2),
            const SizedBox(height: 14),
            Text(
              'No settings match "$query"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: kSettingsDim),
            ),
          ],
        ),
      ),
    );
  }
}
