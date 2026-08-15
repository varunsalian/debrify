import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/profiles/dev/profile_audit_report.dart';
import '../../../services/profiles/profile_preferences.dart';
import '../../../services/profiles/profile_registry.dart';

/// DEV-ONLY. Browses what each profile actually holds, and compares two.
///
/// Renders [ProfileAuditReport] — the same structure that gets pasted to a
/// reviewer — so what is on screen and what leaves the device can never drift.
/// Values are hashes here for the same reason they are hashes there.
///
/// Delete with `lib/screens/profiles/dev/`, plus its row in
/// `ManageProfilesScreen`.
class ProfileDataScreen extends StatefulWidget {
  const ProfileDataScreen({
    super.key,
    required this.registry,
    this.debugCollect,
  });

  final ProfileRegistry registry;

  /// Test seam. [ProfileAuditReport.collect] walks directories and opens
  /// databases, and real file IO never completes under the widget tester's
  /// fake clock — `pumpAndSettle` just times out. Widget tests inject a
  /// fixture and let `profile_audit_report_test.dart`, a plain unit test with
  /// real IO, cover the collection itself.
  final Future<Map<String, Object?>> Function()? debugCollect;

  @override
  State<ProfileDataScreen> createState() => _ProfileDataScreenState();
}

class _ProfileDataScreenState extends State<ProfileDataScreen> {
  Map<String, Object?>? _report;
  String? _error;
  String _selected = '';
  String _compareWith = '';
  String _filter = '';
  bool _comparing = false;

  /// Live values for the ACTIVE profile, fetched only when asked for.
  ///
  /// Deliberately not part of the report: that structure gets pasted to other
  /// people, so it must never hold a value. Reading them here instead keeps
  /// "browse my own data on my own device" useful without making the exported
  /// artifact dangerous — and only the active profile is ever opened, so this
  /// screen never becomes a cross-profile secret viewer.
  Map<String, String>? _revealed;
  bool _revealing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _report = null;
      _error = null;
    });
    try {
      final report =
          await (widget.debugCollect?.call() ??
              ProfileAuditReport.collect(widget.registry));
      if (!mounted) return;
      final aliases = _aliases(report);
      setState(() {
        _report = report;
        _selected = aliases.isEmpty ? '' : aliases.first;
        _compareWith = aliases.length > 1 ? aliases[1] : '';
      });
    } catch (error, stack) {
      debugPrint('ProfileDataScreen: collect failed: $error\n$stack');
      if (!mounted) return;
      // A diagnostic that shows a spinner forever is worse than none.
      setState(() => _error = '$error');
    }
  }

  List<String> _aliases(Map<String, Object?> report) => [
    ...((report['preferences'] as Map<String, Object?>?) ??
            const <String, Object?>{})
        .keys,
    _deviceAlias,
  ];

  static const String _deviceAlias = 'device';

  List<Map<String, Object?>> _rowsFor(String alias) {
    final report = _report;
    if (report == null) return const [];
    final rows = alias == _deviceAlias
        ? (report['devicePreferences'] as List?) ?? const []
        : ((report['preferences'] as Map<String, Object?>?)?[alias] as List?) ??
              const [];
    final all = rows.cast<Map<String, Object?>>();
    if (_filter.isEmpty) return all;
    final needle = _filter.toLowerCase();
    return all
        .where((row) => (row['key']! as String).toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile data'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: report == null ? null : () => _copy(report),
          ),
          IconButton(
            tooltip: 'Re-scan',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _error != null
          ? _buildError(context)
          : report == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context, report),
    );
  }

  Widget _buildError(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            autofocus: true,
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  Widget _buildBody(BuildContext context, Map<String, Object?> report) {
    final findings = ((report['findings'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        _ScopeBanner(report: report),
        if (findings.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          ...findings.map((finding) => _FindingTile(finding: finding)),
        ],
        const SizedBox(height: 12),
        _buildPicker(context, report),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Filter keys',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _filter = value.trim()),
        ),
        const SizedBox(height: 12),
        if (_comparing) ..._buildCompare(context) else ..._buildBrowse(context),
      ],
    );
  }

  Widget _buildPicker(BuildContext context, Map<String, Object?> report) {
    final aliases = _aliases(report);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final alias in aliases)
              ChoiceChip(
                label: Text(alias),
                selected: _selected == alias,
                onSelected: (_) => setState(() => _selected = alias),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Switch(
              value: _comparing,
              onChanged: aliases.length < 2
                  ? null
                  : (value) => setState(() => _comparing = value),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Compare with')),
            if (_comparing)
              DropdownButton<String>(
                value: aliases.contains(_compareWith) ? _compareWith : null,
                items: <DropdownMenuItem<String>>[
                  for (final alias in aliases.where((a) => a != _selected))
                    DropdownMenuItem<String>(value: alias, child: Text(alias)),
                ],
                onChanged: (value) =>
                    setState(() => _compareWith = value ?? _compareWith),
              ),
          ],
        ),
      ],
    );
  }

  /// The alias of the profile whose data this process is actually running on.
  /// Only that one can be revealed — the others are inventoried, never opened.
  String get _activeAlias =>
      ((_report?['runtime'] as Map<String, Object?>?)?['activeProfile']
          as String?) ??
      '';

  Future<void> _toggleReveal() async {
    if (_revealed != null) {
      setState(() => _revealed = null);
      return;
    }
    setState(() => _revealing = true);
    try {
      final prefs = await ProfilePreferences.instance();
      final values = <String, String>{
        for (final key in prefs.getKeys()) key: '${prefs.get(key)}',
      };
      if (!mounted) return;
      setState(() {
        _revealed = values;
        _revealing = false;
      });
    } catch (error) {
      debugPrint('ProfileDataScreen: reveal failed: $error');
      if (!mounted) return;
      setState(() => _revealing = false);
    }
  }

  List<Widget> _buildBrowse(BuildContext context) {
    final rows = _rowsFor(_selected);
    final canReveal = _selected == _activeAlias && _selected.isNotEmpty;
    final header = Row(
      children: <Widget>[
        Text(
          '${rows.length} keys',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const Spacer(),
        if (canReveal)
          TextButton.icon(
            onPressed: _revealing ? null : _toggleReveal,
            icon: Icon(
              _revealed == null
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
            ),
            label: Text(_revealed == null ? 'Reveal values' : 'Hide values'),
          ),
      ],
    );
    if (rows.isEmpty) {
      return <Widget>[header, const _Empty(message: 'No keys match.')];
    }
    return <Widget>[
      header,
      const SizedBox(height: 6),
      for (final row in rows) _KeyTile(row: row, value: _revealed?[row['key']]),
    ];
  }

  List<Widget> _buildCompare(BuildContext context) {
    final left = <String, Map<String, Object?>>{
      for (final row in _rowsFor(_selected)) row['key']! as String: row,
    };
    final right = <String, Map<String, Object?>>{
      for (final row in _rowsFor(_compareWith)) row['key']! as String: row,
    };
    final keys = <String>{...left.keys, ...right.keys}.toList()..sort();

    final identical = <String>[];
    final differs = <String>[];
    final onlyOne = <String>[];
    for (final key in keys) {
      final a = left[key];
      final b = right[key];
      if (a == null || b == null) {
        onlyOne.add(key);
      } else if (a['hash'] == b['hash']) {
        identical.add(key);
      } else {
        differs.add(key);
      }
    }

    Widget bucket(String title, List<String> bucketKeys, Color? tint) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 12),
        Text(
          '$title · ${bucketKeys.length}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        for (final key in bucketKeys)
          _CompareTile(
            keyName: key,
            left: left[key],
            right: right[key],
            leftLabel: _selected,
            rightLabel: _compareWith,
            tint: tint,
          ),
      ],
    );

    return <Widget>[
      // Identical first: a shared value is the shape almost every isolation
      // bug takes. Sealed values are excluded upstream — AES-GCM re-nonces, so
      // two profiles holding the same secret never collide.
      bucket(
        'Same value in both',
        identical,
        Theme.of(context).colorScheme.tertiaryContainer,
      ),
      bucket(
        'Only in one',
        onlyOne,
        Theme.of(context).colorScheme.errorContainer,
      ),
      bucket('Differs', differs, null),
    ];
  }

  Future<void> _copy(Map<String, Object?> report) async {
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(report)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied — no values are included')),
    );
  }
}

