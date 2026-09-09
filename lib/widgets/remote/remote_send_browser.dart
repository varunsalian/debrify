import 'package:flutter/material.dart';
import '../../theme/app_theme_scope.dart';

enum RemoteSendGroup { addons, channels, setup, webDavSync }

class RemoteSendChoice {
  const RemoteSendChoice({
    required this.id,
    required this.label,
    required this.group,
    this.detail,
  });
  final String id;
  final String label;
  final RemoteSendGroup group;
  final String? detail;
}

/// Presentation-only selection state. Individual sends never change the basket.
class RemoteSendBasket extends ChangeNotifier {
  final Set<String> _ids = {};
  Set<String> get ids => Set.unmodifiable(_ids);
  void toggle(String id) {
    _ids.contains(id) ? _ids.remove(id) : _ids.add(id);
    notifyListeners();
  }

  void select(Iterable<String> ids) {
    _ids.addAll(ids);
    notifyListeners();
  }

  void remove(Iterable<String> ids) {
    _ids.removeAll(ids);
    notifyListeners();
  }
}

class RemoteSendBrowser extends StatefulWidget {
  const RemoteSendBrowser({
    super.key,
    required this.choices,
    required this.basket,
    required this.onSend,
    required this.onEverything,
    required this.onPhoto,
    this.loading = false,
    this.error,
    this.onRetry,
    this.busy = false,
    this.filePlaylists = 0,
  });
  final List<RemoteSendChoice> choices;
  final RemoteSendBasket basket;
  final ValueChanged<List<RemoteSendChoice>> onSend;
  final VoidCallback onEverything;
  final VoidCallback onPhoto;
  final bool loading;
  final bool busy;
  final String? error;
  final VoidCallback? onRetry;
  final int filePlaylists;
  @override
  State<RemoteSendBrowser> createState() => _RemoteSendBrowserState();
}

class _RemoteSendBrowserState extends State<RemoteSendBrowser> {
  RemoteSendGroup? _group;
  String name(RemoteSendGroup group) => switch (group) {
    RemoteSendGroup.addons => 'Addons',
    RemoteSendGroup.channels => 'Debrify TV channels',
    RemoteSendGroup.setup => 'Accounts & setup',
    RemoteSendGroup.webDavSync => 'WebDAV Sync',
  };
  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return ListenableBuilder(
      listenable: widget.basket,
      builder: (context, _) {
        final selected = widget.choices
            .where((c) => widget.basket.ids.contains(c.id))
            .toList();
        final visible = widget.choices.where((c) => c.group == _group).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_group == null) ...[
              _row(
                Icons.send_rounded,
                'Send everything',
                'All profiles, setup, TV data and WebDAV sync',
                widget.onEverything,
              ),
              const SizedBox(height: 22),
              Text(
                'Or send just what you need',
                style: TextStyle(
                  color: app.core.tx,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              for (final group in RemoteSendGroup.values)
                _row(
                  switch (group) {
                    RemoteSendGroup.addons => Icons.extension_outlined,
                    RemoteSendGroup.channels => Icons.live_tv_outlined,
                    RemoteSendGroup.setup => Icons.tune_rounded,
                    RemoteSendGroup.webDavSync => Icons.sync,
                  },
                  name(group),
                  '${widget.choices.where((c) => c.group == group).length} available · ${selected.where((c) => c.group == group).length} selected',
                  () => setState(() => _group = group),
                ),
              _row(
                Icons.account_circle_outlined,
                'Profile photo',
                'Choose an image for the TV’s active Admin',
                widget.onPhoto,
              ),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: (widget.busy || widget.loading)
                      ? null
                      : () => setState(() => _group = null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Send'),
                ),
              ),
              Text(
                name(_group!),
                style: TextStyle(
                  color: app.core.tx,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _group == RemoteSendGroup.channels
                    ? 'Every saved torrent hash travels with its channel.'
                    : 'Send one item, or select several.',
                style: TextStyle(color: t.dim),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: (widget.busy || widget.loading)
                        ? null
                        : () => widget.basket.select(visible.map((c) => c.id)),
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    onPressed: (widget.busy || widget.loading)
                        ? null
                        : () => widget.basket.remove(visible.map((c) => c.id)),
                    child: const Text('Clear selection'),
                  ),
                ],
              ),
              for (final choice in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: t.panel2,
                    shape: RoundedRectangleBorder(
                      borderRadius: app.shape.br(15),
                      side: BorderSide(color: t.line),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            value: widget.basket.ids.contains(choice.id),
                            onChanged: (widget.busy || widget.loading)
                                ? null
                                : (_) => widget.basket.toggle(choice.id),
                            title: Text(
                              choice.label,
                              style: TextStyle(color: app.core.tx),
                            ),
                            subtitle: choice.detail == null
                                ? null
                                : Text(
                                    choice.detail!,
                                    style: TextStyle(color: t.dim),
                                  ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TextButton(
                            onPressed: (widget.busy || widget.loading)
                                ? null
                                : () => widget.onSend([choice]),
                            child: Text(
                              'Send',
                              semanticsLabel: 'Send ${choice.label} only',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!widget.loading && visible.isEmpty && widget.error == null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _group == RemoteSendGroup.webDavSync
                        ? 'Connect WebDAV Sync in Sync & Migrate first, then return here from an unlocked Admin profile.'
                        : 'No ${name(_group!).toLowerCase()} available for this profile.',
                    style: TextStyle(color: t.dim),
                  ),
                ),
              if (_group == RemoteSendGroup.setup && widget.filePlaylists > 0)
                Text(
                  'File-imported IPTV playlists are included in Send everything → All profiles.',
                  style: TextStyle(color: t.dim),
                ),
            ],
            if (widget.loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: LinearProgressIndicator(),
              ),
            if (widget.error != null) ...[
              Text(widget.error!, style: TextStyle(color: app.core.tx)),
              TextButton(
                onPressed: widget.busy ? null : widget.onRetry,
                child: const Text('Try again'),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              '${selected.length} selected across all categories',
              style: TextStyle(color: t.dim),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: widget.busy || widget.loading || selected.isEmpty
                  ? null
                  : () => widget.onSend(selected),
              child: Text(
                'Review ${selected.length} selected item${selected.length == 1 ? '' : 's'}',
              ),
            ),
            if (_group != null)
              TextButton(
                onPressed: (widget.busy || widget.loading)
                    ? null
                    : () => setState(() => _group = null),
                child: const Text('Add items from another category'),
              ),
          ],
        );
      },
    );
  }

  Widget _row(IconData icon, String label, String detail, VoidCallback action) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: app.settings.panel2,
        borderRadius: app.shape.br(15),
        child: ListTile(
          enabled: !widget.busy,
          shape: RoundedRectangleBorder(
            borderRadius: app.shape.br(15),
            side: BorderSide(color: app.settings.line),
          ),
          leading: Icon(icon, color: app.settings.dim),
          title: Text(label, style: TextStyle(color: app.core.tx)),
          subtitle: Text(detail, style: TextStyle(color: app.settings.dim)),
          trailing: Icon(Icons.chevron_right, color: app.settings.dim),
          onTap: widget.busy ? null : action,
        ),
      ),
    );
  }
}
