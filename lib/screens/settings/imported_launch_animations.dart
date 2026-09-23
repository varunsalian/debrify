import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/cache_scratch_cleanup.dart';

import '../../services/launch_animation/launch_animation_library.dart';
import '../../services/launch_animation/launch_package.dart';
import '../../services/storage_service.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../widgets/remote/remote_control_screen.dart';
import '../../widgets/remote/remote_pairing_dialog.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../theme/app_looks.dart';
import '../../utils/platform_util.dart';
import '../../widgets/launch/imported_launch_player.dart';
import 'widgets/settings_widgets.dart';

class ImportedLaunchAnimations extends StatefulWidget {
  const ImportedLaunchAnimations({super.key, required this.onSelectionChanged});
  final VoidCallback onSelectionChanged;
  @override
  State<ImportedLaunchAnimations> createState() =>
      _ImportedLaunchAnimationsState();
}

class _ImportedLaunchAnimationsState extends State<ImportedLaunchAnimations> {
  final _library = LaunchAnimationLibrary.instance;
  List<InstalledLaunchAnimation> _entries = [];
  Object? _error;
  bool _busy = false;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    _library.revision.addListener(_reload);
    unawaited(_load(clean: true));
  }

  @override
  void dispose() {
    _library.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() => unawaited(_load());
  Future<void> _load({bool clean = false}) async {
    final generation = ++_loadGeneration;
    try {
      final entries = await _library.list(clean: clean);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _entries = entries;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run(() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
    } on PlatformException catch (error) {
      // Android's picker reports this when no OPEN_DOCUMENT provider exists,
      // even with FileType.any. TV firmware often ships without one.
      if (PlatformUtil.isTelevision && error.code == 'invalid_format_type') {
        throw const LaunchImportException(
          'No file picker is available on this TV. Send the animation from a paired Debrify phone or computer using Send to TV.',
        );
      }
      rethrow;
    }
    if (result == null || result.files.isEmpty) return;
    final selected = result.files.single;
    try {
      if (selected.size > LaunchLimits.compressedBytes) {
        throw const LaunchImportException(
          'Animation files must be 10 MiB or smaller.',
        );
      }
      if (selected.path == null) {
        throw const LaunchImportException(
          'Copy the animation to local storage, then try again.',
        );
      }
      final file = File(selected.path!);
      final package = await _library.inspectFile(file);
      if (!mounted) return;
      var id = package.initialId;
      final pair = package.orientationPair;
      if (pair != null) {
        id = MediaQuery.orientationOf(context) == Orientation.portrait
            ? pair.portrait.id
            : pair.landscape.id;
      } else if (package.animations.length > 1) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Choose an animation'),
            children: [
              for (final animation in package.animations)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, animation.id),
                  child: Text(animation.name),
                ),
            ],
          ),
        );
        if (choice == null) return;
        id = choice;
      }
      final entry = await _library.install(file, animationId: id);
      if (mounted) await _preview(entry);
    } finally {
      await CacheScratchCleanup.releasePickerCopy(selected.path);
    }
  });
  Future<void> _preview(InstalledLaunchAnimation entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportedLaunchDetail(
          entry: entry,
          onSelectionChanged: widget.onSelectionChanged,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: 'Imported animations',
    children: [
      if (_busy) const LinearProgressIndicator(),
      if (!PlatformUtil.isTvOS)
        SettingsTile(
          icon: Icons.file_open_outlined,
          title: 'Import .lottie file',
          subtitle: 'Up to 5 seconds · 10 MiB · plays offline',
          onTap: () async {
            if (!_busy) unawaited(_import());
          },
        ),
      if (PlatformUtil.isTelevision)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'You can also send an animation from a paired Debrify phone or computer. Open its imported animation and choose Send to TV.',
          ),
        ),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(16), child: Text('$_error')),
      if (_error != null)
        SettingsTile(
          icon: Icons.refresh,
          title: 'Reset library index',
          subtitle:
              'Preserves the damaged index. You will need to import your animation files again.',
          onTap: () => _run(() async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Reset animation library?'),
                content: const Text(
                  'Installed animations will need to be imported again. Your built-in animations are unaffected.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            );
            if (confirmed == true) await _library.resetDamagedIndex();
          }),
        ),
      for (final entry in _entries)
        SettingsTile(
          icon: StorageService.importedLaunchAnimationCached == entry.id
              ? Icons.check_circle
              : Icons.animation,
          title: entry.name,
          subtitle: 'Preview, replay and choose',
          onTap: () async {
            if (!_busy) unawaited(_preview(entry));
          },
        ),
    ],
  );
}

class ImportedLaunchDetail extends StatefulWidget {
  const ImportedLaunchDetail({
    super.key,
    required this.entry,
    required this.onSelectionChanged,
  });
  final InstalledLaunchAnimation entry;
  final VoidCallback onSelectionChanged;
  @override
  State<ImportedLaunchDetail> createState() => _ImportedLaunchDetailState();
}

