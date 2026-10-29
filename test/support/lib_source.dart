import 'dart:io';

/// Plain reads of the current `lib/` sources for source guards.
///
/// No move manifests, ledgers or historical text: a guard sees exactly the
/// code that ships. Lookups that cannot be resolved unambiguously throw, so a
/// renamed or relocated declaration fails loudly instead of passing vacuously.

/// The text of one `lib/` file.
String libFile(String path) => File(path).readAsStringSync();

/// Every `.dart` file under [directory], sorted by path.
List<String> libDartFiles(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) {
    throw StateError('Missing source directory: $directory');
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path.replaceAll(r'\', '/'))
      .where((path) => path.endsWith('.dart'))
      .toList()
    ..sort();
}

/// [files] plus every `.dart` file under each of [directories], in order.
List<String> libSourceSet({
  List<String> files = const [],
  List<String> directories = const [],
}) => [
  ...files,
  for (final directory in directories) ...libDartFiles(directory),
];

/// The joined text of [paths].
String libJoined(Iterable<String> paths) => paths.map(libFile).join('\n');

/// The complete current text of member [member] declared directly inside
/// class/mixin/extension [owner] of [path], or of a top-level declaration
/// when [owner] is null. Preceding doc comments and annotations are included.
String libMember(String path, String member, {String? owner}) {
  final lines = libFile(path).split('\n');
  var first = 0;
  var last = lines.length;
  var indent = 0;
  if (owner != null) {
    const kinds =
        r'^(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*'
        r'(?:class|mixin|extension(?:\s+type)?)\s+';
    final header = RegExp('$kinds${RegExp.escape(owner)}\\b');
    final starts = [
      for (var i = 0; i < lines.length; i++)
        if (header.hasMatch(lines[i])) i,
    ];
    if (starts.length != 1) {
      throw StateError('Expected one owner $owner in $path, found $starts');
    }
    first = starts.single + 1;
    last = lines.indexOf('}', first);
    if (last < 0) throw StateError('Unterminated owner $owner in $path');
    indent = 2;
  }
  final pad = ' ' * indent;
  final name = RegExp(
    r'(?:^|[\s>?,(])(?:(?:get|set|operator)\s+)?' +
        RegExp.escape(member) +
        r'\s*(?:<[^=;]*>\s*)?(?:\(|=>|\{|$)',
  );
  final headers = <int>[];
  for (var i = first; i < last; i++) {
    final line = lines[i];
    if (!line.startsWith(pad) || line.startsWith('$pad ')) continue;
    final code = line.substring(indent);
    if (code.startsWith('//') || code.startsWith('@')) continue;
    final declared = name.firstMatch(code);
    if (declared == null) continue;
    // A field initializer or call at member level is not this declaration.
    final before = code.substring(0, declared.start);
    if (before.contains('=') || before.contains('.')) continue;
    headers.add(i);
  }
  if (headers.length != 1) {
    throw StateError(
      'Expected one declaration of ${owner ?? '<top level>'}.$member in '
      '$path, found lines ${headers.map((i) => i + 1).toList()}',
    );
  }
  var start = headers.single;
  while (start > first) {
    final previous = lines[start - 1];
    final code = previous.trimLeft();
    if (previous.length - code.length != indent) break;
    if (!code.startsWith('///') && !code.startsWith('@')) break;
    start--;
  }
  final end = _declarationEnd(lines, headers.single, indent, last);
  // Like an AST node's source: no indentation before the first token.
  return lines.sublist(start, end + 1).join('\n').trimLeft();
}

/// Index of the last line of the declaration starting at [header]: the
/// formatter closes a member body with `}` (or a parameter list with `)`) at
/// the header's own indentation, and a nested line is always deeper.
int _declarationEnd(List<String> lines, int header, int indent, int limit) {
  final pad = ' ' * indent;
  if (_endsDeclaration(lines[header])) return header;
  var previous = header;
  for (var i = header + 1; i < limit; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    if (line.startsWith('$pad ')) {
      previous = i;
      continue;
    }
    if (line.startsWith(RegExp('$pad[})\\]]'))) {
      // `}) async {` or `) {` closes a parameter list and opens the body.
      if (RegExp(r'(?:[{(\[,]|=>)$').hasMatch(line.trimRight())) {
        previous = i;
        continue;
      }
      return i;
    }
    // A multi-line `=>` body ends on its deeper `;` line.
    if (lines[previous].trimRight().endsWith(';')) return previous;
    throw StateError('Declaration at line ${header + 1} has no closing line');
  }
  if (lines[previous].trimRight().endsWith(';')) return previous;
  throw StateError('Declaration at line ${header + 1} is unterminated');
}

bool _endsDeclaration(String line) {
  final code = line.replaceFirst(RegExp(r'\s*//.*$'), '').trimRight();
  if (code.endsWith(';')) return true;
  // A complete one-line block body such as `void f() {}`.
  return code.endsWith('}') &&
      '{'.allMatches(code).length == '}'.allMatches(code).length &&
      code.contains('{');
}
