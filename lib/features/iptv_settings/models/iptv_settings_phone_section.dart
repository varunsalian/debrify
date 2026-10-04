/// The narrow (phone / small-window) layout's destinations. The wide layout
/// keeps its rail + pane; this is the phone-native equivalent — a hub page of
/// section rows, each opening a focused sub-view inside the SAME route (back
/// returns to the hub via PopScope, so section state and the add-form
/// controllers survive the trip).
enum IptvSettingsPhoneSection {
  hub,
  sources,
  lists,
  categoryOrder,
  hidden,
  startup,
  channelPreview,
  continueWatching,
  recording,
}
