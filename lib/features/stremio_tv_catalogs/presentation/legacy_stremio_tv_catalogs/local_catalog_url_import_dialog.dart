import 'dart:async';

import 'package:debrify/features/stremio_tv_catalogs/data/local_catalog_importer.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ─── Import from URL dialog ─────────────────────────────────────────────────

/// Back on a (non-editing) shell field hops to the dialog's Cancel button —
/// matching the deleted per-field handlers — instead of bubbling on and
/// popping the dialog with the user's typed input still in it. While EDITING,
/// TvTextField consumes Back itself, so this only sees the shell-focused case.
Widget _backHopsTo(FocusNode cancelNode, Widget child) {
  return Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.browserBack) {
        cancelNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}

const lcBackHop = _backHopsTo;

class _ImportUrlDialog extends StatefulWidget {
  const _ImportUrlDialog();

  @override
  State<_ImportUrlDialog> createState() => _ImportUrlDialogState();
}

typedef LcUrlDialog = _ImportUrlDialog;

class _ImportUrlDialogState extends State<_ImportUrlDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode(debugLabel: 'stremio-import-url-name');
  final _urlFocusNode = FocusNode(debugLabel: 'stremio-import-url-url');
  final _cancelFocusNode = FocusNode(debugLabel: 'stremio-import-url-cancel');
  final _importFocusNode = FocusNode(debugLabel: 'stremio-import-url-import');
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Name/URL field DPAD exits live on the TvTextFields (onUp/DownArrow).
    _cancelFocusNode.onKeyEvent = _handleCancelButtonKey;
    _importFocusNode.onKeyEvent = _handleImportButtonKey;
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    _urlFocusNode.dispose();
    _cancelFocusNode.dispose();
    _importFocusNode.dispose();
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  KeyEventResult _handleCancelButtonKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _urlFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _importFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _importFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleImportButtonKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _urlFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _cancelFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _cancelFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      if (!_loading) {
        _import();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _import() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Enter a URL');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      setState(() => _error = 'Invalid URL');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (resp.statusCode != 200) {
        setState(() {
          _error = 'HTTP ${resp.statusCode}';
          _loading = false;
        });
        return;
      }

      final err = await LocalCatalogImporter.import(
        resp.body,
        catalogName: _nameController.text,
      );
      if (!mounted) return;

      if (err != null) {
        setState(() {
          _error = err;
          _loading = false;
        });
        return;
      }

      Navigator.of(context).pop(true);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Request timed out';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return AlertDialog(
      title: const Text('Import from URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _backHopsTo(
            _cancelFocusNode,
            TvTextField(
              controller: _nameController,
              focusNode: _nameFocusNode,
              onUpArrow: () => _cancelFocusNode.requestFocus(),
              onDownArrow: () => _urlFocusNode.requestFocus(),
              accent: app.youtube.focus,
              keyboardGround: app.youtube.keyboardPanel,
              keyboardInk: app.core.tx,
              keyboardInkOnAccent: app.inkOn(app.youtube.focus),
              decoration: InputDecoration(
                hintText: 'Catalog name (required for Trakt lists)',
                border: OutlineInputBorder(borderRadius: app.shape.br(12)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _backHopsTo(
            _cancelFocusNode,
            TvTextField(
              controller: _urlController,
              focusNode: _urlFocusNode,
              onUpArrow: () => _nameFocusNode.requestFocus(),
              onDownArrow: () => _importFocusNode.requestFocus(),
              accent: app.youtube.focus,
              keyboardGround: app.youtube.keyboardPanel,
              keyboardInk: app.core.tx,
              keyboardInkOnAccent: app.inkOn(app.youtube.focus),
              decoration: InputDecoration(
                hintText: 'https://example.com/catalog.json',
                border: OutlineInputBorder(borderRadius: app.shape.br(12)),
                errorText: _error,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              autofocus: true,
              onSubmitted: (_) {
                if (!_loading) _import();
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          focusNode: _cancelFocusNode,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          focusNode: _importFocusNode,
          onPressed: _loading ? null : _import,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Import'),
        ),
      ],
    );
  }
}
