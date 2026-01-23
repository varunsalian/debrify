import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/account_service.dart';
import '../services/main_page_bridge.dart';
import '../services/torbox_account_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/storage_service.dart';
import '../services/engine/remote_engine_manager.dart';
import '../services/engine/local_engine_storage.dart';
import '../services/engine/config_loader.dart';
import '../services/engine/engine_registry.dart';
import '../utils/platform_util.dart';
import 'pikpak_folder_picker_dialog.dart';

class InitialSetupFlow extends StatefulWidget {
  const InitialSetupFlow({super.key});

  static Future<bool> show(BuildContext context) async {
    // Get the current focus scope to disable background focus
    final FocusScopeNode parentFocusScope = FocusScope.of(context);

    // AGGRESSIVE: Clear any existing focus BEFORE showing dialog
    FocusManager.instance.primaryFocus?.unfocus();

    // Disable focus on background widgets
    parentFocusScope.canRequestFocus = false;

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        useSafeArea: false,
        builder: (dialogContext) => const InitialSetupFlow(),
      );
      return result ?? false;
    } finally {
      // Re-enable focus on background widgets when dialog closes
      parentFocusScope.canRequestFocus = true;
    }
  }

  @override
  State<InitialSetupFlow> createState() => _InitialSetupFlowState();
}

enum _IntegrationType { realDebrid, torbox, pikpak }

class _IntegrationMeta {
  const _IntegrationMeta({
    required this.type,
    required this.title,
    required this.url,
    required this.linkLabel,
    required this.steps,
    required this.inputLabel,
    required this.hint,
    required this.gradient,
    required this.icon,
  });

  final _IntegrationType type;
  final String title;
  final String url;
  final String linkLabel;
  final List<String> steps;
  final String inputLabel;
  final String hint;
  final List<Color> gradient;
  final IconData icon;
}

const Map<_IntegrationType, _IntegrationMeta> _integrationMeta = {
  _IntegrationType.realDebrid: _IntegrationMeta(
    type: _IntegrationType.realDebrid,
    title: 'Real Debrid',
    url: 'https://real-debrid.com/apitoken',
    linkLabel: 'Open real-debrid.com/apitoken',
    steps: <String>[
      'Open the Real Debrid API token page in your browser.',
      'Sign in if prompted and scroll to the API token section.',
      'Generate a new token if needed, then copy the 40-character key.',
    ],
    inputLabel: 'Real Debrid API Token',
    hint: 'Paste your 40-character token here',
    gradient: <Color>[Color(0xFF1E3A8A), Color(0xFF6366F1)],
    icon: Icons.cloud_download_rounded,
  ),
  _IntegrationType.torbox: _IntegrationMeta(
    type: _IntegrationType.torbox,
    title: 'Torbox',
    url: 'https://torbox.app/settings?section=account',
    linkLabel: 'Open torbox.app settings',
    steps: <String>[
      'Visit the Torbox account settings page.',
      'Log in and scroll to the bottom "API Key" section.',
      'Copy the key displayed under your API details.',
    ],
    inputLabel: 'Torbox API Key',
    hint: 'Paste your Torbox API key here',
    gradient: <Color>[Color(0xFF7C3AED), Color(0xFFEC4899)],
    icon: Icons.flash_on_rounded,
  ),
  _IntegrationType.pikpak: _IntegrationMeta(
    type: _IntegrationType.pikpak,
    title: 'PikPak',
    url: 'https://mypikpak.com/drive/login',
    linkLabel: 'Open PikPak login page',
    steps: <String>[
      'Create a PikPak account if you don\'t have one.',
      'Remember your email and password.',
      'Enter your credentials below to connect.',
    ],
    inputLabel: 'Email',
    hint: 'your@email.com',
    gradient: <Color>[Color(0xFF10B981), Color(0xFF059669)],
    icon: Icons.cloud_queue_rounded,
  ),
};

class _InitialSetupFlowState extends State<InitialSetupFlow> {
  final Set<_IntegrationType> _selection = <_IntegrationType>{};
  final TextEditingController _realDebridController = TextEditingController();
  final TextEditingController _torboxController = TextEditingController();
  final TextEditingController _pikpakEmailController = TextEditingController();
  final TextEditingController _pikpakPasswordController =
      TextEditingController();
  int _stepIndex =
      0; // 0 => welcome, >0 => selected integrations, -1 => engine selection
  List<_IntegrationType> _flow = const <_IntegrationType>[];
  bool _isProcessing = false;
  String? _errorMessage;
  bool _hasConfigured = false;

  // Engine selection state
  final RemoteEngineManager _remoteEngineManager = RemoteEngineManager();
  List<RemoteEngineInfo> _availableEngines = [];
  Set<String> _selectedEngineIds = {};
  bool _isLoadingEngines = false;
  String? _engineError;

  bool _isAndroidTv = false; // Store TV detection result
  bool _isTvDetectionComplete = false; // Track if TV detection is done

  // Scroll controller for auto-scrolling on DPAD navigation
  final ScrollController _scrollController = ScrollController();

  // Map to store focus listener callbacks for proper disposal
  final Map<FocusNode, VoidCallback> _focusListeners = {};

