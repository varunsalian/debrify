# iOS Installation Guide

Debrify provides an **unsigned IPA** for iOS users. Since Apple requires a $99/year developer account for official distribution, you'll need to sideload the app using one of the methods below.

> **Important**: Sideloaded apps expire after **7 days** and need to be reinstalled. This is an Apple limitation, not a Debrify limitation.
>
> **Unless you have a paid Apple Developer account** — then it's **1 year**. See [the section below](#have-a-paid-apple-developer-account).

---

## Have a paid Apple Developer account?

Good news: it doesn't change *how* you install, but it makes the result last **1 year instead of 7 days**.

### What changes

| | Free Apple ID | Paid Developer Program ($99/yr) |
|---|---|---|
| App keeps working for | **7 days** | **1 year** |
| Sideloaded apps at once | 3 | Unlimited |
| Devices | Very limited | Up to **100 per membership year** |
| How often you plug into a computer | ~Weekly | ~Once a year |

### What does *not* change

- **You still need a computer for the first install.** Debrify ships an *unsigned* IPA, so the signing has to happen on your machine. Sideloadly / AltStore do exactly that — they just sign it with your paid team instead of a free Apple ID.
- **You still have to tap Trust once** in Settings → General → VPN & Device Management.
- **There's no App Store / TestFlight shortcut.** A developer account lets you sign apps; it doesn't let you install someone else's app straight from a link.

### Recommended: Sideloadly with your paid account

Works on **Windows and macOS**. This is the simplest path.

