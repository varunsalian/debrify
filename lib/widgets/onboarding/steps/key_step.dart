import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../theme/widgets/parallax_focus.dart';
import '../../tv_keyboard.dart';
import '../../tv_text_field.dart';
import '../key_codec.dart';
import '../onboarding_focus.dart';
import '../onboarding_models.dart';
import '../onboarding_stage.dart';
import '../tv_keyboard_slot.dart';

enum KeyValidationPhase { idle, validating, failed }

class KeyStep extends StatefulWidget {
  const KeyStep({
    super.key,
    required this.layout,
    required this.isTelevision,
    required this.focusController,
    required this.session,
    required this.meta,
    required this.index,
    required this.total,
    required this.controller,
    required this.pikpakPasswordController,
    required this.phase,
    required this.onChanged,
    required this.onConnect,
    required this.onSkip,
    required this.onImport,
    this.clipboardCandidate,
    this.error,
  });

  final OnboardLayout layout;
  final bool isTelevision;
  final OnboardFocusController focusController;
  final TvKeyboardSession session;
  final IntegrationMeta meta;
  final int index;
  final int total;
  final TextEditingController controller;
  final TextEditingController pikpakPasswordController;
  final KeyValidationPhase phase;
  final ValueChanged<String> onChanged;
  final VoidCallback onConnect;
  final VoidCallback onSkip;
  final VoidCallback onImport;
  final String? clipboardCandidate;
  final String? error;

  Widget buildFooter(BuildContext context) {
    final validating = phase == KeyValidationPhase.validating;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OnboardFocusable(
          controller: focusController,
          cell: const OnboardCell(2, 0),
          onActivate: onSkip,
          enabled: !validating,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(18),
          semanticLabel: 'Skip this service',
          builder: (context, focused) => OnboardPillSurface(
            focused: focused,
            label: 'Skip',
            enabled: !validating,
          ),
        ),
        const SizedBox(width: 10),
        OnboardFocusable(
          controller: focusController,
          cell: const OnboardCell(2, 1),
          onActivate: onConnect,
          enabled: !validating,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(18),
          semanticLabel: 'Connect service',
          builder: (context, focused) => OnboardPillSurface(
            focused: focused,
            label: validating ? 'Checking…' : 'Connect',
            primary: true,
            enabled: !validating,
          ),
        ),
      ],
    );
  }

  @override
  State<KeyStep> createState() => _KeyStepState();
}

