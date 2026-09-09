# WebDAV sync after remote credential import

Importing WebDAV server credentials now offers **Enable WebDAV Sync?** on the
receiving device after configuration application and the transfer receipt finish.
The server login is saved regardless of whether this optional offer is accepted.
When several servers are imported, the receiver chooses one; the app does not
join every server automatically. Resending an already-saved server can offer
setup again using its saved credentials.

Setup reuses `WebDavSyncConnectController`: the folder is `Debrify`, a new sync
secret is generated for an empty account, and an existing account supplies its
sync secret through the authenticated authority file. No folder or passphrase
entry is added. Successful setup registers the receiver and completes the first
sync through the existing activation flow.

The receiver must use an unlocked, authorized Admin profile. Joining existing
remote data requires the existing replacement confirmation semantics, explicitly
warning that locally imported configuration may be replaced. Cancelling the
offer does not pause sync or modify an account. Cancelling adoption or encountering
a setup error does not change the already-delivered configuration receipt;
separate receiver messages describe cancellation, failure or pending recovery.

The scheduler is paused only after an account is selected and resumed in cleanup.
Ordinary offers are scoped to the importing session and discarded on its reset.
For onboarding's in-app route restart, only the saved server IDs, destination
profile ID and data generation survive session cleanup. ProfileGate resumes the
offer after that same profile is entered/unlocked, re-reading credentials from
storage; it cannot appear over the picker or in another profile or generation.
This reference-only intent is in memory, not a persistent background setup job.
Offers never run during a configuration completion (including older completions
without a correlated request ID). It is not a silent account switch.

Validation includes UI tests for selection/success, cancellation, stale profile
scope, adoption confirmation and network/setup failure, plus a real encrypted
remote-transfer test proving the receipt completes before the optional offer.
Existing connection-controller and first-join tests cover registration/activation.
No real WebDAV account was modified during automated tests.
