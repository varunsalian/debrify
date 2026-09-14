import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_policy.dart';
import '../../services/profiles/profile_policy_guard.dart';
import '../../services/profiles/profile_avatar_ingest.dart';
import '../../services/remote_control/remote_constants.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/udp_discovery_service.dart';
import 'remote_dpad_widget.dart';
import 'remote_keyboard_input.dart';
import 'remote_pairing_dialog.dart';
import 'remote_transfer_all.dart';
import 'remote_transfer_progress.dart';
import 'remote_send_workspace.dart';
import 'remote_receive_screen.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import '../../theme/app_theme_scope.dart';
import '../../services/profiles/profile_runtime.dart';

/// Full remote control UI modal
class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  // Track which view is showing: null = menu, 'navigate' = D-pad controls
  String? _activeView;
  // Track if keyboard input is showing
  bool _showKeyboard = false;
  bool _sendingAvatar = false;

  @override
  void initState() {
    super.initState();
    RemoteControlState().addListener(_onStateChanged);
  }

  @override
  void dispose() {
    RemoteControlState().removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _receiveInstead() async {
    final state = RemoteControlState();
    try {
      final name =
          await StorageService.getRemoteTvDeviceName() ??
          await PlatformUtil.getDeviceName() ??
          'This device';
      if (!mounted) return;
      await state.switchToReceiverMode(name);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RemoteReceiveScreen()),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start receiving. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        await state.switchToSenderMode();
        if (mounted) _closeView();
      }
    }
  }

  Future<void> _openView(String view) async {
    if (view != 'navigate' &&
        !await ProfilePolicyGuard.allows(ProfileFeature.remoteTransfer)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Setup transfer is disabled for this profile.'),
        ),
      );
      return;
    }
    if (view == 'navigate') {
      if (!mounted) return;
      final state = RemoteControlState();
      final device = state.connectedDevice;
      if (device == null) return;
      final authorized = await ensureNavigationSession(context, state, device);
      if (!mounted || !authorized) {
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _activeView = view;
    });
  }

  void _closeView() {
    setState(() {
      _activeView = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = RemoteControlState();
    final app = AppThemeScope.of(context);
    return ListenableBuilder(
      listenable: state.transferActivity.status,
      builder: (context, _) {
        final busy = state.transferActivity.active || _sendingAvatar;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: app.core.tx,
              onPrimary: app.inkOn(app.core.tx),
              surface: app.settings.panel2,
              onSurface: app.core.tx,
            ),
          ),
          child: PopScope(
            canPop: !busy,
            child: Scaffold(
              backgroundColor: app.core.ground,
              appBar: AppBar(
                backgroundColor: app.core.ground,
                foregroundColor: app.core.tx,
                title: const Text('Remote'),
                actions: [
                  TextButton(
                    onPressed: busy ? null : _receiveInstead,
                    child: const Text('Receive instead'),
                  ),
                ],
                leading: BackButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).maybePop(),
                ),
              ),
              body: SafeArea(
                child: Column(
                  children: [
                    if (state.isConnected) ...[
                      ListTile(
                        title: Text(
                          state.connectedDevice?.deviceName ?? 'TV',
                          style: TextStyle(color: app.core.tx),
                        ),
                        subtitle: Text(
                          'Connected',
                          style: TextStyle(color: app.settings.dim),
                        ),
                        trailing: TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  await state.disconnect();
                                  await _connectSafely(state.rescan);
                                },
                          child: const Text('Change'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: _activeView != 'navigate'
                                  ? FilledButton(
                                      onPressed: busy ? null : _closeView,
                                      child: const Text('Send'),
                                    )
                                  : OutlinedButton(
                                      onPressed: busy ? null : _closeView,
                                      child: const Text('Send'),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _activeView == 'navigate'
                                  ? FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () => _openView('navigate'),
                                      child: const Text('Control'),
                                    )
                                  : OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => _openView('navigate'),
                                      child: const Text('Control'),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const RemoteTransferProgressPanel(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            if (!state.isConnected)
                              _buildNotConnectedView(state)
                            else ...[
                              Offstage(
                                offstage: _activeView != null,
                                child: ValueListenableBuilder(
                                  valueListenable: ProfileRuntime.scope,
                                  builder: (context, scope, _) =>
                                      RemoteSendWorkspace(
                                        key: ValueKey(scope),
                                        onEverything: () =>
                                            _openView('transfer_all'),
                                        onPhoto: () =>
                                            _pickAndSendAvatar(state),
                                      ),
                                ),
                              ),
                              if (_activeView == 'navigate')
                                _buildNavigateView(state),
                              if (_activeView == 'transfer_all')
                                RemoteTransferAll(onBack: _closeView),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotConnectedView(RemoteControlState state) {
    final hasDevices = state.discoveredDevices.isNotEmpty;

    return Column(
      children: [
        const SizedBox(height: 24),

        // Header row with status and scan button
        Row(
          children: [
            // Status indicator
            if (state.isScanning) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppThemeScope.of(context).core.tx,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Scanning...',
                  style: TextStyle(
                    color: AppThemeScope.of(
                      context,
                    ).core.tx.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ),
            ] else ...[
              Icon(
                hasDevices ? Icons.tv : Icons.tv_off,
                size: 20,
                color: hasDevices
                    ? const Color(0xFF10B981)
                    : AppThemeScope.of(context).core.tx.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasDevices
                      ? '${state.discoveredDevices.length} TV${state.discoveredDevices.length > 1 ? 's' : ''} found'
                      : 'No TVs found',
                  style: TextStyle(
                    color: AppThemeScope.of(
                      context,
                    ).core.tx.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ),
            ],

            // Scan/Rescan button
            TextButton.icon(
              onPressed: state.isScanning
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      _connectSafely(state.rescan);
                    },
              icon: Icon(
                Icons.radar,
                size: 18,
                color: state.isScanning
                    ? AppThemeScope.of(context).core.tx.withValues(alpha: 0.3)
                    : AppThemeScope.of(context).core.tx,
              ),
              label: Text(
                hasDevices ? 'Rescan' : 'Scan',
                style: TextStyle(
                  color: state.isScanning
                      ? AppThemeScope.of(context).core.tx.withValues(alpha: 0.3)
                      : AppThemeScope.of(context).core.tx,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Device list or empty state
        if (hasDevices) ...[
          // Device list
          ...state.discoveredDevices.map(
            (device) => _buildDeviceTile(device, state),
          ),
        ] else if (!state.isScanning) ...[
          // Empty state
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppThemeScope.of(context).settings.panel2,
              border: Border.all(
                color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.1),
              ),
            ),
            child: Icon(
              Icons.tv_off,
              size: 36,
              color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            state.lastError ?? 'No TVs found on your network',
            style: TextStyle(
              color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure Debrify is running on your TV',
            style: TextStyle(
              color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.5),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],

        // Manual IP entry — works for Tailscale or any reachable IP that
        // UDP broadcast discovery can't see.
        const SizedBox(height: 20),
        _buildManualIpButton(state),
      ],
    );
  }

  Widget _buildManualIpButton(RemoteControlState state) {
    return OutlinedButton.icon(
      onPressed: () {
        HapticFeedback.mediumImpact();
        _showManualIpDialog(state);
      },
      icon: Icon(Icons.lan_rounded, size: 18),
      label: Text('Connect by IP (Tailscale / VPN)'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppThemeScope.of(
          context,
        ).core.tx.withValues(alpha: 0.85),
        side: BorderSide(
          color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.18),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showManualIpDialog(RemoteControlState state) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppThemeScope.of(context).settings.panel2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Connect by IP',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the receiver\'s IP. For Tailscale, this is the 100.x.y.z address shown on the receiving device.',
                style: TextStyle(
                  color: AppThemeScope.of(
                    context,
                  ).core.tx.withValues(alpha: 0.65),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(fontSize: 15),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '100.64.0.5',
                    hintStyle: TextStyle(
                      color: AppThemeScope.of(
                        context,
                      ).core.tx.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: AppThemeScope.of(context).core.ground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppThemeScope.of(
                          context,
                        ).core.tx.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppThemeScope.of(
                          context,
                        ).core.tx.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppThemeScope.of(context).core.tx,
                        width: 1.5,
                      ),
                    ),
                    errorStyle: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12,
                    ),
                  ),
                  validator: _validateIpv4,
                  onFieldSubmitted: (_) => _submitManualIp(
                    dialogContext,
                    formKey,
                    controller,
                    state,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppThemeScope.of(
                    context,
                  ).core.tx.withValues(alpha: 0.6),
                ),
              ),
            ),
            FilledButton(
              onPressed: () =>
                  _submitManualIp(dialogContext, formKey, controller, state),
              style: FilledButton.styleFrom(
                backgroundColor: AppThemeScope.of(context).core.tx,
              ),
              child: Text('Connect'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _submitManualIp(
    BuildContext dialogContext,
    GlobalKey<FormState> formKey,
    TextEditingController controller,
    RemoteControlState state,
  ) {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final ip = controller.text.trim();
    Navigator.of(dialogContext).pop();
    HapticFeedback.mediumImpact();
    _connectSafely(() => state.connectToManualIp(ip));
  }

  Future<void> _connectSafely(Future<void> Function() connect) async {
    try {
      await connect();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start the connection. Check local network access and retry.',
          ),
        ),
      );
    }
  }

  String? _validateIpv4(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter an IP address';
    final parts = v.split('.');
    if (parts.length != 4) return 'Use the form 1.2.3.4';
    for (final p in parts) {
      if (p.isEmpty) return 'Use the form 1.2.3.4';
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return 'Each part must be 0–255';
    }
    return null;
  }

  Widget _buildDeviceTile(DiscoveredDevice device, RemoteControlState state) {
    final isConnecting =
        state.connectionState == RemoteConnectionState.connecting &&
        state.connectedDevice?.ip == device.ip;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isConnecting
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  _connectSafely(() => state.connectToDevice(device));
                },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppThemeScope.of(context).settings.panel2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                // TV icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppThemeScope.of(context).settings.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.tv,
                    color: AppThemeScope.of(
                      context,
                    ).inkOn(AppThemeScope.of(context).core.tx),
                    size: 24,
                  ),
                ),

                const SizedBox(width: 16),

                // Device info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        device.ip,
                        style: TextStyle(
                          color: AppThemeScope.of(
                            context,
                          ).core.tx.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Connect button/indicator
                if (isConnecting)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppThemeScope.of(context).core.tx,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppThemeScope.of(
                        context,
                      ).core.tx.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Connect',
                      style: TextStyle(
                        color: AppThemeScope.of(context).core.tx,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendAvatar(RemoteControlState state) =>
      RemoteControlState().transferActivity.run(
        () => _pickAndSendAvatarNow(state),
      );

  Future<void> _pickAndSendAvatarNow(RemoteControlState state) async {
    if (!await ProfilePolicyGuard.allows(ProfileFeature.remoteTransfer) ||
        !mounted) {
      return;
    }
    final device = state.connectedDevice;
    if (device == null) return;
    try {
      final pick = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a profile avatar',
        type: FileType.any,
        withData: false,
      );
      if (pick == null || pick.files.isEmpty || !mounted) return;
      final picked = pick.files.single;
      if (picked.size > ProfileAvatarIngest.maxInputBytes) {
        throw const ProfileAvatarRejected(
          'That image is too large to send. Choose one under 12 MB.',
        );
      }
      final bytes = await _readAvatarBytes(picked);
      if (!mounted) return;
      final session = await ensureAuthorizedSession(context, state, device);
      if (session == null || !mounted) return;
      setState(() => _sendingAvatar = true);
      final applied = await state.sendProfileAvatar(device.ip, bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            applied
                ? 'Profile avatar updated on TV'
                : 'The TV did not apply that avatar',
          ),
        ),
      );
    } on ProfileAvatarRejected catch (rejected) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(rejected.message)));
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The image picker is not available.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That avatar could not be sent.')),
      );
    } finally {
      if (mounted) setState(() => _sendingAvatar = false);
    }
  }

  Future<Uint8List> _readAvatarBytes(PlatformFile picked) async {
    final inline = picked.bytes;
    if (inline != null) return inline;
    final path = picked.path;
    if (path == null || path.isEmpty) {
      throw const ProfileAvatarRejected('That file could not be read.');
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in File(path).openRead()) {
      if (length > ProfileAvatarIngest.maxInputBytes - chunk.length) {
        throw const ProfileAvatarRejected(
          'That image is too large to send. Choose one under 12 MB.',
        );
      }
      builder.add(chunk);
      length += chunk.length;
    }
    return builder.takeBytes();
  }

  Widget _buildNavigateView(RemoteControlState state) {
    return Column(
      children: [
        // Back to menu button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              if (_showKeyboard) {
                setState(() => _showKeyboard = false);
              } else {
                _closeView();
              }
            },
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(_showKeyboard ? 'Hide keyboard' : 'Back to menu'),
            style: TextButton.styleFrom(
              foregroundColor: AppThemeScope.of(
                context,
              ).core.tx.withValues(alpha: 0.7),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Keyboard input (when shown)
        if (_showKeyboard) ...[
          RemoteKeyboardInput(
            onClose: () => setState(() => _showKeyboard = false),
          ),
          const SizedBox(height: 24),
        ],

        // DPAD
        const RemoteDpadWidget(size: 220),

        const SizedBox(height: 32),

        // Media controls
        _buildMediaControls(),

        const SizedBox(height: 24),

        // Keyboard toggle and Back button row
        Row(
          children: [
            // Keyboard button
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  setState(() => _showKeyboard = !_showKeyboard);
                },
                icon: Icon(
                  _showKeyboard ? Icons.keyboard_hide : Icons.keyboard,
                  size: 20,
                ),
                label: Text(_showKeyboard ? 'Hide' : 'Keyboard'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _showKeyboard
                      ? AppThemeScope.of(context).core.tx
                      : AppThemeScope.of(context).core.tx,
                  side: BorderSide(
                    color: _showKeyboard
                        ? AppThemeScope.of(context).core.tx
                        : AppThemeScope.of(
                            context,
                          ).core.tx.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Back button (sends back command to TV)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  RemoteControlState().sendNavigateCommand(
                    NavigateCommand.back,
                  );
                },
                icon: const Icon(Icons.arrow_back, size: 20),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppThemeScope.of(context).core.tx,
                  side: BorderSide(
                    color: AppThemeScope.of(
                      context,
                    ).core.tx.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMediaControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Seek backward
        _MediaButton(
          icon: Icons.fast_rewind,
          onPressed: () {
            HapticFeedback.lightImpact();
            RemoteControlState().sendMediaCommand(MediaCommand.seekBackward);
          },
        ),

        const SizedBox(width: 24),

        // Play/Pause
        _MediaButton(
          icon: Icons.play_arrow,
          size: 64,
          isPrimary: true,
          onPressed: () {
            HapticFeedback.mediumImpact();
            RemoteControlState().sendMediaCommand(MediaCommand.playPause);
          },
        ),

        const SizedBox(width: 24),

        // Seek forward
        _MediaButton(
          icon: Icons.fast_forward,
          onPressed: () {
            HapticFeedback.lightImpact();
            RemoteControlState().sendMediaCommand(MediaCommand.seekForward);
          },
        ),
      ],
    );
  }
}

class _MediaButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final bool isPrimary;

  const _MediaButton({
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.isPrimary = false,
  });

  @override
  State<_MediaButton> createState() => _MediaButtonState();
}

class _MediaButtonState extends State<_MediaButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isPrimary
                ? AppThemeScope.of(context).core.tx
                : AppThemeScope.of(context).settings.panel2,
            border: Border.all(color: AppThemeScope.of(context).settings.line),
          ),
          child: Icon(
            widget.icon,
            color: widget.isPrimary
                ? AppThemeScope.of(
                    context,
                  ).inkOn(AppThemeScope.of(context).core.tx)
                : AppThemeScope.of(context).core.tx,
            size: widget.size * 0.5,
          ),
        ),
      ),
    );
  }
}
