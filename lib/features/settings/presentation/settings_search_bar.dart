import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Tappable search affordance on the phone/desktop settings root. Looks like a
/// search field but opens the dedicated [SettingsSearchPage] (which owns the
/// live field) so the root layout stays a cheap StatelessWidget.
class SettingsSearchBar extends StatefulWidget {
  final VoidCallback onTap;
  const SettingsSearchBar({super.key, required this.onTap});

  @override
  State<SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<SettingsSearchBar> {
  final FocusNode _node = FocusNode(debugLabel: 'settingsSearchBar');
  bool _hovered = false;

  /// Live, never cached — see the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final bool lit = _focused || _hovered;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        focusNode: _node,
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        onFocusChange: (_) => setState(() {}),
        onHover: (h) => setState(() => _hovered = h),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: lit ? t.panel2 : t.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? t.accent : t.line,
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 20,
                color: lit ? t.accent2 : t.dim,
              ),
              const SizedBox(width: 12),
              Text(
                'Search settings',
                style: TextStyle(fontSize: 13.5, color: t.dim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
