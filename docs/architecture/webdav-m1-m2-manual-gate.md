# WebDAV M1/M2 manual release gate

Run this gate before shipping a build that includes WebDAV migration. The
automated fake-server suite remains the CI gate; this check covers real-server
behavior that is intentionally not reproduced by a Docker service in CI.

## Validation record

- **2026-09-01 — Koofr WebDAV:** the M1/M2 WebDAV migration flow at commit
  `366df767` was manually tested against Koofr and reported working end to
  end.
- The exact client-platform matrix and individual stress/error checks below
  were not recorded, so this entry is a real-provider smoke test rather than a
  pass of every numbered gate.
- **Nextcloud 34.0.3:** deferred on 2026-09-01; not tested and not claimed as
  validated.

## Pinned server

- Nextcloud Server **34.0.3** (the current stable maintenance release when
  this gate was written on 2026-09-01)
- WebDAV endpoint:
  `https://HOST/remote.php/dav/files/USERNAME/`
- Use a dedicated test account and app password.

Record the exact Nextcloud patch version, Debrify commit, client platform, and
result in the release checklist. Re-run on iOS and tvOS, plus one non-Apple
client.

## Required checks

1. Configure the HTTPS endpoint in Debrify and confirm **Save and Test** works.
2. Configure an explicit HTTP test endpoint and confirm Debrify labels it
   **Insecure HTTP** in both WebDAV settings and the migration picker. Do not
   use production credentials for this check.
3. In **Settings → Sync and Migrate**, choose a nested folder, create an
   encrypted profile backup, and confirm the remote filename contains a UTC
   timestamp and random suffix.
4. Confirm the request uses `If-None-Match: *`; pre-create the first candidate
   name in a controlled proxy/fake suffix build and verify Debrify retries with
   a different name rather than overwriting it.
5. Confirm the uploaded file is read back and SHA-256 verified before Debrify
   reports success.
6. Restore that backup from the DPAD picker. Cancel once at the file picker,
   once at the passphrase prompt, then complete a restore. Confirm temporary
   staging files are absent after every path.
7. Verify a bad password produces an authentication error, a missing object is
   not confused with authentication failure, and an exhausted quota is
   reported distinctly.
8. Through a controlled reverse proxy, exercise one same-origin 307 redirect
   and confirm it succeeds. Confirm cross-origin, scheme-downgrade, second-hop,
   and PROPFIND 301 redirects fail without sending credentials to the target.
9. On iOS, test a LAN hostname/IP and confirm the Local Network prompt appears.
   Deny it once and verify the failure is recoverable after enabling permission
   in Settings.
10. On tvOS, complete folder selection, backup, and restore using only the
    remote. Exercise both a representative package and a near-128 MiB
    synthetic package; each must complete safely, compact, or be refused before
    memory pressure. tvOS has no Local Network privacy prompt. On a low-memory
    Apple TV, confirm backup creation is deferred and a restore above the 32
    MiB safety cap is refused before parsing/decryption.

## Pass condition

All checks pass on Nextcloud 34.0.3. Any server-side
workaround or skipped platform blocks the M1/M2 release until documented and
approved.

References: [Nextcloud 34.0.3 maintenance release](https://nextcloud.com/blog/august-updates-for-nextcloud-hub-25-autumn-26-winter-26-spring/),
[Nextcloud WebDAV basics](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/WebDAV/basic.html),
and [Apple TN3179 local-network privacy platform table](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