class _ImportedLaunchDetailState extends State<ImportedLaunchDetail> {
  final Set<String> _runtimeWarnings = {};
  bool? _portraitOverride;
  bool get _portrait =>
      _portraitOverride ??
      (MediaQuery.orientationOf(context) == Orientation.portrait);
  bool _ready = false;
  bool _saving = false;
  int _replay = 0;
  late int _background = widget.entry.background;
  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: widget.entry.name,
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: _portrait ? 420 : 480),
                  child: AspectRatio(
                    aspectRatio: _portrait ? 9 / 16 : 16 / 9,
                    child: ImportedAnimationPreview(
                      key: ValueKey(_replay),
                      id: widget.entry.id,
                      background: _background,
                      onWarning: (warning) {
                        if (mounted && !_runtimeWarnings.contains(warning)) {
                          setState(() => _runtimeWarnings.add(warning));
                        }
                      },
                      onReady: (ready) {
                        if (mounted) setState(() => _ready = ready);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _ready = false;
                      _replay++;
                    }),
                    child: const Text('Replay'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        setState(() => _portraitOverride = !_portrait),
                    child: Text(
                      _portrait ? 'Landscape preview' : 'Portrait preview',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : _send,
                    child: const Text('Send to TV'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _saving ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove animation'),
                  ),
                  FilledButton(
                    onPressed: !_ready || _saving ? null : _use,
                    child: Text(_saving ? 'Saving…' : 'Use animation'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Background'),
              Wrap(
                spacing: 10,
                children: [
                  for (final color in const [
                    0xff080b12,
                    0xff000000,
                    0xffffffff,
                    0xff102438,
                  ])
                    OutlinedButton(
                      onPressed: () => setState(() => _background = color),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _background == color
                                ? Icons.check_circle
                                : Icons.circle,
                            color: Color(color),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            color == 0xffffffff
                                ? 'White'
                                : color == 0xff000000
                                ? 'Black'
                                : color == 0xff080b12
                                ? 'Midnight'
                                : 'Navy',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Plays once, then holds its final frame while Home loads. Artwork is fitted without cropping. Imported colors do not follow the app theme.',
              ),
              for (final warning in {
                ...widget.entry.warnings,
                ..._runtimeWarnings,
              })
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(warning),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> _send() async {
    setState(() => _saving = true);
    try {
      final remote = RemoteControlState();
      if (!remote.isConnected || remote.isTv) {
        await remote.startMobileDiscovery();
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RemoteControlScreen()),
        );
      }
      final target = remote.connectedDevice;
      if (!mounted || target == null || !remote.isConnected) return;
      final session = await ensureAuthorizedSession(context, remote, target);
      if (!mounted || session == null || !session.authorized) return;
      final entry = InstalledLaunchAnimation(
        id: widget.entry.id,
        name: widget.entry.name,
        animationId: widget.entry.animationId,
        background: _background,
        warnings: widget.entry.warnings,
      );
      await remote.sendLaunchAnimation(target.ip, entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Imported on the receiving device. Preview and select it in Launch Animation settings.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _use() async {
    setState(() => _saving = true);
    final scope = ProfileRuntime.scope.value;
    try {
      LookApplier.noteExternalWrite('launch_animation');
      await LaunchAnimationLibrary.instance.setBackground(
        widget.entry.id,
        _background,
      );
      if (scope != ProfileRuntime.scope.value) {
        throw StateError('Profile changed. Select the animation again.');
      }
      await StorageService.setImportedLaunchAnimation(widget.entry.id);
      if (mounted) {
        widget.onSelectionChanged();
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${widget.entry.name}?'),
        content: const Text(
          'This removes the animation from this device. Profiles using it will use their built-in animation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await LaunchAnimationLibrary.instance.delete(widget.entry.id);
      await StorageService.clearImportedLaunchAnimationIf(widget.entry.id);
      if (mounted) {
        widget.onSelectionChanged();
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class ImportedAnimationPreview extends StatefulWidget {
  const ImportedAnimationPreview({
    super.key,
    required this.id,
    this.background,
    this.onReady,
    this.onWarning,
  });
  final String id;
  final int? background;
  final ValueChanged<bool>? onReady;
  final ValueChanged<String>? onWarning;
  @override
  State<ImportedAnimationPreview> createState() =>
      _ImportedAnimationPreviewState();
}

class _ImportedAnimationPreviewState extends State<ImportedAnimationPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  LoadedLaunchAnimation? _loaded;
  Object? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ImportedAnimationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _controller.stop();
    final old = _loaded;
    _loaded = null;
    _error = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    try {
      final loaded = await LaunchAnimationLibrary.instance.load(widget.id);
      if (!mounted || generation != _generation) {
        loaded.dispose();
        return;
      }
      setState(() => _loaded = loaded);
      _controller.duration = loaded.composition.duration;
      await _controller.forward(from: 0).orCancel;
      // Wait for the final paint, including a possible painter-error callback.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && generation == _generation && _error == null) {
        widget.onReady?.call(true);
      }
    } catch (error) {
      if (mounted && generation == _generation) _fail(error);
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    _controller.stop();
    setState(() => _error = error);
    widget.onReady?.call(false);
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    _loaded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Animation unavailable: $_error'),
        ),
      );
    }
    final loaded = _loaded;
    if (loaded == null) return const Center(child: CircularProgressIndicator());
    // A view wrapper shares the owner's composition; only the owner disposes it.
    final view =
        widget.background == null
              ? loaded
              : LoadedLaunchAnimation(
                  loaded.composition,
                  widget.background!,
                  loaded.warnings,
                )
          ..alternate = loaded.alternate;
    return ImportedLaunchPlayer(
      animation: view,
      progress: _controller,
      onError: _fail,
      onWarning: widget.onWarning,
    );
  }
}
