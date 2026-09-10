# WebDAV sync after remote credential import

## Sender entry point

The root Send screen has a separate **WebDAV Sync** category alongside
**Send everything**, **Addons**, and **Accounts & setup**. Its account comes from
the configured sync binding, not the media-server collection. An unlocked Admin
can select **WebDAV Sync account** and send it even when no WebDAV media server
is saved. Unconfigured accounts and uncommitted setup candidates are not exported.

Only the server URL/login is sent through the existing encrypted WebDAV
credential command; no profiles, databases, device identity or sync secret are
included. The receiving device saves those server credentials and offers the
sync setup described below. **Accounts & setup → WebDAV media servers** remains
a separate selection for browsing connections.

## Receiver setup

Importing WebDAV server credentials now offers **Enable WebDAV Sync?** on the
receiving device after configuration application and the transfer receipt finish.
The server login is saved regardless of whether this optional offer is accepted.
When several servers are imported, the receiver chooses one; the app does not
join every server automatically. Resending an already-saved server can offer
setup again using its saved credentials.

Receiver deduplication matches the normalized endpoint **and** username/password.
If an existing media connection uses a different login at the same endpoint, it
is retained unchanged and the incoming login is saved separately. Only the
matching incoming account is offered for sync, including after onboarding.
The sender rechecks pending logout as well as the active binding before returning
sync credentials; namespace-only logout changes cannot bypass revalidation.

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

## Appearance stays local

WebDAV Sync leaves appearance and display preferences local to each profile on
each device. This includes themes and Looks, layouts, navigation, card labels,
player and subtitle styling, ambient trailers, and TV display tuning. Existing
local choices are preserved; a newly joined profile starts with local defaults.
Legacy remote appearance values and saved pending sync targets are ignored.
Explicit profile backups/restores and copying profile defaults still include
appearance. No preference keys are renamed or deleted locally.

The exclusion list is `ProfileAppearancePreferences.keys`; add new appearance
preferences there so hot sync, bootstrap export/import, and pending replay agree.
