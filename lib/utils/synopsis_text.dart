/// True when [text] ends in an ellipsis because whoever supplied it cut it
/// short.
///
/// Cinemeta ships some series descriptions this way (MobLand's stops at
/// "…when opposing forces col..."), so showing the text in full still ends
/// mid-word. Callers prefer IMDb's plot then, which is the whole text.
bool synopsisLooksCut(String text) {
  final t = text.trimRight();
  return t.endsWith('...') || t.endsWith('…');
}
