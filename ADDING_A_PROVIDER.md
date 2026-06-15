# Adding a New Debrid/Cloud Provider

Step-by-step checklist for wiring a new provider into Debrify. Use **Premiumize**
(added in branch `0.5.1`) as the reference implementation — search the codebase
for `premiumize` / `Premiumize` to see each piece in context.

Convention: providers are identified by lowercase string ids
(`debrid`, `torbox`, `pikpak`, `premiumize`).

---

## 1. Account model
Parse the provider's account/user info.
- **New file:** `lib/models/<provider>_user.dart`
- Reference: `lib/models/torbox_user.dart`, `lib/models/premiumize_user.dart`
- Include helpers like `hasActivePremium`, `formattedPremiumExpiry`, `subscriptionStatus`.

## 2. API service
Network calls + validation against the provider API.
- **New file:** `lib/services/<provider>_service.dart`
- Reference: `lib/services/torbox_service.dart`, `lib/services/premiumize_service.dart`
- At minimum: `getUserInfo(apiKey)` that throws on bad key / error response.

## 3. Account service (session state)
Static holder + reactive `ValueNotifier`, validate/persist/refresh/clear.
- **New file:** `lib/services/<provider>_account_service.dart`
- Reference: `lib/services/torbox_account_service.dart`, `lib/services/premiumize_account_service.dart`
- Keep the validation-token guard and `persist` flag pattern.

## 4. Storage (SharedPreferences)
- **Edit:** `lib/services/storage_service.dart`
- Add key constants (`_<provider>ApiKey`, `_<provider>IntegrationEnabledKey`, etc.)
  near the other provider keys (~line 14-26).
- Add getters/setters: `get/save/delete<Provider>ApiKey`,
  `get/set<Provider>IntegrationEnabled` (after the Torbox helpers).

## 5. Account status widget
Card UI shown on the provider's settings page.
- **New file:** `lib/widgets/<provider>_account_status_widget.dart`
- Reference: `lib/widgets/torbox_account_status_widget.dart`, `lib/widgets/premiumize_account_status_widget.dart`

## 6. Provider settings page (API key entry)
Enable toggle + API key add/validate/logout + "how to get key" help.
- **New file:** `lib/screens/settings/<provider>_settings_page.dart`
- Reference: `lib/screens/settings/torbox_settings_page.dart`, `lib/screens/settings/premiumize_settings_page.dart`
- Skip hide-from-nav / file-selection / post-action until the provider has a
  nav tab / add-torrent flow (steps 9+).

## 7. Settings screen — Connections card
Add the tappable card in the connections grid (with TV focus wiring).
- **Edit:** `lib/screens/settings_screen.dart`
  - Import the account service + settings page.
  - Add `_<provider>Connected/Status/Caption` state fields.
  - Add `getXApiKey()` to the `_loadSummaries()` `Future.wait` + read its result index.
  - Add cached-state block + background `refreshUserInfo()` call.
  - Add `_applyXUserInfo(...)` helper.
  - Add `_ConnectionInfo` entry + `_openXSettings()` handler.
  - In `_ConnectionsSummary`: add field/constructor param, focus node
    (init + dispose), and **re-wire the grid up/down/left/right neighbors**
    for the new card count (wide 2-col + narrow 1-col).

## 8. Provider Settings page (default provider picker)
Let users pick it as the default torrent provider.
- **Edit:** `lib/screens/settings/provider_settings_page.dart`
  - Add `_<provider>Available` (gated on key + integration enabled).
  - Add to provider count, `hasAnyProvider`, and the "no longer available → reset
    to none" cleanup.
  - Add the radio `_ProviderOption` (stores id e.g. `'premiumize'`).
  - Update the no-providers message text.

---

## Not done yet (future steps — wire the provider into actual flows)
These make the provider functional beyond settings:

- [ ] **Add-torrent flow** — handle the provider id in `lib/screens/torrent_search_screen.dart`
      (and the provider-selection dialog) so adding a torrent routes to it.
- [ ] **Magnet / file selection / unrestrict / download** logic in the API service.
- [ ] **Navigation tab** (browse cloud library) + hide-from-nav support, if desired.
- [ ] **Quick Play** + post-torrent-action support.
- [ ] **Backup/restore** of the new credentials (`settings_screen.dart` backup logic).

---

### Quick verify
```
flutter analyze lib/screens/settings_screen.dart \
  lib/screens/settings/<provider>_settings_page.dart \
  lib/services/<provider>_service.dart \
  lib/services/<provider>_account_service.dart \
  lib/services/storage_service.dart \
  lib/models/<provider>_user.dart \
  lib/widgets/<provider>_account_status_widget.dart
```
