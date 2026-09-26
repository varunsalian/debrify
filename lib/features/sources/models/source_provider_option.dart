/// A rendered provider choice. Source ordering and retry ownership stay upstream.
class SourceProviderOption {
  const SourceProviderOption({
    required this.key,
    required this.label,
    this.retryable = false,
    this.failed = false,
    this.retrying = false,
  });

  final String key;
  final String label;
  final bool retryable;
  final bool failed;
  final bool retrying;
}
