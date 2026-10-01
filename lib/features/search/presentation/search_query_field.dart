import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/text_field_suggestions.dart';
import '../../../widgets/tv_text_field.dart';
import '../models/search_mode.dart';

/// Query editing and keyboard presentation. Controllers and focus nodes are
/// borrowed from the route; query execution and navigation remain callbacks.
class SearchQueryField extends StatelessWidget {
  const SearchQueryField({
    super.key,
    required this.tv,
    required this.dedicatedSearch,
    required this.mode,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onFocusMode,
    required this.onFocusContent,
    required this.onFocusSidebar,
    this.suggestions,
  });

  final bool tv;
  final bool dedicatedSearch;
  final SearchMode mode;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onFocusMode;
  final VoidCallback onFocusContent;
  final VoidCallback onFocusSidebar;
  final ValueListenable<List<TextFieldSuggestion>>? suggestions;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final compactSearch = tv && dedicatedSearch;
    final radius = app.shape.br(compactSearch ? 12 : 26);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          // Pre-search Sources button (keyword or catalog empty state) is the
          // only content, and _focusContent keeps focus on the field there —
          // so target it directly, otherwise Down is a dead end.
          onFocusContent();
          return KeyEventResult.handled;
        }
        // Arrow-up jumps to the Catalog/Keyword toggle (top-right). Works on
        // both TV (DPAD) and desktop (keyboard) — up is safe to intercept, a
        // single-line field doesn't use it for the cursor and nothing sits
        // above the search field.
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          onFocusMode();
          return KeyEventResult.handled;
        }
        // Arrow-right reaches the toggle too — its natural spatial direction —
        // but only once the caret is at the very end of the text, so right
        // still moves the cursor through what you've typed first. A blank field
        // (or caret already at the end) jumps to the toggle immediately.
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final text = controller.text;
          final sel = controller.selection;
          final atEnd =
              text.isEmpty ||
              sel.baseOffset < 0 ||
              (sel.isCollapsed && sel.baseOffset >= text.length);
          if (atEnd) {
            onFocusMode();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored; // let the caret move right first
        }
        // Arrow-left is handled via a Shortcuts override on the field (below),
        // not here — an EditableText consumes left-at-start for the caret before
        // an ancestor Focus.onKeyEvent can see it.
        return KeyEventResult.ignored;
      },
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final hasText = value.text.isNotEmpty;
          // TvTextField: on TV (Debrify keyboard on) this is a shell — DPAD
          // landing draws the focus ring but never opens a keyboard; OK
          // starts editing with the in-app DPAD keyboard. Off TV / opted out
          // it renders the same plain TextField as before.
          final field = TvTextField(
            controller: controller,
            suggestions: suggestions,
            suggestionsLabel: 'Titles from TMDB',
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            // Apple's fullscreen keyboard emits only an ambiguous end-editing
            // signal for both Search and Back. On this dedicated search field,
            // executing the typed query is preferable to silently revealing a
            // suggestion strip and leaving Catalog search unsubmitted.
            submitOnTvosEndEditing: dedicatedSearch,
            textInputAction: TextInputAction.search,
            textAlign: compactSearch ? TextAlign.start : TextAlign.center,
            style: TextStyle(color: scheme.onSurface, fontSize: tv ? 16 : 15),
            // Shell-mode LEFT: no caret exists at the shell, so left always
            // escapes to the sidebar (the LEFT-only sidebar policy). While
            // EDITING, left moves the keyboard highlight instead — TvTextField
            // consumes it internally. The Shortcuts wrapper below still covers
            // the opted-out plain-TextField path.
            onLeftArrow: tv ? onFocusSidebar : null,
            // Explicit up/down so BOTH keyboard modes use the curated targets
            // (mirrors the ancestor Focus handler below, which otherwise only
            // sees keys the field lets bubble).
            onUpArrow: tv ? onFocusMode : null,
            onDownArrow: tv ? onFocusContent : null,
            decoration: InputDecoration(
              hintText: switch (mode) {
                SearchMode.catalog => 'Search or paste link',
                SearchMode.keyword => 'Search torrents by keyword',
                SearchMode.lists => 'Search MDBList lists',
              },
              hintStyle: TextStyle(color: app.fade(app.core.tx, 0.32)),
              suffixIcon: hasText
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: app.fade(app.core.tx, 0.55),
                      ),
                      onPressed: onClear,
                    )
                  : Icon(
                      Icons.search_rounded,
                      color: app.fade(app.core.tx, 0.4),
                    ),
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(
                  color: app.fade(app.home.chromeAccent, 0.6),
                ),
              ),
              filled: true,
              fillColor: app.fade(app.core.tx, 0.06),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: compactSearch ? 10 : (tv ? 16 : 14),
              ),
            ),
          );
          // TV: wrap the field so left-arrow on an EMPTY field escapes to the
          // sidebar (the intuitive direction) — the text editor would otherwise
          // silently eat it. The wrapper is ALWAYS present (a stable subtree root,
          // so typing/clearing never tears the EditableText down); the action
          // disables itself once there's text, so the framework's own caret and
          // selection handling takes over untouched.
          if (!tv) return field;
          return Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowLeft):
                  _SearchLeftIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _SearchLeftIntent: _EmptyFieldLeftAction(
                  controller,
                  onFocusSidebar,
                ),
              },
              child: field,
            ),
          );
        },
      ),
    );
  }
}

/// Intent for a left-arrow on the search field, remapped (via a [Shortcuts]
/// override closer than the default text-editing shortcuts) so an empty field
/// escapes to the sidebar instead of the EditableText silently eating the key.
class _SearchLeftIntent extends Intent {
  const _SearchLeftIntent();
}

/// Escapes an *empty* TV search field to the sidebar on left-arrow. It disables
/// itself the moment there's text, so [Shortcuts] falls through to the default
/// caret/selection handling — meaning the wrapper can stay mounted at all times
/// (a stable subtree root) without the action ever swallowing a real caret move.
class _EmptyFieldLeftAction extends Action<_SearchLeftIntent> {
  _EmptyFieldLeftAction(this._controller, this._onEscape);

  final TextEditingController _controller;
  final VoidCallback _onEscape;

  @override
  bool isEnabled(_SearchLeftIntent intent) => _controller.text.isEmpty;

  @override
  Object? invoke(_SearchLeftIntent intent) {
    _onEscape();
    return null;
  }
}

/// Suggestion actions capture the displayed title/query. Lookup ownership and
/// stale-navigation guards remain with the host.
List<TextFieldSuggestion> buildSearchTitleSuggestions(
  List<StremioMeta> items, {
  required String query,
  required ValueChanged<StremioMeta> onOpen,
  required ValueChanged<String> onSubmit,
}) => [
  for (final item in items)
    TextFieldSuggestion(
      id: '${item.type}:${item.id}',
      title: item.name,
      subtitle: [
        item.type == 'series' ? 'TV show' : 'Movie',
        if (item.year?.isNotEmpty == true) item.year!,
      ].join(' · '),
      year: item.year,
      onSelected: () => onOpen(item),
    ),
  if (items.isNotEmpty)
    TextFieldSuggestion(
      id: 'search-query',
      title: 'Search for “$query”',
      subtitle: 'Search catalogs',
      onSelected: () => onSubmit(query),
    ),
];
