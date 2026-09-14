/// A local authorization boundary changed. This remains a StateError for
/// existing UI handlers, but durable jobs can wait for a new valid session
/// without confusing it with malformed data or invalid server credentials.
class ProfileSessionUnavailable extends StateError {
  ProfileSessionUnavailable(super.message);
}