class _KeyStepState extends State<KeyStep> {
  final GlobalKey<TvTextFieldState> _fieldKey = GlobalKey<TvTextFieldState>();
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'onboarding-key-field');
  final FocusNode _passwordFocus = FocusNode(
    debugLabel: 'onboarding-pikpak-password',
  );
  FocusNode? _validationReturnFocus;

  bool get _isPikPak => widget.meta.type == IntegrationType.pikpak;
  bool get _validating => widget.phase == KeyValidationPhase.validating;
  OnboardCell get _fieldCell => OnboardCell(widget.isTelevision ? 2 : 1, 0);
  OnboardCell get _passwordCell => const OnboardCell(3, 0);

  @override
  void initState() {
    super.initState();
    widget.focusController.register(_fieldCell, _fieldFocus);
    if (widget.isTelevision) {
      widget.focusController.register(_passwordCell, _passwordFocus);
    }
    _updateLanding();
  }

  @override
  void didUpdateWidget(KeyStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final startedValidating =
        oldWidget.phase != KeyValidationPhase.validating &&
        widget.phase == KeyValidationPhase.validating;
    final finishedValidating =
        oldWidget.phase == KeyValidationPhase.validating &&
        widget.phase != KeyValidationPhase.validating;
    if (widget.isTelevision && startedValidating) {
      _validationReturnFocus = _passwordFocus.hasFocus
          ? _passwordFocus
          : _fieldFocus.hasFocus
          ? _fieldFocus
          : null;
    }
    if (finishedValidating) {
      final returnFocus = _validationReturnFocus;
      _validationReturnFocus = null;
      if (widget.isTelevision && widget.phase == KeyValidationPhase.failed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _validating) return;
          (returnFocus ?? _fieldFocus).requestFocus();
        });
      }
    }
    final oldFieldCell = OnboardCell(oldWidget.isTelevision ? 2 : 1, 0);
    if (oldWidget.focusController != widget.focusController ||
        oldWidget.isTelevision != widget.isTelevision) {
      oldWidget.focusController.unregister(oldFieldCell, _fieldFocus);
      if (oldWidget.isTelevision) {
        oldWidget.focusController.unregister(_passwordCell, _passwordFocus);
      }
      widget.focusController.register(_fieldCell, _fieldFocus);
      if (widget.isTelevision) {
        widget.focusController.register(_passwordCell, _passwordFocus);
      }
    }
    _updateLanding();
  }

  void _updateLanding() {
    widget.focusController.setLandingOverride(
      widget.clipboardCandidate != null ? const OnboardCell(0, 1) : _fieldCell,
    );
  }

  void _paste() {
    if (_validating) return;
    final value = widget.clipboardCandidate;
    if (value == null || value.isEmpty) return;
    _fieldKey.currentState?.insertText(value);
    _fieldFocus.requestFocus();
  }

  Future<void> _openProviderPage() async {
    if (_validating) return;
    try {
      final opened = await launchUrl(
        Uri.parse(widget.meta.url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not open that page.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not open that page.')),
      );
    }
  }

  void _focusBack(OnboardCell source) {
    if (_validating) return;
    widget.focusController.move(source, TraversalDirection.left);
  }

  @override
  void dispose() {
    widget.focusController.unregister(_fieldCell, _fieldFocus);
    if (widget.isTelevision) {
      widget.focusController.unregister(_passwordCell, _passwordFocus);
    }
    _fieldFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fieldBand = _buildFieldBand(context);
    if (!widget.isTelevision) {
      return ListView(
        key: const ValueKey('onboarding-field-band'),
        padding: const EdgeInsets.only(bottom: 16),
        children: [fieldBand],
      );
    }

    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return TvKeyboardSlot(
      session: widget.session,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            key: const ValueKey('onboarding-field-band'),
            child: Align(
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(child: fieldBand),
            ),
          ),
          Container(
            key: const ValueKey('onboarding-keyboard-band'),
            constraints: const BoxConstraints(minHeight: 275),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.035),
              border: Border(
                top: BorderSide(
                  color: scheme.onSurface.withValues(alpha: 0.07),
                ),
              ),
            ),
            child: ValueListenableBuilder<TvKeyboardController?>(
              valueListenable: widget.session.panel,
              builder: (context, controller, _) {
                if (controller == null) {
                  return Center(
                    child: Text(
                      'Press OK on the field to open the keyboard',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  );
                }
                return Center(
                  child: TvKeyboardPanel(
                    key: const ValueKey('onboarding-keyboard-panel'),
                    controller: controller,
                    accent: app.core.accent,
                    ground: app.core.pane,
                    ink: app.core.tx,
                    inkOnAccent: scheme.onPrimary,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldBand(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parsed = parseOnboardingKey(widget.controller.text);
    final length = parsed.key.length;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: widget.meta.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.meta.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.meta.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Service ${widget.index + 1} of ${widget.total} · ${widget.meta.url.replaceFirst('https://', '')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMethodChips(),
          const SizedBox(height: 12),
          if (_isPikPak) ...[
            _buildTextField(
              key: _fieldKey,
              controller: widget.controller,
              focusNode: _fieldFocus,
              cell: _fieldCell,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: 8),
            _buildTextField(
              controller: widget.pikpakPasswordController,
              focusNode: _passwordFocus,
              cell: _passwordCell,
              label: 'Password',
              hintText: 'Enter your PikPak password',
              obscureText: true,
              onSubmitted: (_) => widget.onConnect(),
            ),
          ] else
            _buildTextField(
              key: _fieldKey,
              controller: widget.controller,
              focusNode: _fieldFocus,
              cell: _fieldCell,
              label: widget.meta.inputLabel,
              formatters: const [OnboardingKeyFormatter()],
              onSubmitted: (_) => widget.onConnect(),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor(context),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _statusText(length),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: _statusColor(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMethodChips() {
    final firstRow = <Widget>[
      _MethodChip(
        controller: widget.focusController,
        cell: const OnboardCell(0, 0),
        icon: Icons.keyboard_rounded,
        label: 'Type it',
        selected: true,
        enabled: !_validating,
        onPressed: _fieldFocus.requestFocus,
      ),
      if (widget.clipboardCandidate != null)
        _MethodChip(
          controller: widget.focusController,
          cell: const OnboardCell(0, 1),
          icon: Icons.content_paste_rounded,
          label: 'Paste',
          enabled: !_validating,
          onPressed: _paste,
        ),
      _MethodChip(
        controller: widget.focusController,
        cell: OnboardCell(0, widget.clipboardCandidate != null ? 2 : 1),
        icon: Icons.devices_rounded,
        label: 'Send everything from another device',
        enabled: !_validating,
        onPressed: widget.onImport,
      ),
    ];
    final openPage = _MethodChip(
      controller: widget.focusController,
      cell: widget.isTelevision
          ? const OnboardCell(1, 0)
          : OnboardCell(0, widget.clipboardCandidate != null ? 3 : 2),
      icon: Icons.open_in_new_rounded,
      label: widget.meta.linkLabel,
      enabled: !_validating,
      onPressed: () => unawaited(_openProviderPage()),
    );

    if (!widget.isTelevision) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[...firstRow, openPage],
      );
    }

    // The approved TV width wraps the final two methods. Give that visual row
    // matching DPAD coordinates instead of pretending every chip is on row 0.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: firstRow),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            openPage,
            _MethodChip(
              controller: widget.focusController,
              cell: const OnboardCell(1, 1),
              icon: Icons.skip_next_rounded,
              label: 'Skip for now',
              enabled: !_validating,
              onPressed: widget.onSkip,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    Key? key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required OnboardCell cell,
    required String label,
    String? hintText,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    ValueChanged<String>? onSubmitted,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TvTextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      enabled: !_validating,
      keyboardSubmitLabel: _isPikPak && identical(controller, widget.controller)
          ? 'Next'
          : 'Connect',
      keyboardType: keyboardType,
      textInputAction: _isPikPak && identical(controller, widget.controller)
          ? TextInputAction.next
          : TextInputAction.done,
      obscureText: obscureText,
      inputFormatters: formatters,
      onChanged: widget.onChanged,
      onSubmitted: onSubmitted,
      onLeftArrow: () => _focusBack(cell),
      onUpArrow: () => widget.focusController.move(cell, TraversalDirection.up),
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 19,
        letterSpacing: obscureText ? 1 : 2.5,
        color: scheme.onSurface,
      ),
      cursorColor: scheme.onSurface,
      shellRing: false,
      accent: scheme.primary,
      keyboardGround: AppThemeScope.of(context).core.pane,
      keyboardInk: scheme.onSurface,
      keyboardInkOnAccent: scheme.onPrimary,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText ?? widget.meta.hint,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.30),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 17,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  String _statusText(int length) {
    if (widget.phase == KeyValidationPhase.validating) {
      return 'Checking with ${widget.meta.title}…';
    }
    if (widget.phase == KeyValidationPhase.failed) {
      return widget.error ??
          "That key didn't work — check for a missing character";
    }
    if (_isPikPak) {
      return widget.controller.text.isEmpty
          ? 'Nothing entered yet'
          : 'Press Connect';
    }
    if (length == 0) return 'Nothing entered yet';
    final expected = widget.meta.keyLength;
    if (expected != null && length < expected) return '$length of $expected';
    if (expected == null && length > 0) return '$length characters';
    return 'Press Connect';
  }

  Color _statusColor(BuildContext context) {
    return switch (widget.phase) {
      KeyValidationPhase.validating => const Color(0xFFFBBF24),
      KeyValidationPhase.failed => const Color(0xFFF87171),
      KeyValidationPhase.idle => Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.55),
    };
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.controller,
    required this.cell,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
  });

  final OnboardFocusController controller;
  final OnboardCell cell;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OnboardFocusable(
      controller: controller,
      cell: cell,
      onActivate: onPressed,
      enabled: enabled,
      shape: ParallaxShape.pill,
      radius: BorderRadius.circular(18),
      semanticLabel: label,
      builder: (context, focused) => OnboardPillSurface(
        focused: focused,
        label: label,
        icon: icon,
        primary: selected,
        enabled: enabled,
      ),
    );
  }
}
