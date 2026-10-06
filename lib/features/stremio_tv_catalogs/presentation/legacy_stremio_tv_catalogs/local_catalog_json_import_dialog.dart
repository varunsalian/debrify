import 'package:debrify/features/stremio_tv_catalogs/data/local_catalog_importer.dart';
import 'package:debrify/features/stremio_tv_catalogs/presentation/legacy_stremio_tv_catalogs/local_catalog_url_import_dialog.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Paste JSON dialog ──────────────────────────────────────────────────────

class _ImportJsonDialog extends StatefulWidget {
  const _ImportJsonDialog();

  @override
  State<_ImportJsonDialog> createState() => _ImportJsonDialogState();
}

typedef LcJsonDialog = _ImportJsonDialog;

class _ImportJsonDialogState extends State<_ImportJsonDialog> {
  final _jsonController = TextEditingController();
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode(debugLabel: 'stremio-import-json-name');
  final _jsonFocusNode = FocusNode(debugLabel: 'stremio-import-json-content');
  final _cancelFocusNode = FocusNode(debugLabel: 'stremio-import-json-cancel');
  final _importFocusNode = FocusNode(debugLabel: 'stremio-import-json-import');
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Name field DPAD exits live on the TvTextField (onUp/DownArrow).
    _jsonFocusNode.onKeyEvent = _handleJsonFieldKey;
    _cancelFocusNode.onKeyEvent = _handleCancelButtonKey;
    _importFocusNode.onKeyEvent = _handleImportButtonKey;
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    _jsonFocusNode.dispose();
    _cancelFocusNode.dispose();
    _importFocusNode.dispose();
    _jsonController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  KeyEventResult _handleJsonFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final text = _jsonController.text;
    final selection = _jsonController.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;
    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart =
        !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd =
        !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _cancelFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        _nameFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown || isActivateKey(key)) {
      if (isTextEmpty || isAtEnd) {
        _importFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCancelButtonKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _jsonFocusNode.requestFocus();
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
      _jsonFocusNode.requestFocus();
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
    final content = _jsonController.text.trim();
    if (content.isEmpty) {
      setState(() => _error = 'Paste JSON content');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final err = await LocalCatalogImporter.import(
      content,
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
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return AlertDialog(
      title: const Text('Paste JSON'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          lcBackHop(
            _cancelFocusNode,
            TvTextField(
              controller: _nameController,
              focusNode: _nameFocusNode,
              onUpArrow: () => _cancelFocusNode.requestFocus(),
              onDownArrow: () => _jsonFocusNode.requestFocus(),
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
          TextField(
            controller: _jsonController,
            focusNode: _jsonFocusNode,
            maxLines: 6,
            decoration: InputDecoration(
              hintText:
                  '{"name": "My Catalog", "items": [...]}\nor paste Trakt list JSON',
              border: OutlineInputBorder(borderRadius: app.shape.br(12)),
              errorText: _error,
              contentPadding: const EdgeInsets.all(12),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            autofocus: true,
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
