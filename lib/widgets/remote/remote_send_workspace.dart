import 'package:flutter/material.dart';
import '../../models/stremio_addon.dart';
import '../../models/profiles/profile_policy.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/remote_constants.dart';
import '../../services/stremio_service.dart';
import '../../services/remote_control/remote_webdav_sync_account.dart';
import '../../theme/app_theme_scope.dart';
import 'remote_channel_export.dart';
import 'remote_config_export.dart';
import 'remote_send_browser.dart';

/// Keeps the existing, authorization-aware inventory and send handlers mounted
/// while the user moves between categories. No credentials enter selection IDs.
class RemoteSendWorkspace extends StatefulWidget {
  const RemoteSendWorkspace({
    super.key,
    required this.onEverything,
    required this.onPhoto,
  });
  final VoidCallback onEverything;
  final VoidCallback onPhoto;
  @override
  State<RemoteSendWorkspace> createState() => _RemoteSendWorkspaceState();
}

class _RemoteSendWorkspaceState extends State<RemoteSendWorkspace> {
  final _config = GlobalKey<RemoteConfigExportState>();
  final _channels = GlobalKey<RemoteChannelExportState>();
  final _basket = RemoteSendBasket();
  List<StremioAddon> _addons = [];
  bool _loadingAddons = true;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _loadAddons();
  }

  @override
  void dispose() {
    _basket.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAddons() async {
    if (mounted) setState(() => _loadingAddons = true);
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.remoteTransfer,
      );
      final addons = authorization == null
          ? await StremioService.instance.getAddons(forRemoteTransfer: true)
          : await authorization.runIfCurrent(
              () => StremioService.instance.getAddons(forRemoteTransfer: true),
            );
      if (!mounted) return;
      setState(() {
        _addons = addons;
        _loadingAddons = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingAddons = false;
          _error = 'Could not load addons for this profile.';
        });
      }
    }
  }

  List<RemoteSendChoice> get _choices => [
    for (var i = 0; i < _addons.length; i++)
      RemoteSendChoice(
        id: 'addon:$i',
        label: _addons[i].name,
        group: RemoteSendGroup.addons,
      ),
    for (final item
        in _config.currentState?.choices ?? <({String id, String name})>[])
      RemoteSendChoice(
        id: 'setup:${item.id}',
        label: item.id == ConfigCommand.webDav
            ? 'WebDAV media servers'
            : item.name,
        detail: item.id == ConfigCommand.webDav
            ? 'Browsing connections · Separate from WebDAV sync'
            : null,
        group: item.id == remoteWebDavSyncAccountId
            ? RemoteSendGroup.webDavSync
            : RemoteSendGroup.setup,
      ),
    for (final channel in _channels.currentState?.channels ?? [])
      RemoteSendChoice(
        id: 'channel:${channel.channelId}',
        label: channel.name,
        group: RemoteSendGroup.channels,
        detail: 'Saved torrent hashes included',
      ),
  ];
  Future<void> _review(List<RemoteSendChoice> choices) async {
    if (_busy || choices.isEmpty) return;
    setState(() => _busy = true);
    final password = TextEditingController();
    final succeeded = <String>{};
    bool attempted = false;
    try {
      final state = RemoteControlState();
      final device = state.connectedDevice;
      if (device == null) return;
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.remoteTransfer,
      );
      final needsPassword = choices.any(
        (c) => c.id == 'setup:${ConfigCommand.pikpak}',
      );
      if (!mounted) return;
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                title: Text(
                  'Send ${choices.length} item${choices.length == 1 ? '' : 's'}?',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('To ${device.deviceName}'),
                      const SizedBox(height: 14),
                      for (final choice in choices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• ${choice.label}'),
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Setup items apply to the receiving device’s active profile. Keep both apps open and confirm the import there.',
                      ),
                      if (needsPassword)
                        TextField(
                          controller: password,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'PikPak password',
                          ),
                          onChanged: (_) => update(() {}),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: needsPassword && password.text.isEmpty
                        ? null
                        : () => Navigator.pop(context, true),
                    child: const Text('Send now'),
                  ),
                ],
              ),
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
      attempted = true;
      Future<void> run() async {
        if (state.connectedDevice?.ip != device.ip) {
          throw StateError('The receiving device changed');
        }
        final setup = choices
            .where(
              (c) =>
                  c.group == RemoteSendGroup.setup ||
                  c.group == RemoteSendGroup.webDavSync,
            )
            .map((c) => c.id.substring(6))
            .toSet();
        final addons = choices
            .where((c) => c.group == RemoteSendGroup.addons)
            .map((c) => _addons[int.parse(c.id.substring(6))])
            .toList();
        if (setup.isNotEmpty || addons.isNotEmpty) {
          final applied =
              await _config.currentState?.sendSelection(
                setup,
                addons,
                password.text,
              ) ??
              false;
          if (applied) {
            succeeded.addAll(
              choices
                  .where((c) => c.group != RemoteSendGroup.channels)
                  .map((c) => c.id),
            );
          }
        }
        if (!mounted || state.connectedDevice?.ip != device.ip) return;
        final channelIds = choices
            .where((c) => c.group == RemoteSendGroup.channels)
            .map((c) => c.id.substring(8))
            .toSet();
        if (channelIds.isNotEmpty) {
          final sent =
              await _channels.currentState?.sendSelection(channelIds) ??
              <String>{};
          succeeded.addAll(sent.map((id) => 'channel:$id'));
        }
      }

      await state.transferActivity.run(() async {
        if (authorization == null) {
          await run();
        } else {
          await authorization.runIfCurrentAsOutbound(run);
        }
      });
      if (!mounted) return;
      _basket.remove(succeeded);
      final failed = choices.where((c) => !succeeded.contains(c.id)).toList();
      _basket.select(failed.map((c) => c.id));
      final acknowledged =
          (state.sessionFor(device.ip)?.peerProtocolVersion ?? 0) >=
          kRemoteTransferResultProtocolVersion;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            failed.isEmpty
                ? (acknowledged ? 'Transfer complete' : 'Transfer sent')
                : 'Some items need another attempt',
          ),
          content: Text(
            failed.isEmpty
                ? (acknowledged
                      ? 'The receiving device saved all ${choices.length} selected items.'
                      : 'Confirm the import on the receiving device.')
                : '${succeeded.length} sent successfully. These remain selected for retry:\n${failed.map((c) => c.label).join('\n')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Transfer could not finish. Check the receiving device and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && attempted) {
        _basket.remove(succeeded);
        _basket.select(
          choices.where((c) => !succeeded.contains(c.id)).map((c) => c.id),
        );
      }
      password.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return PopScope(
      canPop: !_busy,
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: app.core.tx,
            onPrimary: app.inkOn(app.core.tx),
            surface: app.settings.panel2,
            onSurface: app.core.tx,
          ),
        ),
        child: Column(
          children: [
            RemoteConfigExport(
              key: _config,
              headless: true,
              onBack: () {},
              onInventoryChanged: _changed,
            ),
            RemoteChannelExport(
              key: _channels,
              headless: true,
              onBack: () {},
              onInventoryChanged: _changed,
            ),
            RemoteSendBrowser(
              choices: _choices,
              basket: _basket,
              busy: _busy,
              loading:
                  _loadingAddons ||
                  (_config.currentState?.loading ?? true) ||
                  (_channels.currentState?.loading ?? true),
              error:
                  _error ??
                  _config.currentState?.inventoryError ??
                  _channels.currentState?.inventoryError,
              filePlaylists: _config.currentState?.filePlaylistCount ?? 0,
              onRetry: () {
                _basket.remove(_basket.ids);
                _loadAddons();
                _config.currentState?.reload();
                _channels.currentState?.reload();
              },
              onSend: _review,
              onEverything: widget.onEverything,
              onPhoto: widget.onPhoto,
            ),
          ],
        ),
      ),
    );
  }
}
