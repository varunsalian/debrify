# Debrify cache maintenance patch

Base: flutter_cache_manager 3.4.1, published pub.dev archive. MIT license retained.

- Resolve eviction paths through the configured filesystem and await deletion.
- Serialize index writes and maintenance; do not resurrect evicted rows on touch.
- Enforce LRU count AND byte targets, including recently accessed files. Default
  byte target is 64 MiB; app artwork, logos and badges configure their own limits.
- Schedule maintenance after writes as well as lookups; cancel it on disposal.
- Protect registered file writes from eviction. Budgets are eventual targets,
  not a limit on instantaneous download/decoding memory or in-flight disk bytes.
- Protect files handed to image decoders for 30 seconds during automatic
  eviction. Explicit cache removals still invalidate images immediately.
- Await metadata commits before returning downloaded/written files.
- Acquire HTTP revalidation entries and key-based eviction leases atomically.
  Keep the lease through headers, body and metadata commit, releasing in finally
  on completion, errors or stream cancellation. The network never holds the
  store mutation lock; unrelated cache entries can still be evicted.
- Close and remove partial files when HTTP response streaming fails.
- At repository initialization, recover unindexed UUID files older than one day
  in that cache's directory. Preserve indexed files, recent files and links.

Regression coverage lives in the app's test/services/image_disk_cache_test.dart.
Re-evaluate these changes before upgrading the upstream package.
