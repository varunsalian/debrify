// Bound to the main State declaration and its owning lifecycle method. Only
// whitespace and one optional formatter comma are accepted at the call site.
bool catalogCompletionListenerSite(
  String source,
  String declaration,
  String notifier,
  String operation,
) {
  final stateStart = source.indexOf('class _CatalogItemDetailScreenState ');
  if (stateStart < 0) return false;
  final tail = source.substring(stateStart);
  final stateEnd = RegExp(r'^}', multiLine: true).firstMatch(tail);
  if (stateEnd == null) return false;
  final state = tail.substring(0, stateEnd.end);
  final start = RegExp(
    r'^  void ' + RegExp.escape(declaration) + r'\(\)\s*\{',
    multiLine: true,
  ).firstMatch(state);
  if (start == null) return false;
  final end = RegExp(
    r'^  }',
    multiLine: true,
  ).firstMatch(state.substring(start.end));
  if (end == null) return false;
  final body = state.substring(start.start, start.end + end.end);
  final expression = notifier.split('.').map(RegExp.escape).join(r'\s*\.\s*');
  return RegExp(
    r'^\s*' +
        expression +
        r'\s*\.\s*' +
        RegExp.escape(operation) +
        r'\s*\(\s*_loadLocalMovieFinished\s*,?\s*\)',
    multiLine: true,
  ).hasMatch(body);
}
