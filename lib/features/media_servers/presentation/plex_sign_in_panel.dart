import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/plex_sign_in_controller.dart';
import '../application/plex_sign_in_providers.dart';
import '../models/plex_server_choice.dart';

/// Plex sign-in with a plex.tv/link code, then a server choice. Works with
/// directional keys, Select and Back: after every step the step's main action
/// takes focus (even when the page's other fields held it), and leaving the
/// page stops the sign-in.
class PlexSignInPanel extends ConsumerStatefulWidget {
  const PlexSignInPanel({
    super.key,
    required this.label,
    required this.onDone,
    this.replaceId,
  });

  /// The optional display name typed above the panel.
  final TextEditingController label;
  final VoidCallback onDone;
  final String? replaceId;

  @override
  ConsumerState<PlexSignInPanel> createState() => _PlexSignInPanelState();
}

class _PlexSignInPanelState extends ConsumerState<PlexSignInPanel> {
  final _primary = FocusNode(debugLabel: 'plex-sign-in-primary');
  bool _allowInsecureLocal = false;

  PlexSignInController get _controller =>
      ref.read(plexSignInControllerProvider.notifier);

  @override
  void dispose() {
    _primary.dispose();
    super.dispose();
  }

  void _start() =>
      _controller.start(replaceId: widget.replaceId, label: widget.label.text);

  /// The previous step's button is gone; give its focus to the new one.
  void _focusPrimaryAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Not while a dialog or another page covers this one.
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      if (_primary.context != null) _primary.requestFocus();
    });
  }

  Future<void> _openLink(Future<bool> Function() open) async {
    try {
      await open();
    } catch (_) {
      // No browser: the code can still be entered on another device.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(plexSignInControllerProvider, (previous, next) {
      if (next is PlexSignInDone && previous is! PlexSignInDone) {
        widget.onDone();
        return;
      }
      if (next.runtimeType != previous.runtimeType) _focusPrimaryAfterFrame();
    });
    final state = ref.watch(plexSignInControllerProvider);
    return switch (state) {
      PlexSignInIdle() => _Step(
        text:
            'Sign in with your Plex account, then choose one of your servers. '
            'Your password is never entered in Debrify.',
        primary: FilledButton(
          focusNode: _primary,
          onPressed: _start,
          child: const Text('Sign in with Plex'),
        ),
      ),
      PlexSignInBusy() || PlexSignInDone() => _Step(
        text: 'Connecting…',
        body: const Center(child: CircularProgressIndicator()),
        primary: TextButton(
          focusNode: _primary,
          onPressed: _controller.cancel,
          child: const Text('Cancel'),
        ),
      ),
      PlexSignInWaiting(:final code) => _Waiting(
        code: code,
        primary: _primary,
        openLink: switch (ref.watch(plexOpenLinkProvider)) {
          final open? => () => _openLink(open),
          null => null,
        },
        onCancel: _controller.cancel,
      ),
      PlexSignInExpired() => _Step(
        text: 'This code expired before it was entered.',
        primary: FilledButton(
          focusNode: _primary,
          onPressed: _controller.renewCode,
          child: const Text('Get a new code'),
        ),
        secondary: TextButton(
          onPressed: _controller.cancel,
          child: const Text('Cancel'),
        ),
      ),
      PlexSignInChoosing(:final servers, :final message) => _Servers(
        servers: servers,
        message: message,
        primary: _primary,
        allowInsecureLocal: _allowInsecureLocal,
        onAllowInsecureLocal: (value) =>
            setState(() => _allowInsecureLocal = value),
        onChoose: (server) => _controller.choose(
          server.id,
          allowInsecureLocal: _allowInsecureLocal,
          label: widget.label.text,
        ),
        onCancel: _controller.cancel,
      ),
      PlexSignInFailed(:final message) => _Step(
        text: message,
        error: true,
        primary: FilledButton(
          focusNode: _primary,
          onPressed: _start,
          child: const Text('Try again'),
        ),
      ),
    };
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.text,
    required this.primary,
    this.body,
    this.secondary,
    this.error = false,
  });

  final String text;
  final Widget primary;
  final Widget? body;
  final Widget? secondary;
  final bool error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        text,
        style: error
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      const SizedBox(height: 16),
      if (body != null) ...[body!, const SizedBox(height: 16)],
      primary,
      if (secondary != null) ...[const SizedBox(height: 8), secondary!],
    ],
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.code,
    required this.primary,
    required this.openLink,
    required this.onCancel,
  });

  final String code;
  final FocusNode primary;
  final VoidCallback? openLink;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('On your phone or computer, go to plex.tv/link and enter:'),
        const SizedBox(height: 16),
        Semantics(
          label: 'Code ${code.split('').join(' ')}',
          excludeSemantics: true,
          child: Text(
            code,
            textAlign: TextAlign.center,
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 8,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Waiting for plex.tv… This page updates by itself.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (openLink != null)
          FilledButton(
            focusNode: primary,
            onPressed: openLink,
            child: const Text('Open plex.tv/link'),
          ),
        const SizedBox(height: 8),
        TextButton(
          focusNode: openLink == null ? primary : null,
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _Servers extends StatelessWidget {
  const _Servers({
    required this.servers,
    required this.message,
    required this.primary,
    required this.allowInsecureLocal,
    required this.onAllowInsecureLocal,
    required this.onChoose,
    required this.onCancel,
  });

  final List<PlexServerChoice> servers;
  final String? message;
  final FocusNode primary;
  final bool allowInsecureLocal;
  final ValueChanged<bool> onAllowInsecureLocal;
  final ValueChanged<PlexServerChoice> onChoose;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choose a server', style: theme.textTheme.titleMedium),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(message!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 8),
        for (final (index, server) in servers.indexed)
          ListTile(
            focusNode: index == 0 ? primary : null,
            leading: const Icon(Icons.dns_outlined),
            title: Text(server.name),
            subtitle: Text(
              [
                server.owned ? 'Your server' : 'Shared with you',
                if (!server.hasSecureAddress) 'No encrypted address',
              ].join(' · '),
            ),
            onTap: () => onChoose(server),
          ),
        if (servers.any((s) => s.hasInsecureLocalAddress))
          CheckboxListTile(
            value: allowInsecureLocal,
            onChanged: (value) => onAllowInsecureLocal(value ?? false),
            title: const Text(
              "Allow an unencrypted connection to this server's local address",
            ),
            subtitle: const Text(
              'Only if the encrypted address does not work on your network. '
              'Your Plex sign-in is then sent without encryption to that '
              'address.',
            ),
          ),
        const SizedBox(height: 8),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}