1. Install [Sideloadly](https://sideloadly.io/) on your computer.
2. Download `debrify-*-unsigned.ipa` from [GitHub Releases](https://github.com/varunsalian/debrify/releases).
3. Plug your iPhone in via USB and unlock it. Tap **Trust This Computer** if prompted.
4. Drag the IPA into Sideloadly.
5. In the **Apple ID** field, enter **the Apple ID that the paid membership is on** — this is the part that matters. If you sign in with a different Apple ID, you'll silently get a 7-day certificate.
6. Click **Start** and enter your password (and 2FA code) when prompted.
7. When it finishes, check the log — it should report an expiry roughly **365 days** out, not 7. If it says 7 days, you used the wrong Apple ID.

Then on your iPhone:

8. **Settings → General → VPN & Device Management**
9. Tap your developer profile → **Trust**
10. **(iOS 16 and later)** Enable **Developer Mode**: **Settings → Privacy & Security → Developer Mode** → toggle it on → restart when prompted → tap **Turn On** and enter your passcode after the reboot. Development-signed apps won't launch without this — trusting the profile alone is not enough. (The Developer Mode menu item only appears after the first install attempt.)
11. Open Debrify. You're set for a year.

### Alternative: AltStore Classic with your paid account

Same idea, but AltStore keeps a list of your sideloaded apps on-device and can push updates. Follow [Option 1](#option-1-altstore-recommended) below, and sign in with the **paid** Apple ID when AltServer asks. Apps signed with a paid account get a 1-year certificate, so the background-refresh requirement effectively goes away — you don't need AltServer running on the same Wi-Fi all the time anymore.

### Alternative: build it yourself in Xcode (Mac only)

This is where a paid account really shines — no IPA juggling at all. Follow [Option 3](#option-3-build-from-source), but in **Signing & Capabilities** pick your **paid team** instead of a personal team. Xcode registers the device to your account and issues a 1-year provisioning profile automatically.

### Gotchas worth knowing

- **Bundle ID suffixing.** Sideloadly appends your team ID to the bundle identifier by default (e.g. `com.varunsalian.debrify.ABCDE12345`). That's fine and it's why a Sideloadly install can sit alongside an existing one — but it also means the two are *separate apps* with separate data. If you're replacing an older install, delete the old one first.
- **Device slots don't free up mid-year.** Every device you register counts against your 100. You can disable a device in the developer portal, but the count only resets when your membership renews.
- **Certificate limit.** Apple caps how many development certificates you can have. If signing starts failing with a certificate error, go to [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) → Certificates and revoke stale ones.
- **1 year is the ceiling, not a promise.** If you revoke the certificate, let the membership lapse, or re-sign a pile of other apps, the existing install can stop opening. Re-running the same steps fixes it.
- **2FA.** If Sideloadly/AltServer keeps rejecting your password, generate an app-specific password at [appleid.apple.com](https://appleid.apple.com/) → Sign-In and Security → App-Specific Passwords and use that instead.

---

## Option 1: AltStore (Recommended)

AltStore automatically refreshes your apps in the background so you don't have to reinstall every 7 days.

### Requirements
- iPhone/iPad running iOS 12.2 or later
- A computer (Mac or Windows) on the same Wi-Fi network
- An Apple ID (free account works)

### Setup (One-Time)

**On your computer:**

1. Download AltServer from [altstore.io](https://altstore.io/)
2. Install and run AltServer
   - **Mac**: AltServer appears in the menu bar
   - **Windows**: AltServer appears in the system tray
3. Connect your iPhone via USB
4. Click AltServer icon → Install AltStore → Select your device
5. Enter your Apple ID credentials when prompted

**On your iPhone:**

6. Go to **Settings → General → VPN & Device Management**
7. Tap your Apple ID under "Developer App" and tap **Trust**
8. **(iOS 16 and later)** Enable **Developer Mode**: **Settings → Privacy & Security → Developer Mode** → toggle it on → restart when prompted → tap **Turn On** after the reboot. AltStore and the apps it installs won't launch without this. (The menu item only appears after AltStore has been installed once.)

### Install Debrify

1. Download `debrify-*-unsigned.ipa` from [GitHub Releases](https://github.com/varunsalian/debrify/releases)
2. Open the file with AltStore, or:
   - Open AltStore on your iPhone
   - Go to **My Apps** tab
   - Tap **+** in the top left
   - Select the downloaded IPA file
3. Wait for installation to complete

### Keep It Fresh

- Keep AltServer running on your computer
- Make sure your iPhone and computer are on the same Wi-Fi network
- AltStore will automatically refresh the app before it expires

---

## Option 2: Sideloadly (Manual)

Sideloadly is a simple tool for one-time sideloading. You'll need to reinstall every 7 days.

### Requirements
- iPhone/iPad running iOS 7 or later
- A computer (Mac or Windows)
- An Apple ID (free account works)
- Lightning/USB-C cable

### Steps

1. Download Sideloadly from [sideloadly.io](https://sideloadly.io/)
2. Install and run Sideloadly
3. Connect your iPhone via USB cable
4. Download `debrify-*-unsigned.ipa` from [GitHub Releases](https://github.com/varunsalian/debrify/releases)
5. Drag and drop the IPA file into Sideloadly
6. Enter your Apple ID and password
7. Click **Start**
8. Wait for installation to complete

**On your iPhone:**

9. Go to **Settings → General → VPN & Device Management**
10. Tap your Apple ID under "Developer App" and tap **Trust**
11. **(iOS 16 and later)** Enable **Developer Mode**: **Settings → Privacy & Security → Developer Mode** → toggle it on → restart when prompted → tap **Turn On** after the reboot. Sideloaded apps won't launch without this. (The menu item only appears after the first install attempt.)
12. Open Debrify

### Reinstalling

Repeat steps 3-8 every 7 days before the app expires.

---

## Option 3: Build From Source

If you have a Mac with Xcode, you can build and run directly on your device:

```bash
# Clone the repository
git clone https://github.com/varunsalian/debrify.git
cd debrify

# Get dependencies
flutter pub get

# Open in Xcode
open ios/Runner.xcworkspace
```

In Xcode:
1. Select your device from the device dropdown
2. Go to **Signing & Capabilities**
3. Select your team — a personal team (free Apple ID) gives 7 days, a **paid** team gives 1 year
4. Click the **Run** button
5. **(iOS 16 and later)** If the device blocks the launch, enable **Developer Mode** on the iPhone: **Settings → Privacy & Security → Developer Mode** → toggle on → restart → confirm. Xcode usually prompts you through this the first time it runs on the device.

---

## Troubleshooting

### "Developer Mode Required" alert / app won't open after Trust
- On iOS 16 and later, sideloaded (development-signed) apps are blocked until **Developer Mode** is on: **Settings → Privacy & Security → Developer Mode** → toggle → restart → tap **Turn On** after the reboot
- The Developer Mode menu item is hidden until a development-signed app has been installed at least once — install first, then enable it
- This is separate from (and additional to) trusting the developer profile

### "Unable to install" error
- Make sure you trusted the developer profile in Settings
- Try revoking your Apple ID certificates in AltStore/Sideloadly and try again

### App crashes on launch
- Reinstall the app
- Make sure you're using the latest IPA from releases

### "Your session has expired"
- Apple IDs with 2FA may require an app-specific password
- Generate one at [appleid.apple.com](https://appleid.apple.com/) → Sign-In and Security → App-Specific Passwords

### AltStore not refreshing automatically
- Ensure AltServer is running on your computer
- Both devices must be on the same Wi-Fi network
- Try manually refreshing in AltStore → My Apps → hold on Debrify → Refresh

---

## FAQ

**Q: Why does the app expire after 7 days?**
A: Apple restricts free Apple IDs to 7-day certificates. A paid Apple Developer account ($99/year) raises that to 1 year — see [Have a paid Apple Developer account?](#have-a-paid-apple-developer-account) above.

**Q: I just bought a developer account. Is installing simpler now?**
A: The steps are the same — you still sideload with Sideloadly or AltStore from a computer, because the IPA ships unsigned. What changes is the result: 1 year instead of 7 days, no 3-app limit, and up to 100 devices. Just make sure you sign in with the Apple ID the membership is actually on.

**Q: Is sideloading safe?**
A: Yes, as long as you download the IPA directly from our GitHub releases. The app is the same as what would be on the App Store.

**Q: Will my data be lost when I reinstall?**
A: No, your data is preserved when reinstalling/refreshing the same app.

**Q: Can I use a secondary Apple ID?**
A: Yes, it's actually recommended to use a separate Apple ID for sideloading.