class _ScopeBanner extends StatelessWidget {
  const _ScopeBanner({required this.report});

  final Map<String, Object?> report;

  @override
  Widget build(BuildContext context) {
    final runtime =
        (report['runtime'] as Map<String, Object?>?) ??
        const <String, Object?>{};
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text('${runtime['activeProfile'] ?? runtime['mode']}'),
        subtitle: Text(
          '${runtime['activeScope'] ?? runtime['mode']}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});

  final Map<String, Object?> finding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 6),
      color: scheme.errorContainer,
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.report_problem_outlined,
          color: scheme.onErrorContainer,
        ),
        title: Text(
          '${finding['id']}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: scheme.onErrorContainer,
          ),
        ),
        subtitle: Text(
          '${finding['detail']}',
          style: TextStyle(color: scheme.onErrorContainer),
        ),
      ),
    );
  }
}

class _KeyTile extends StatelessWidget {
  const _KeyTile({required this.row, this.value});

  final Map<String, Object?> row;

  /// The live value, present only while Reveal is on for the active profile.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final sealed = row['sealed'] == true;
    final count = row['count'];
    final shown = value;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${row['key']}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            <String>[
              '${row['type']}',
              if (row['bytes'] != null) '${row['bytes']} B',
              if (count != null) '$count entries',
              '#${row['hash']}',
              if (sealed) 'sealed',
            ].join('  ·  '),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
          ),
          if (shown != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                shown,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompareTile extends StatelessWidget {
  const _CompareTile({
    required this.keyName,
    required this.left,
    required this.right,
    required this.leftLabel,
    required this.rightLabel,
    required this.tint,
  });

  final String keyName;
  final Map<String, Object?>? left;
  final Map<String, Object?>? right;
  final String leftLabel;
  final String rightLabel;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    String side(Map<String, Object?>? row) =>
        row == null ? '— not set —' : '${row['type']} · #${row['hash']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            keyName,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          // Stacked rather than two columns: this has to stay readable in a
          // phone-width dialog and on a TV, and a two-column table does not.
          Text(
            '$leftLabel: ${side(left)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
          ),
          Text(
            '$rightLabel: ${side(right)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(child: Text(message)),
  );
}
