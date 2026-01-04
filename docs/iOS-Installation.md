# iOS Installation Guide

Debrify provides an **unsigned IPA** for iOS users. Since Apple requires a $99/year developer account for official distribution, you'll need to sideload the app using one of the methods below.

> **Important**: Sideloaded apps expire after **7 days** and need to be reinstalled. This is an Apple limitation, not a Debrify limitation.

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
11. Open Debrify

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
3. Select your personal team (free Apple ID)
4. Click the **Run** button

---

## Troubleshooting

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
A: Apple restricts free developer accounts to 7-day certificates. Only paid developer accounts ($99/year) can create apps that don't expire.

**Q: Is sideloading safe?**
A: Yes, as long as you download the IPA directly from our GitHub releases. The app is the same as what would be on the App Store.

**Q: Will my data be lost when I reinstall?**
A: No, your data is preserved when reinstalling/refreshing the same app.

**Q: Can I use a secondary Apple ID?**
A: Yes, it's actually recommended to use a separate Apple ID for sideloading.
