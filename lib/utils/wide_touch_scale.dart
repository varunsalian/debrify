/// The wide-TOUCH type-and-control scale, shared by every surface that draws
/// the TV mock's 960-canvas absolutes on a touch screen.
///
/// A TV's logical width IS ~960 (the scaled surface), so fixed values tuned
/// there render at ~70% of their designed proportion on an iPad Pro's 1366pt
/// canvas. Scaling them by w/960 restores the mock's proportions, and because
/// the proportional values (`w * x/1920`) already track width, text and cards
/// grow together instead of drifting apart.
///
/// One function rather than a formula per metrics class: the 960 reference
/// and the 1.5 ceiling are design-tuning knobs, and retuning them must move
/// the Home Spotlight hero and the Showcase detail page as one.
///
/// Callers gate this to the wide TOUCH tier themselves (TV dpad and compact
/// phone stay at exactly 1.0 — their absolutes are shipped/hand-measured);
/// the clamp keeps a full-screen desktop window from overgrowing the type.
double wideTouchScale(double w) => (w / 960).clamp(1.0, 1.5).toDouble();
