/// Effective source-row labels; storage owns the shipped preference defaults.
typedef SourceAppearance = ({bool text, bool logos});
typedef SourceAppearanceReader = Future<SourceAppearance> Function();
const initialSourceAppearance = (text: false, logos: false);
