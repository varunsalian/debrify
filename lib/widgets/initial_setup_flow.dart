import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/account_service.dart';
import '../services/main_page_bridge.dart';
import '../services/torbox_account_service.dart';
import '../services/engine/remote_engine_manager.dart';
import '../services/engine/local_engine_storage.dart';
import '../services/engine/config_loader.dart';
import '../services/engine/engine_registry.dart';

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

enum _IntegrationType {
  realDebrid,
  torbox,
}

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
      'Log in and scroll to the bottom “API Key” section.',
      'Copy the key displayed under your API details.',
    ],
    inputLabel: 'Torbox API Key',
    hint: 'Paste your Torbox API key here',
    gradient: <Color>[Color(0xFF7C3AED), Color(0xFFEC4899)],
    icon: Icons.flash_on_rounded,
  ),
};

class _InitialSetupFlowState extends State<InitialSetupFlow> {
  final Set<_IntegrationType> _selection = <_IntegrationType>{};
  final TextEditingController _realDebridController = TextEditingController();
  final TextEditingController _torboxController = TextEditingController();
  int _stepIndex = 0; // 0 => welcome, >0 => selected integrations, -1 => engine selection
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

  // Focus nodes for TV/DPAD navigation
  final FocusNode _dialogFocusNode = FocusNode(debugLabel: 'initial-setup-dialog');
  final FocusNode _realDebridChipFocusNode = FocusNode(debugLabel: 'rd-chip');
  final FocusNode _torboxChipFocusNode = FocusNode(debugLabel: 'torbox-chip');
  final FocusNode _skipButtonFocusNode = FocusNode(debugLabel: 'skip-button');
  final FocusNode _continueButtonFocusNode = FocusNode(debugLabel: 'continue-button');
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'back-button');
  final FocusNode _openLinkButtonFocusNode = FocusNode(debugLabel: 'open-link-button');
  final FocusNode _textFieldFocusNode = FocusNode(debugLabel: 'api-key-field');
  final FocusNode _skipForNowButtonFocusNode = FocusNode(debugLabel: 'skip-for-now');
  final FocusNode _connectButtonFocusNode = FocusNode(debugLabel: 'connect-button');

  // Engine selection focus nodes
  final FocusNode _engineSkipButtonFocusNode = FocusNode(debugLabel: 'engine-skip-button');
  final FocusNode _engineImportButtonFocusNode = FocusNode(debugLabel: 'engine-import-button');
  final FocusNode _engineRetryButtonFocusNode = FocusNode(debugLabel: 'engine-retry-button');
  final Map<String, FocusNode> _engineItemFocusNodes = {};

  // DPAD shortcuts for arrow key navigation
  static const Map<ShortcutActivator, Intent> _dpadShortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
    SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(TraversalDirection.right),
    SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(TraversalDirection.left),
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  };

  @override
  void initState() {
    super.initState();
    // Request focus IMMEDIATELY, not waiting for postFrameCallback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Force unfocus from anything else first
        FocusManager.instance.primaryFocus?.unfocus();
        // Then request focus on the first chip
        _realDebridChipFocusNode.requestFocus();

        // Double-check focus after a short delay (for race conditions)
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && !_realDebridChipFocusNode.hasFocus) {
            FocusManager.instance.primaryFocus?.unfocus();
            _realDebridChipFocusNode.requestFocus();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _realDebridController.dispose();
    _torboxController.dispose();
    _dialogFocusNode.dispose();
    _realDebridChipFocusNode.dispose();
    _torboxChipFocusNode.dispose();
    _skipButtonFocusNode.dispose();
    _continueButtonFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _openLinkButtonFocusNode.dispose();
    _textFieldFocusNode.dispose();
    _skipForNowButtonFocusNode.dispose();
    _connectButtonFocusNode.dispose();
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
    final mediaQuery = MediaQuery.of(context);
    final double keyboardInset = mediaQuery.viewInsets.bottom;
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
                    DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
                      onInvoke: (intent) {
                        FocusScope.of(innerContext).focusInDirection(intent.direction);
                        return null;
                      },
                    ),
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        // Find the focused widget and activate it
                        final focusedChild = FocusScope.of(innerContext).focusedChild;
                        if (focusedChild != null) {
                          final primaryFocus = FocusManager.instance.primaryFocus;
                          if (primaryFocus != null) {
                            // Trigger activation via Actions
                            Actions.maybeInvoke(primaryFocus.context!, const ActivateIntent());
                          }
                        }
                        return null;
                      },
                    ),
                  },
                  child: Dialog(
                    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    backgroundColor: Colors.transparent,
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints _) {
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          clipBehavior: Clip.none,
                          padding: EdgeInsets.only(bottom: keyboardInset > 0 ? keyboardInset : 0),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 560,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  gradient: const LinearGradient(
                                    colors: <Color>[Color(0xFF0F172A), Color(0xFF1F2937)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      blurRadius: 28,
                                      offset: const Offset(0, 24),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                                  child: LayoutBuilder(
                                    builder:
                                        (BuildContext context, BoxConstraints innerConstraints) {
                                      return AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 250),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        child: _stepIndex == 0
                                            ? _buildWelcomeStep(theme, innerConstraints.maxWidth)
                                            : _stepIndex > _flow.length
                                                ? _buildEngineSelectionStep(theme, innerConstraints.maxWidth)
                                                : _buildIntegrationStep(
                                                    theme,
                                                    _flow[_stepIndex - 1],
                                                    innerConstraints.maxWidth,
                                                  ),
                                      );
                                    },
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

  Widget _buildWelcomeStep(ThemeData theme, double availableWidth) {
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
        const SizedBox(height: 12),
        Text(
          'You can add others later from Settings.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 24),
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
                    : _torboxChipFocusNode;
                final order = meta.type == _IntegrationType.realDebrid ? 1.0 : 2.0;
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
                          Text(meta.title, style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 32),
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
                      onPressed:
                          _isProcessing ? null : () => Navigator.of(context).pop(false),
                      child: const Text("I don't have any yet"),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                    onPressed:
                        _isProcessing ? null : () => Navigator.of(context).pop(false),
                    child: const Text("I don't have any yet"),
                  ),
                ),
                const Spacer(),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(4),
                  child: FilledButton.icon(
                    focusNode: _continueButtonFocusNode,
                    onPressed:
                        _selection.isEmpty || _isProcessing ? null : _startIntegrationFlow,
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
  ) {
    final _IntegrationMeta meta = _integrationMeta[type]!;
    final TextEditingController controller =
        type == _IntegrationType.realDebrid ? _realDebridController : _torboxController;
    final int currentStep = _stepIndex;
    final int totalSteps = _flow.length;

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
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white60),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      meta.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const SizedBox(height: 4),
                    Text(
                      'Paste your API key below to connect.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Where to find the API key',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int i = 0; i < meta.steps.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == meta.steps.length - 1 ? 0 : 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: meta.gradient.first.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            meta.steps[i],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: OutlinedButton.icon(
                    focusNode: _openLinkButtonFocusNode,
                    onPressed: _isProcessing ? null : () => _launch(meta.url),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(meta.linkLabel),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: _TvFriendlyTextField(
            controller: controller,
            focusNode: _textFieldFocusNode,
            enabled: !_isProcessing,
            labelText: meta.inputLabel,
            hintText: meta.hint,
            prefixIcon: Icon(meta.icon),
            errorText: _errorMessage,
            onSubmitted: (_) {
              if (_isProcessing) return;
              _submitCurrent();
            },
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : availableWidth;
            final bool isCompact = width < 420;
            final Widget primaryButton = FocusTraversalOrder(
              order: const NumericFocusOrder(6),
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
              order: const NumericFocusOrder(5),
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
                  const SizedBox(height: 12),
                  primaryButton,
                ],
              );
            }

            return Row(
              children: <Widget>[
                skipButton,
                const Spacer(),
                primaryButton,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildEngineSelectionStep(ThemeData theme, double availableWidth) {
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
        const SizedBox(height: 12),
        Text(
          'Select the torrent search engines you want to use.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 24),
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
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
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
                      label: const Text('Retry', style: TextStyle(color: Colors.white)),
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
            constraints: const BoxConstraints(maxHeight: 280),
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
                              fillColor: WidgetStateProperty.resolveWith((states) {
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
        const SizedBox(height: 24),
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
    ];

    if (ordered.isEmpty) return;

    setState(() {
      _flow = ordered;
      _stepIndex = 1;
      _errorMessage = null;
    });
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
  }

  void _skipCurrent() {
    setState(() {
      _errorMessage = null;
    });
    _advanceOrFinish();
  }

  Future<void> _submitCurrent() async {
    final _IntegrationType current = _flow[_stepIndex - 1];
    final TextEditingController controller =
        current == _IntegrationType.realDebrid ? _realDebridController : _torboxController;
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
    } catch (_) {
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
        _errorMessage = 'That key did not work. Double-check it and try again.';
      });
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
  }

  void _goToEngineSelection() {
    setState(() {
      _stepIndex = _flow.length + 1;
      _isLoadingEngines = true;
      _engineError = null;
    });
    _loadAvailableEngines();
  }

  Future<void> _loadAvailableEngines() async {
    try {
      final engines = await _remoteEngineManager.fetchAvailableEngines();
      if (mounted) {
        // Clean up old focus nodes
        for (final node in _engineItemFocusNodes.values) {
          node.dispose();
        }
        _engineItemFocusNodes.clear();

        // Create focus nodes for each engine
        for (final engine in engines) {
          _engineItemFocusNodes[engine.id] = FocusNode(debugLabel: 'engine-${engine.id}');
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
      }
    } catch (e) {
      if (mounted) {
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
  }

  Future<void> _importSelectedEngines() async {
    if (_selectedEngineIds.isEmpty) {
      // Skip if no engines selected
      Navigator.of(context).pop(_hasConfigured);
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    final localStorage = LocalEngineStorage.instance;
    int successCount = 0;

    for (final engine in _availableEngines) {
      if (!_selectedEngineIds.contains(engine.id)) continue;

      try {
        final yamlContent = await _remoteEngineManager.downloadEngineYaml(engine.fileName);
        if (yamlContent != null) {
          await localStorage.saveEngine(
            engineId: engine.id,
            fileName: engine.fileName,
            yamlContent: yamlContent,
            displayName: engine.displayName,
            icon: engine.icon,
          );
          successCount++;
        }
      } catch (e) {
        debugPrint('Failed to import ${engine.id}: $e');
      }
    }

    // Reload engine registry
    ConfigLoader().clearCache();
    await EngineRegistry.instance.reload();

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
      Navigator.of(context).pop(_hasConfigured || successCount > 0);
    }
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
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
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
    widget.focusNode?.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_handleFocusChange);
    super.dispose();
  }

  @override
  void didUpdateWidget(_FocusableEngineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
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
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    this.errorText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String labelText;
  final String hintText;
  final Widget prefixIcon;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_TvFriendlyTextField> createState() => _TvFriendlyTextFieldState();
}

class _TvFriendlyTextFieldState extends State<_TvFriendlyTextField> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
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

    final key = event.logicalKey;
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;

    // Check if selection is valid
    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart = !isSelectionValid || (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd = !isSelectionValid || (selection.baseOffset == textLength && selection.extentOffset == textLength);

    // Allow escape from TextField with back button (escape key)
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      final ctx = node.context;
      if (ctx != null) {
        FocusScope.of(ctx).previousFocus();
        return KeyEventResult.handled;
      }
    }

    // Navigate up: always allow if text is empty or cursor at start
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        final ctx = node.context;
        if (ctx != null) {
          // Use directional focus to go to element above
          FocusScope.of(ctx).focusInDirection(TraversalDirection.up);
          return KeyEventResult.handled;
        }
      }
    }

    // Navigate down: always allow if text is empty or cursor at end
    if (key == LogicalKeyboardKey.arrowDown) {
      if (isTextEmpty || isAtEnd) {
        final ctx = node.context;
        if (ctx != null) {
          // Use directional focus to go to element below
          FocusScope.of(ctx).focusInDirection(TraversalDirection.down);
          return KeyEventResult.handled;
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
          border: _isFocused
              ? Border.all(color: Colors.white, width: 2)
              : null,
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
          obscureText: false,
          autofillHints: const <String>[AutofillHints.password],
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            prefixIcon: widget.prefixIcon,
            errorText: widget.errorText,
          ),
          onSubmitted: widget.onSubmitted,
        ),
      ),
    );
  }
}
