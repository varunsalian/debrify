import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';
import '../tv_text_field.dart';

/// The root-level "search your torrents" bar shared by the TorBox and
/// Real-Debrid cloud files screens (G4-5). Moved verbatim from the
/// byte-identical `_buildTorrentSearchBar` each host carried.
///
/// Stateless on purpose: `hasText` is read at build time and the hosts do not
/// call `setState` from the field's `onChanged`, so the clear button appears
/// on the next rebuild the host happens to do. That is the origin behaviour.
class CloudTorrentSearchBar extends StatelessWidget {
  const CloudTorrentSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.clearFocusNode,
    required this.onCancelPendingSubmit,
    required this.onSubmit,
    required this.onQueryCleared,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode clearFocusNode;

  /// `_torrentSearchSubmitFocus.cancel()` on the host.
  final VoidCallback onCancelPendingSubmit;

  /// `_submitTorrentSearch()` on the host.
  final VoidCallback onSubmit;

  /// `setState(() => _torrentSearchQuery = '')` on the host.
  final VoidCallback onQueryCleared;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final hasText = controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              onChanged: (_) => onCancelPendingSubmit(),
              onSubmitted: (_) => onSubmit(),
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search your torrents...',
                hintStyle: TextStyle(color: app.fade(app.core.tx, 0.3)),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: app.fade(app.core.tx, 0.4),
                  size: 20,
                ),
                filled: true,
                fillColor: app.fade(app.core.tx, 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: app.shape.br(12),
                  borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: app.shape.br(12),
                  borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: app.shape.br(12),
                  borderSide: BorderSide(color: app.cloud.accent),
                ),
              ),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: clearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
                    onCancelPendingSubmit();
                    controller.clear();
                    onQueryCleared();
                    focusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    focusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return IconButton(
                      onPressed: () {
                        onCancelPendingSubmit();
                        controller.clear();
                        onQueryCleared();
                        focusNode.requestFocus();
                      },
                      icon: Icon(
                        Icons.clear_rounded,
                        color: isFocused
                            ? app.core.tx
                            : app.fade(app.core.tx, 0.4),
                        size: 18,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
