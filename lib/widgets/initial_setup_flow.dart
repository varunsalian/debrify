import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/account_service.dart';
import '../services/main_page_bridge.dart';
import '../services/torbox_account_service.dart';

class InitialSetupFlow extends StatefulWidget {
  const InitialSetupFlow({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => const InitialSetupFlow(),
    );
    return result ?? false;
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
  int _stepIndex = 0; // 0 => welcome, >0 => selected integrations
  List<_IntegrationType> _flow = const <_IntegrationType>[];
  bool _isProcessing = false;
  String? _errorMessage;
  bool _hasConfigured = false;

  @override
  void dispose() {
    _realDebridController.dispose();
    _torboxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final double keyboardInset = mediaQuery.viewInsets.bottom;
    return WillPopScope(
      onWillPop: () async => false,
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
                return SizedBox(
                  width: isNarrow ? width : (width - 16) / 2,
                  child: FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(meta.icon, size: 18),
                        const SizedBox(width: 8),
                        Text(meta.title),
                      ],
                    ),
                    selected: _selection.contains(meta.type),
                    onSelected: (_) => _toggleSelection(meta.type),
                    showCheckmark: false,
                    selectedColor: Colors.white.withValues(alpha: 0.2),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    labelStyle: const TextStyle(color: Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: _selection.contains(meta.type)
                            ? Colors.white.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  TextButton(
                    onPressed:
                        _isProcessing ? null : () => Navigator.of(context).pop(false),
                    child: const Text("I don't have any yet"),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _selection.isEmpty || _isProcessing
                        ? null
                        : _startIntegrationFlow,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Continue'),
                  ),
                ],
              );
            }
            return Row(
              children: <Widget>[
                TextButton(
                  onPressed:
                      _isProcessing ? null : () => Navigator.of(context).pop(false),
                  child: const Text("I don't have any yet"),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      _selection.isEmpty || _isProcessing ? null : _startIntegrationFlow,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Continue'),
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
            IconButton(
              onPressed: _isProcessing ? null : _goBack,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
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
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _launch(meta.url),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(meta.linkLabel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controller,
          enabled: !_isProcessing,
          obscureText: false,
          autofillHints: const <String>[AutofillHints.password],
          decoration: InputDecoration(
            labelText: meta.inputLabel,
            hintText: meta.hint,
            prefixIcon: Icon(meta.icon),
            errorText: _errorMessage,
          ),
          onSubmitted: (_) {
            if (_isProcessing) return;
            _submitCurrent();
          },
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : availableWidth;
            final bool isCompact = width < 420;
            final Widget primaryButton = FilledButton(
              onPressed: _isProcessing ? null : _submitCurrent,
              child: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Connect ${meta.title}'),
            );
            final Widget skipButton = TextButton(
              onPressed: _isProcessing ? null : _skipCurrent,
              child: const Text('Skip for now'),
            );
            final Widget backButton = TextButton(
              onPressed: _isProcessing ? null : _goBack,
              child: const Text('Back'),
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[backButton, skipButton],
                  ),
                  const SizedBox(height: 12),
                  primaryButton,
                ],
              );
            }

            return Row(
              children: <Widget>[
                backButton,
                const SizedBox(width: 8),
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
      Navigator.of(context).pop(_hasConfigured);
      return;
    }

    setState(() {
      _stepIndex += 1;
      _errorMessage = null;
    });
  }

  Future<void> _launch(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