  // Focus nodes for TV/DPAD navigation
  final FocusNode _dialogFocusNode = FocusNode(
    debugLabel: 'initial-setup-dialog',
  );
  final FocusNode _realDebridChipFocusNode = FocusNode(debugLabel: 'rd-chip');
  final FocusNode _torboxChipFocusNode = FocusNode(debugLabel: 'torbox-chip');
  final FocusNode _pikpakChipFocusNode = FocusNode(debugLabel: 'pikpak-chip');
  final FocusNode _skipButtonFocusNode = FocusNode(debugLabel: 'skip-button');
  final FocusNode _continueButtonFocusNode = FocusNode(
    debugLabel: 'continue-button',
  );
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'back-button');
  final FocusNode _openLinkButtonFocusNode = FocusNode(
    debugLabel: 'open-link-button',
  );
  final FocusNode _textFieldFocusNode = FocusNode(debugLabel: 'api-key-field');
  final FocusNode _pikpakEmailFieldFocusNode = FocusNode(
    debugLabel: 'pikpak-email-field',
  );
  final FocusNode _pikpakPasswordFieldFocusNode = FocusNode(
    debugLabel: 'pikpak-password-field',
  );
  final FocusNode _skipForNowButtonFocusNode = FocusNode(
    debugLabel: 'skip-for-now',
  );
  final FocusNode _connectButtonFocusNode = FocusNode(
    debugLabel: 'connect-button',
  );
  final FocusNode _folderRestrictionSkipButtonFocusNode = FocusNode(
    debugLabel: 'folder-restriction-skip',
  );
  final FocusNode _folderRestrictionSelectButtonFocusNode = FocusNode(
    debugLabel: 'folder-restriction-select',
  );

  // Engine selection focus nodes
  final FocusNode _engineSkipButtonFocusNode = FocusNode(
    debugLabel: 'engine-skip-button',
  );
  final FocusNode _engineImportButtonFocusNode = FocusNode(
    debugLabel: 'engine-import-button',
  );
  final FocusNode _engineRetryButtonFocusNode = FocusNode(
    debugLabel: 'engine-retry-button',
  );
  final Map<String, FocusNode> _engineItemFocusNodes = {};

  // DPAD shortcuts for arrow key navigation
  static const Map<ShortcutActivator, Intent> _dpadShortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
      TraversalDirection.down,
    ),
    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
      TraversalDirection.up,
    ),
    SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
      TraversalDirection.right,
    ),
    SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
      TraversalDirection.left,
    ),
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  };

  @override
  void initState() {
    super.initState();

    // Add focus listeners for auto-scrolling on TV
    _addFocusListeners();

    // Detect Android TV and setup accordingly
    _detectAndroidTV();
  }

  Future<void> _detectAndroidTV() async {
    // Use addPostFrameCallback to ensure widget is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      try {
        // Check if this is an Android TV device
        final isTV = await PlatformUtil.isAndroidTV();
        if (!mounted) return;

        setState(() {
          _isAndroidTv = isTV;
          _isTvDetectionComplete = true;
        });

        // Only request focus on TV devices for D-pad navigation
        if (_isAndroidTv) {
          // Wait for next frame to ensure UI is ready
          await Future.delayed(const Duration(milliseconds: 100));
          if (!mounted) return;

          // Verify dialog is still visible and topmost
          final navigator = Navigator.maybeOf(context);
          if (navigator == null || !navigator.canPop()) return;

          // Request focus on the first chip
          FocusManager.instance.primaryFocus?.unfocus();
          _realDebridChipFocusNode.requestFocus();
        }
      } catch (e) {
        // Failed to detect TV, default to non-TV mode
        if (!mounted) return;
        setState(() {
          _isAndroidTv = false;
          _isTvDetectionComplete = true;
        });
      }
    });
  }

  void _addFocusListeners() {
    // Add listeners to all focusable elements for auto-scrolling
    final focusNodes = [
      _realDebridChipFocusNode,
      _torboxChipFocusNode,
      _pikpakChipFocusNode,
      _skipButtonFocusNode,
      _continueButtonFocusNode,
      _backButtonFocusNode,
      _openLinkButtonFocusNode,
      _textFieldFocusNode,
      _pikpakEmailFieldFocusNode,
      _pikpakPasswordFieldFocusNode,
      _skipForNowButtonFocusNode,
      _connectButtonFocusNode,
      _engineSkipButtonFocusNode,
      _engineImportButtonFocusNode,
    ];

    for (final node in focusNodes) {
      // Create a named listener callback that we can remove later
      void listener() {
        if (node.hasFocus && _isAndroidTv) {
          _scrollToFocusedWidget(node);
        }
      }

      // Store the listener so we can remove it in dispose
      _focusListeners[node] = listener;

      // Add the listener to the node
      node.addListener(listener);
    }
  }

  void _removeFocusListeners() {
    // Remove all focus listeners to prevent memory leaks
    _focusListeners.forEach((node, listener) {
      node.removeListener(listener);
    });
    _focusListeners.clear();
  }

  void _scrollToFocusedWidget(FocusNode node) {
    if (!_scrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || node.context == null) return;

      try {
        final RenderBox? renderBox = node.context!.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) return;

        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        final screenHeight = MediaQuery.of(context).size.height;

        // Calculate if widget is out of view
        final widgetTop = position.dy;
        final widgetBottom = position.dy + size.height;

        // Scroll if widget is not fully visible
        if (widgetTop < 100 || widgetBottom > screenHeight - 100) {
          final scrollOffset = _scrollController.offset + (widgetTop - screenHeight / 2 + size.height / 2);
          _scrollController.animateTo(
            scrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      } catch (e, stackTrace) {
        // Log errors during scrolling calculations for debugging
        debugPrint('Error calculating scroll position: $e');
        if (kDebugMode) {
          debugPrint('Stack trace: $stackTrace');
        }
      }
    });
  }

  @override
  void dispose() {
    // Remove focus listeners FIRST to prevent memory leaks
    _removeFocusListeners();

    // Dispose controllers and focus nodes
    _scrollController.dispose();
    _realDebridController.dispose();
    _torboxController.dispose();
    _pikpakEmailController.dispose();
    _pikpakPasswordController.dispose();
    _dialogFocusNode.dispose();
    _realDebridChipFocusNode.dispose();
    _torboxChipFocusNode.dispose();
    _pikpakChipFocusNode.dispose();
    _skipButtonFocusNode.dispose();
    _continueButtonFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _openLinkButtonFocusNode.dispose();
    _textFieldFocusNode.dispose();
    _pikpakEmailFieldFocusNode.dispose();
    _pikpakPasswordFieldFocusNode.dispose();
    _skipForNowButtonFocusNode.dispose();
    _connectButtonFocusNode.dispose();
    _folderRestrictionSkipButtonFocusNode.dispose();
    _folderRestrictionSelectButtonFocusNode.dispose();
    _engineSkipButtonFocusNode.dispose();
    _engineImportButtonFocusNode.dispose();
    _engineRetryButtonFocusNode.dispose();
    for (final node in _engineItemFocusNodes.values) {
      node.dispose();
    }
    _engineItemFocusNodes.clear();
    _remoteEngineManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Responsive padding based on screen height
    final verticalPadding = screenHeight < 800 ? 16.0 : 32.0;
    final horizontalPadding = screenWidth < 600 ? 16.0 : 24.0;
    final innerVerticalPadding = screenHeight < 800 ? 16.0 : 32.0;
    final innerHorizontalPadding = screenWidth < 600 ? 16.0 : 28.0;

    return PopScope(
      canPop: false,
      child: FocusScope(
        node: FocusScopeNode(debugLabel: 'initial-setup-scope'),
        autofocus: true,
        child: Focus(
          autofocus: true,
          canRequestFocus: true,
          skipTraversal: true,
          descendantsAreFocusable: true,
          descendantsAreTraversable: true,
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: Builder(
              builder: (innerContext) => Shortcuts(
                shortcuts: _dpadShortcuts,
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    DirectionalFocusIntent:
                        CallbackAction<DirectionalFocusIntent>(
                          onInvoke: (intent) {
                            FocusScope.of(
                              innerContext,
                            ).focusInDirection(intent.direction);
                            return null;
                          },
                        ),
                  },
                  child: Dialog(
                    insetPadding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    backgroundColor: Colors.transparent,
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        final maxDialogHeight = screenHeight - (verticalPadding * 2);
                        final maxDialogWidth = screenWidth - (horizontalPadding * 2);
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: maxDialogHeight,
                            maxWidth: maxDialogWidth.clamp(300.0, 560.0),
                          ),
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: maxDialogWidth.clamp(300.0, 560.0),
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    gradient: const LinearGradient(
                                      colors: <Color>[
                                        Color(0xFF0F172A),
                                        Color(0xFF1F2937),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 28,
                                        offset: const Offset(0, 24),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: innerHorizontalPadding,
                                      vertical: innerVerticalPadding,
                                    ),
                                    child: LayoutBuilder(
                                      builder:
                                          (
                                            BuildContext context,
                                            BoxConstraints innerConstraints,
                                          ) {
                                            return AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 250,
                                              ),
                                              switchInCurve: Curves.easeOutCubic,
                                              switchOutCurve: Curves.easeInCubic,
                                              child: _stepIndex == 0
                                                  ? _buildWelcomeStep(
                                                      theme,
                                                      innerConstraints.maxWidth,
                                                      screenHeight,
                                                    )
                                                  : _stepIndex > _flow.length
                                                  ? _buildEngineSelectionStep(
                                                      theme,
                                                      innerConstraints.maxWidth,
                                                      screenHeight,
                                                    )
                                                  : _buildIntegrationStep(
                                                      theme,
                                                      _flow[_stepIndex - 1],
                                                      innerConstraints.maxWidth,
                                                      screenHeight,
                                                    ),
                                            );
                                          },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeStep(ThemeData theme, double availableWidth, double screenHeight) {
    final spacing1 = screenHeight < 800 ? 8.0 : 12.0;
    final spacing2 = screenHeight < 800 ? 16.0 : 24.0;
    final spacing3 = screenHeight < 800 ? 20.0 : 32.0;

    return Column(
      key: const ValueKey<String>('welcome'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Set up your services',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        SizedBox(height: spacing1),
        Text(
          'You can add others later from Settings.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        SizedBox(height: spacing2),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : availableWidth;
            final bool isNarrow = width < 440;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _integrationMeta.values.map((meta) {
                final focusNode = meta.type == _IntegrationType.realDebrid
                    ? _realDebridChipFocusNode
                    : meta.type == _IntegrationType.torbox
                    ? _torboxChipFocusNode
                    : _pikpakChipFocusNode;
                final order = meta.type == _IntegrationType.realDebrid
                    ? 1.0
                    : meta.type == _IntegrationType.torbox
                    ? 2.0
                    : 3.0;
                return SizedBox(
                  width: isNarrow ? width : (width - 16) / 2,
                  child: FocusTraversalOrder(
                    order: NumericFocusOrder(order),
                    child: _FocusableChip(
                      focusNode: focusNode,
                      selected: _selection.contains(meta.type),
                      onSelected: () => _toggleSelection(meta.type),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(meta.icon, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            meta.title,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        SizedBox(height: spacing3),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isCompact = constraints.maxWidth < 420;
            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(3),
                    child: TextButton(
                      focusNode: _skipButtonFocusNode,
                      onPressed: _isProcessing ? null : _goToEngineSelection,
                      child: const Text("I don't have any yet"),
                    ),
                  ),
                  SizedBox(height: spacing1),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(4),
                    child: FilledButton.icon(
                      focusNode: _continueButtonFocusNode,
                      onPressed: _selection.isEmpty || _isProcessing
                          ? null
                          : _startIntegrationFlow,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Continue'),
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: <Widget>[
                FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: TextButton(
                    focusNode: _skipButtonFocusNode,
                    onPressed: _isProcessing ? null : _goToEngineSelection,
                    child: const Text("I don't have any yet"),
                  ),
                ),
                const Spacer(),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(4),
                  child: FilledButton.icon(
                    focusNode: _continueButtonFocusNode,
                    onPressed: _selection.isEmpty || _isProcessing
                        ? null
                        : _startIntegrationFlow,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Continue'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildIntegrationStep(
    ThemeData theme,
    _IntegrationType type,
    double availableWidth,
    double screenHeight,
  ) {
    final _IntegrationMeta meta = _integrationMeta[type]!;
    final TextEditingController controller = type == _IntegrationType.realDebrid
        ? _realDebridController
        : type == _IntegrationType.torbox
        ? _torboxController
        : _pikpakEmailController;
    final int currentStep = _stepIndex;
    final int totalSteps = _flow.length;
    final bool isPikPak = type == _IntegrationType.pikpak;

    // Responsive spacing
    final spacing1 = screenHeight < 800 ? 8.0 : 12.0;
    final spacing2 = screenHeight < 800 ? 12.0 : 16.0;
    final spacing3 = screenHeight < 800 ? 16.0 : 24.0;

    return Column(
      key: ValueKey<_IntegrationType>(type),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: IconButton(
                focusNode: _backButtonFocusNode,
                onPressed: _isProcessing ? null : _goBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Step $currentStep of $totalSteps',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white60,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing1),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: meta.gradient),
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: meta.gradient.last.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Icon(meta.icon, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  meta.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing3),
        if (isPikPak) ...[
          Text(
            'Email',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          SizedBox(height: spacing1),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: _TvFriendlyTextField(
              controller: _pikpakEmailController,
              focusNode: _pikpakEmailFieldFocusNode,
              enabled: !_isProcessing,
              labelText: '',
              hintText: 'your@email.com',
              prefixIcon: const Icon(Icons.email_outlined),
              errorText: _errorMessage,
              onSubmitted: (_) {
                if (_isProcessing) return;
                _pikpakPasswordFieldFocusNode.requestFocus();
              },
            ),
          ),
          SizedBox(height: spacing2),
          Text(
            'Password',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          SizedBox(height: spacing1),
          FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: _TvFriendlyTextField(
              controller: _pikpakPasswordController,
              focusNode: _pikpakPasswordFieldFocusNode,
              enabled: !_isProcessing,
              labelText: '',
              hintText: 'Enter your password',
              prefixIcon: const Icon(Icons.lock_outline),
              obscureText: true,
              errorText: null,
              onSubmitted: (_) {
                if (_isProcessing) return;
                _submitCurrent();
              },
            ),
          ),
        ] else ...[
          Text(
            meta.inputLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          SizedBox(height: spacing1),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: _TvFriendlyTextField(
              controller: controller,
              focusNode: _textFieldFocusNode,
              enabled: !_isProcessing,
              labelText: '',
              hintText: meta.hint,
              prefixIcon: Icon(meta.icon),
              errorText: _errorMessage,
              onSubmitted: (_) {
                if (_isProcessing) return;
                _submitCurrent();
              },
            ),
          ),
          SizedBox(height: spacing2),
          FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: OutlinedButton.icon(
              focusNode: _openLinkButtonFocusNode,
              onPressed: _isProcessing ? null : () => _launch(meta.url),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(meta.linkLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
        ],
        SizedBox(height: spacing3),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : availableWidth;
            final bool isCompact = width < 420;
            final Widget primaryButton = FocusTraversalOrder(
              order: const NumericFocusOrder(5),
              child: FilledButton(
                focusNode: _connectButtonFocusNode,
                onPressed: _isProcessing ? null : _submitCurrent,
                child: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Connect ${meta.title}'),
              ),
            );
            final Widget skipButton = FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: TextButton(
                focusNode: _skipForNowButtonFocusNode,
                onPressed: _isProcessing ? null : _skipCurrent,
                child: const Text('Skip for now'),
              ),
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[skipButton],
                  ),
                  SizedBox(height: spacing1),
                  primaryButton,
                ],
              );
            }

            return Row(
              children: <Widget>[skipButton, const Spacer(), primaryButton],
            );
          },
        ),
      ],
    );
  }

  Widget _buildEngineSelectionStep(ThemeData theme, double availableWidth, double screenHeight) {
    // Responsive spacing
    final spacing1 = screenHeight < 800 ? 8.0 : 12.0;
    final spacing3 = screenHeight < 800 ? 16.0 : 24.0;

    // Responsive ListView height (30-40% of screen height)
    final listViewMaxHeight = screenHeight < 800
        ? screenHeight * 0.3  // 30% for small screens
        : 280.0;  // Fixed 280 for larger screens

    return Column(
      key: const ValueKey<String>('engine-selection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Import Search Engines',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        SizedBox(height: spacing1),
        Text(
          'Select the torrent search engines you want to use.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        SizedBox(height: spacing3),
        if (_isLoadingEngines)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Loading available engines...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          )
        else if (_engineError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load engines',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _engineError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: OutlinedButton.icon(
                      focusNode: _engineRetryButtonFocusNode,
                      onPressed: () {
                        setState(() {
                          _isLoadingEngines = true;
                          _engineError = null;
                        });
                        _loadAvailableEngines();
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text(
                        'Retry',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            constraints: BoxConstraints(maxHeight: listViewMaxHeight),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _availableEngines.length,
              itemBuilder: (context, index) {
                final engine = _availableEngines[index];
                final isSelected = _selectedEngineIds.contains(engine.id);
                final focusNode = _engineItemFocusNodes[engine.id];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FocusTraversalOrder(
                    order: NumericFocusOrder(index.toDouble()),
                    child: _FocusableEngineItem(
                      focusNode: focusNode,
                      isSelected: isSelected,
                      onToggle: () {
                        setState(() {
                          if (isSelected) {
                            _selectedEngineIds.remove(engine.id);
                          } else {
                            _selectedEngineIds.add(engine.id);
                          }
                        });
                      },
                      child: Row(
                        children: [
                          IgnorePointer(
                            child: Checkbox(
                              value: isSelected,
                              onChanged: null,
                              fillColor: WidgetStateProperty.resolveWith((
                                states,
                              ) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.white;
                                }
                                return Colors.transparent;
                              }),
                              checkColor: const Color(0xFF1F2937),
                              side: const BorderSide(color: Colors.white54),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            _getEngineIcon(engine.icon),
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              engine.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        SizedBox(height: spacing3),
        Row(
          children: [
            FocusTraversalOrder(
              order: NumericFocusOrder(_availableEngines.length.toDouble() + 1),
              child: TextButton(
                focusNode: _engineSkipButtonFocusNode,
                onPressed: _isProcessing
                    ? null
                    : () => Navigator.of(context).pop(_hasConfigured),
                child: const Text('Skip for now'),
              ),
            ),
            const Spacer(),
            FocusTraversalOrder(
              order: NumericFocusOrder(_availableEngines.length.toDouble() + 2),
              child: FilledButton(
                focusNode: _engineImportButtonFocusNode,
                onPressed: _isProcessing || _isLoadingEngines
                    ? null
                    : _importSelectedEngines,
                child: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _selectedEngineIds.isEmpty
                            ? 'Finish'
                            : 'Import ${_selectedEngineIds.length} Engine${_selectedEngineIds.length == 1 ? '' : 's'}',
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _getEngineIcon(String? iconName) {
    switch (iconName) {
      case 'sailing':
        return Icons.sailing;
      case 'storage':
        return Icons.storage;
      case 'movie':
        return Icons.movie;
      case 'tv':
        return Icons.tv;
      case 'cloud':
        return Icons.cloud;
      default:
        return Icons.extension;
    }
  }

  void _toggleSelection(_IntegrationType type) {
    setState(() {
      if (_selection.contains(type)) {
        _selection.remove(type);
      } else {
        _selection.add(type);
      }
    });
  }

  void _startIntegrationFlow() {
    final List<_IntegrationType> ordered = <_IntegrationType>[
      if (_selection.contains(_IntegrationType.realDebrid))
        _IntegrationType.realDebrid,
      if (_selection.contains(_IntegrationType.torbox)) _IntegrationType.torbox,
      if (_selection.contains(_IntegrationType.pikpak)) _IntegrationType.pikpak,
    ];

    if (ordered.isEmpty) return;

    setState(() {
      _flow = ordered;
      _stepIndex = 1;
      _errorMessage = null;
    });

    // On Android TV, auto-focus the first focusable element after step change
    if (_isAndroidTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _requestFocusForCurrentStep();
      });
    }
  }

  void _goBack() {
    if (_stepIndex <= 1) {
      setState(() {
        _stepIndex = 0;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _stepIndex -= 1;
        _errorMessage = null;
      });
    }

    // On Android TV, auto-focus the first focusable element after step change
    if (_isAndroidTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _requestFocusForCurrentStep();
      });
    }
  }

  void _skipCurrent() {
    setState(() {
      _errorMessage = null;
    });
    _advanceOrFinish();
  }

  Future<void> _submitCurrent() async {
    final _IntegrationType current = _flow[_stepIndex - 1];

    // Handle PikPak differently (email/password) vs API key services
    if (current == _IntegrationType.pikpak) {
      final String email = _pikpakEmailController.text.trim();
      final String password = _pikpakPasswordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter both email and password.';
        });
        return;
      }

      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });

      bool success = false;
      try {
        success = await PikPakApiService.instance.login(email, password);
        if (success) {
          await StorageService.setPikPakEnabled(true);
        }
      } catch (e, stackTrace) {
        debugPrint('PikPak login failed: $e');
        if (kDebugMode) {
          debugPrint('Stack trace: $stackTrace');
        }
        success = false;
      }

      if (!mounted) return;

      if (success) {
        setState(() {
          _isProcessing = false;
          _hasConfigured = true;
          _errorMessage = null;
        });
        MainPageBridge.notifyIntegrationChanged();

        // Ask if user wants to set up folder restriction
        final shouldSetupRestriction = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            // Auto-focus the first button when dialog opens for TV navigation
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _folderRestrictionSkipButtonFocusNode.requestFocus();
            });

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.folder_special, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Folder Restriction',
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'For enhanced security, you can restrict PikPak access to a specific folder.',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '• Full Access: Browse all files in your account',
                    style: TextStyle(fontSize: 13),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Restricted: Only access files in one folder',
                    style: TextStyle(fontSize: 13),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Note: You must logout and login again to change this later.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              actionsOverflowButtonSpacing: 8,
              actionsOverflowDirection: VerticalDirection.up,
              actions: [
                Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (_) {
                          Navigator.pop(dialogContext, false);
                          return null;
                        },
                      ),
                    },
                    child: Focus(
                      focusNode: _folderRestrictionSkipButtonFocusNode,
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Skip'),
                      ),
                    ),
                  ),
                ),
                Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (_) {
                          Navigator.pop(dialogContext, true);
                          return null;
                        },
                      ),
                    },
                    child: Focus(
                      focusNode: _folderRestrictionSelectButtonFocusNode,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Restrict'),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );

        // If user wants to set restriction, show folder picker
        if (shouldSetupRestriction == true && mounted) {
          final folderResult = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (ctx) => const PikPakFolderPickerDialog(),
          );

          if (!mounted) return; // Check after dialog closes

          // Save folder restriction if selected
          if (folderResult != null) {
            final folderId = folderResult['folderId'] as String?;
            final folderName = folderResult['folderName'] as String?;
            await StorageService.setPikPakRestrictedFolder(
              folderId,
              folderName,
            );
          }
        }

        if (!mounted) return; // Check before advancing
        _advanceOrFinish();
      } else {
        if (!mounted) return; // Check before setState
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Login failed. Please check your credentials.';
        });
      }
    } else {
      // Handle Real Debrid and Torbox (API key services)
      final TextEditingController controller =
          current == _IntegrationType.realDebrid
          ? _realDebridController
          : _torboxController;
      final String value = controller.text.trim();

      if (value.isEmpty) {
        setState(() {
          _errorMessage = 'Please paste your API key to continue.';
        });
        return;
      }

      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });

      bool success = false;
      try {
        if (current == _IntegrationType.realDebrid) {
          success = await AccountService.validateAndGetUserInfo(value);
        } else {
          success = await TorboxAccountService.validateAndGetUserInfo(value);
        }
      } catch (e, stackTrace) {
        final serviceName = current == _IntegrationType.realDebrid ? 'Real Debrid' : 'Torbox';
        debugPrint('$serviceName API validation failed: $e');
        if (kDebugMode) {
          debugPrint('Stack trace: $stackTrace');
        }
        success = false;
      }

      if (!mounted) return;

      if (success) {
        setState(() {
          _isProcessing = false;
          _hasConfigured = true;
          _errorMessage = null;
        });
        MainPageBridge.notifyIntegrationChanged();
        _advanceOrFinish();
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'That key did not work. Double-check it and try again.';
        });
      }
    }
  }

  void _advanceOrFinish() {
    if (_stepIndex >= _flow.length) {
      // Go to engine selection step
      _goToEngineSelection();
      return;
    }

    setState(() {
      _stepIndex += 1;
      _errorMessage = null;
    });

    // On Android TV, auto-focus the first focusable element after step change
    if (_isAndroidTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _requestFocusForCurrentStep();
      });
    }
  }

  void _goToEngineSelection() {
    setState(() {
      _stepIndex = _flow.length + 1;
      _isLoadingEngines = true;
      _engineError = null;
    });
    _loadAvailableEngines();
  }

  /// Request focus on the appropriate widget for the current step (Android TV)
  void _requestFocusForCurrentStep() {
    if (_stepIndex == 0) {
      // Welcome screen - focus first chip
      _realDebridChipFocusNode.requestFocus();
    } else if (_stepIndex > 0 && _stepIndex <= _flow.length) {
      // Integration step - focus the text field
      final currentType = _flow[_stepIndex - 1];
      if (currentType == _IntegrationType.pikpak) {
        // PikPak has email field first
        _pikpakEmailFieldFocusNode.requestFocus();
      } else if (currentType == _IntegrationType.realDebrid) {
        // Real Debrid uses the shared text field focus node
        _textFieldFocusNode.requestFocus();
      } else if (currentType == _IntegrationType.torbox) {
        // TorBox uses the shared text field focus node
        _textFieldFocusNode.requestFocus();
      }
    } else if (_stepIndex > _flow.length) {
      // Engine selection step
      if (_engineError != null) {
        _engineRetryButtonFocusNode.requestFocus();
      } else if (!_isLoadingEngines && _availableEngines.isNotEmpty) {
        _engineImportButtonFocusNode.requestFocus();
      }
    }
  }

  Future<void> _loadAvailableEngines() async {
    try {
      final engines = await _remoteEngineManager.fetchAvailableEngines();
      if (!mounted) return; // Early exit if widget disposed during fetch

      // Clean up old focus nodes AND their listeners before creating new ones
      for (final node in _engineItemFocusNodes.values) {
        // Remove listener if it exists
        final listener = _focusListeners[node];
        if (listener != null) {
          node.removeListener(listener);
          _focusListeners.remove(node);
        }
        node.dispose();
      }
      _engineItemFocusNodes.clear();

      // Create focus nodes for each engine AND register listeners
      for (final engine in engines) {
        final focusNode = FocusNode(
          debugLabel: 'engine-${engine.id}',
        );
        _engineItemFocusNodes[engine.id] = focusNode;

        // Create and register listener for auto-scrolling
        void listener() {
          if (focusNode.hasFocus && _isAndroidTv) {
            _scrollToFocusedWidget(focusNode);
          }
        }
        _focusListeners[focusNode] = listener;
        focusNode.addListener(listener);
      }

      if (!mounted) {
        // Widget was disposed while creating nodes - clean them up properly
        for (final node in _engineItemFocusNodes.values) {
          final listener = _focusListeners[node];
          if (listener != null) {
            node.removeListener(listener);
            _focusListeners.remove(node);
          }
          node.dispose();
        }
        _engineItemFocusNodes.clear();
        return;
      }

      setState(() {
        _availableEngines = engines;
        // Auto-select all engines by default
        _selectedEngineIds = engines.map((e) => e.id).toSet();
        _isLoadingEngines = false;
      });

      // Auto-focus the import button after a short delay
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _engineImportButtonFocusNode.requestFocus();
        }
      });
    } catch (e) {
      if (!mounted) return; // Early exit if disposed during error

      setState(() {
        _isLoadingEngines = false;
        _engineError = e.toString();
      });

      // Focus retry button on error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _engineRetryButtonFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _importSelectedEngines() async {
    if (_selectedEngineIds.isEmpty) {
      // Skip if no engines selected
      if (!mounted) return;
      Navigator.of(context).pop(_hasConfigured);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = true;
    });

    final localStorage = LocalEngineStorage.instance;
    int successCount = 0;

    for (final engine in _availableEngines) {
      if (!mounted) return; // Check during loop iterations
      if (!_selectedEngineIds.contains(engine.id)) continue;

      try {
        final yamlContent = await _remoteEngineManager.downloadEngineYaml(
          engine.fileName,
        );
        if (!mounted) return; // Check after async operation

        if (yamlContent != null) {
          await localStorage.saveEngine(
            engineId: engine.id,
            fileName: engine.fileName,
            yamlContent: yamlContent,
            displayName: engine.displayName,
            icon: engine.icon,
          );
          if (!mounted) return; // Check after async operation
          successCount++;
        }
      } catch (e) {
        debugPrint('Failed to import ${engine.id}: $e');
      }
    }

    if (!mounted) return;

    // Reload engine registry
    ConfigLoader().clearCache();
    await EngineRegistry.instance.reload();

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
    });

    if (!mounted) return;
    Navigator.of(context).pop(_hasConfigured || successCount > 0);
  }

  Future<void> _launch(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// A TV-friendly chip widget that shows clear focus indication
class _FocusableChip extends StatefulWidget {
  const _FocusableChip({
    required this.focusNode,
    required this.selected,
    required this.onSelected,
    required this.child,
  });

  final FocusNode focusNode;
  final bool selected;
  final VoidCallback onSelected;
  final Widget child;

  @override
  State<_FocusableChip> createState() => _FocusableChipState();
}

class _FocusableChipState extends State<_FocusableChip> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    // Safely add listener - focus node is guaranteed to exist in parent
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    // Safely remove listener before disposal
    try {
      widget.focusNode.removeListener(_handleFocusChange);
    } catch (e) {
      // Ignore if listener was already removed or node disposed
      debugPrint('_FocusableChip: Error removing listener: $e');
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              HapticFeedback.lightImpact();
              widget.onSelected();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: widget.focusNode,
          child: GestureDetector(
            onTap: widget.onSelected,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: widget.selected
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: _isFocused
                      ? Colors.white
                      : widget.selected
                      ? Colors.white.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.15),
                  width: _isFocused ? 2 : 1,
                ),
                boxShadow: _isFocused
                    ? <BoxShadow>[
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A TV-friendly engine item widget that shows clear focus indication
class _FocusableEngineItem extends StatefulWidget {
  const _FocusableEngineItem({
    required this.focusNode,
    required this.isSelected,
    required this.onToggle,
    required this.child,
  });

  final FocusNode? focusNode;
  final bool isSelected;
  final VoidCallback onToggle;
  final Widget child;

  @override
  State<_FocusableEngineItem> createState() => _FocusableEngineItemState();
}

class _FocusableEngineItemState extends State<_FocusableEngineItem> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    // Safely add listener with null check
    widget.focusNode?.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    // Safely remove listener with try-catch
    try {
      widget.focusNode?.removeListener(_handleFocusChange);
    } catch (e) {
      // Ignore if listener was already removed or node disposed
      debugPrint('_FocusableEngineItem: Error removing listener: $e');
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(_FocusableEngineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      // Safely remove old listener
      try {
        oldWidget.focusNode?.removeListener(_handleFocusChange);
      } catch (e) {
        debugPrint('_FocusableEngineItem: Error removing old listener: $e');
      }
      // Add new listener
      widget.focusNode?.addListener(_handleFocusChange);
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode?.hasFocus ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              HapticFeedback.lightImpact();
              widget.onToggle();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: widget.focusNode,
          child: GestureDetector(
            onTap: widget.onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: widget.isSelected
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: _isFocused
                      ? Colors.white
                      : widget.isSelected
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.1),
                  width: _isFocused ? 2 : 1,
                ),
                boxShadow: _isFocused
                    ? <BoxShadow>[
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A TV-friendly TextField that allows escaping with DPAD
class _TvFriendlyTextField extends StatefulWidget {
  const _TvFriendlyTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    this.errorText,
    this.onSubmitted,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String labelText;
  final String hintText;
  final Widget prefixIcon;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;

  @override
  State<_TvFriendlyTextField> createState() => _TvFriendlyTextFieldState();
}

class _TvFriendlyTextFieldState extends State<_TvFriendlyTextField> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    // Safely add listener - focus node is guaranteed to exist in parent
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    // Safely remove listener with try-catch
    try {
      widget.focusNode.removeListener(_handleFocusChange);
    } catch (e) {
      // Ignore if listener was already removed or node disposed
      debugPrint('_TvFriendlyTextField: Error removing listener: $e');
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Safety check: widget must be mounted to access context
    if (!mounted) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;

    // Check if selection is valid
    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart =
        !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd =
        !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    // Allow escape from TextField with back button (escape key)
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      final ctx = node.context;
      if (ctx != null && mounted) {
        try {
          FocusScope.of(ctx).previousFocus();
          return KeyEventResult.handled;
        } catch (e) {
          debugPrint('Error handling escape key: $e');
          return KeyEventResult.ignored;
        }
      }
    }

    // Navigate up: always allow if text is empty or cursor at start
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        final ctx = node.context;
        if (ctx != null && mounted) {
          try {
            // Use directional focus to go to element above
            FocusScope.of(ctx).focusInDirection(TraversalDirection.up);
            return KeyEventResult.handled;
          } catch (e) {
            debugPrint('Error handling arrow up: $e');
            return KeyEventResult.ignored;
          }
        }
      }
    }

    // Navigate down: always allow if text is empty or cursor at end
    if (key == LogicalKeyboardKey.arrowDown) {
      if (isTextEmpty || isAtEnd) {
        final ctx = node.context;
        if (ctx != null && mounted) {
          try {
            // Use directional focus to go to element below
            FocusScope.of(ctx).focusInDirection(TraversalDirection.down);
            return KeyEventResult.handled;
          } catch (e) {
            debugPrint('Error handling arrow down: $e');
            return KeyEventResult.ignored;
          }
        }
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      skipTraversal: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _isFocused ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: _isFocused
              ? <BoxShadow>[
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          obscureText: widget.obscureText,
          showCursor: true,
          autofocus: false,
          autofillHints: widget.obscureText
              ? const <String>[AutofillHints.password]
              : null,
          decoration: InputDecoration(
            labelText: widget.labelText.isEmpty ? null : widget.labelText,
            labelStyle: const TextStyle(color: Colors.white70),
            hintText: widget.hintText,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            prefixIcon: widget.prefixIcon,
            prefixIconColor: Colors.white70,
            errorText: widget.errorText,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
          ),
          style: const TextStyle(color: Colors.white),
          onSubmitted: widget.onSubmitted,
        ),
      ),
    );
  }
}
