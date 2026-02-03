import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/remote_control/remote_constants.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/udp_discovery_service.dart';
import 'remote_dpad_widget.dart';
import 'remote_addon_export.dart';

/// Full remote control UI modal
class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  // Track which view is showing: null = menu, 'navigate' = D-pad controls
  String? _activeView;

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

  void _openView(String view) {
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
    final isConnected = state.isConnected;
    final deviceName = state.connectedDevice?.deviceName ?? 'TV';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context, isConnected, deviceName),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),

                    // Connection status
                    if (!isConnected) ...[
                      _buildNotConnectedView(state),
                    ] else if (_activeView == 'navigate') ...[
                      // Navigate view - D-pad and media controls
                      _buildNavigateView(state),
                    ] else if (_activeView == 'addons') ...[
                      // Addons view - export addons to TV
                      RemoteAddonExport(onBack: _closeView),
                    ] else ...[
                      // Main menu
                      _buildConnectedMenu(state),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isConnected, String deviceName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),

          const SizedBox(width: 8),

          // Title
          Expanded(
            child: Text(
              'Remote Control',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Connection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isConnected
                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                  : const Color(0xFFEF4444).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected
                    ? const Color(0xFF10B981).withValues(alpha: 0.5)
                    : const Color(0xFFEF4444).withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? deviceName : 'Disconnected',
                  style: TextStyle(
                    color: isConnected
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Scanning...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ] else ...[
              Icon(
                hasDevices ? Icons.tv : Icons.tv_off,
                size: 20,
                color: hasDevices
                    ? const Color(0xFF10B981)
                    : Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 12),
              Text(
                hasDevices
                    ? '${state.discoveredDevices.length} TV${state.discoveredDevices.length > 1 ? 's' : ''} found'
                    : 'No TVs found',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],

            const Spacer(),

            // Scan/Rescan button
            TextButton.icon(
              onPressed: state.isScanning
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      state.rescan();
                    },
              icon: Icon(
                Icons.radar,
                size: 18,
                color: state.isScanning
                    ? Colors.white.withValues(alpha: 0.3)
                    : const Color(0xFF6366F1),
              ),
              label: Text(
                hasDevices ? 'Rescan' : 'Scan',
                style: TextStyle(
                  color: state.isScanning
                      ? Colors.white.withValues(alpha: 0.3)
                      : const Color(0xFF6366F1),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Device list or empty state
        if (hasDevices) ...[
          // Device list
          ...state.discoveredDevices.map((device) => _buildDeviceTile(device, state)),
        ] else if (!state.isScanning) ...[
          // Empty state
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E293B),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Icon(
              Icons.tv_off,
              size: 36,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            state.lastError ?? 'No TVs found on your network',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure Debrify is running on your TV',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildDeviceTile(DiscoveredDevice device, RemoteControlState state) {
    final isConnecting = state.connectionState == RemoteConnectionState.connecting &&
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
                  state.connectToDevice(device);
                },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                // TV icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.tv,
                    color: Colors.white,
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        device.ip,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Connect button/indicator
                if (isConnecting)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Connect',
                      style: TextStyle(
                        color: Color(0xFF6366F1),
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

  Widget _buildConnectedMenu(RemoteControlState state) {
    return Column(
      children: [
        // Menu items
        _buildMenuItem(
          icon: Icons.gamepad_rounded,
          title: 'Navigate',
          subtitle: 'D-pad and media controls',
          onTap: () => _openView('navigate'),
        ),

        const SizedBox(height: 12),

        _buildMenuItem(
          icon: Icons.extension_rounded,
          title: 'Stremio Addons',
          subtitle: 'Send addons to your TV',
          onTap: () => _openView('addons'),
        ),

        const SizedBox(height: 24),

        // Switch TV option
        TextButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            state.disconnect();
            state.rescan();
          },
          child: Text(
            'Switch TV',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigateView(RemoteControlState state) {
    return Column(
      children: [
        // Back to menu button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _closeView,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to menu'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // DPAD
        const RemoteDpadWidget(size: 220),

        const SizedBox(height: 32),

        // Media controls
        _buildMediaControls(),

        const SizedBox(height: 24),

        // Back button (sends back command to TV)
        _buildBackButton(),
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

  Widget _buildBackButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          HapticFeedback.mediumImpact();
          RemoteControlState().sendNavigateCommand(NavigateCommand.back);
        },
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.3),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
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
            gradient: widget.isPrimary
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  )
                : null,
            color: widget.isPrimary ? null : const Color(0xFF334155),
            border: Border.all(
              color: widget.isPrimary
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.1),
            ),
            boxShadow: widget.isPrimary
                ? [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            widget.icon,
            color: Colors.white,
            size: widget.size * 0.5,
          ),
        ),
      ),
    );
  }
}
