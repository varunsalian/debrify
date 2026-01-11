<p align="center">
  <img src="assets/app_icon.png" alt="Debrify" width="120" height="120">
</p>

<h1 align="center">Debrify</h1>

<p align="center">
  <strong>Stream & Download — Effortlessly</strong><br>
  The all-in-one debrid manager for Real-Debrid, Torbox, and PikPak
</p>

<p align="center">
  <a href="https://github.com/varunsalian/debrify/releases"><img src="https://img.shields.io/github/v/release/varunsalian/debrify?style=flat-square&color=6366f1" alt="Release"></a>
  <a href="https://github.com/varunsalian/debrify/stargazers"><img src="https://img.shields.io/github/stars/varunsalian/debrify?style=flat-square&color=f59e0b" alt="Stars"></a>
  <a href="https://github.com/varunsalian/debrify/releases"><img src="https://img.shields.io/github/downloads/varunsalian/debrify/total?style=flat-square&color=22c55e" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/Flutter-3.8+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/License-Polyform%20NC-blue?style=flat-square" alt="License">
</p>

<p align="center">
  <a href="https://varunsalian.github.io/debrify/"><strong>Website</strong></a> &bull;
  <a href="https://github.com/varunsalian/debrify/releases"><strong>Download</strong></a> &bull;
  <a href="#-features">Features</a> &bull;
  <a href="#-supported-platforms">Platforms</a> &bull;
  <a href="https://www.reddit.com/r/debrify/">Reddit</a> &bull;
  <a href="https://discord.gg/nay3FVtAp">Discord</a>
</p>

---

<p align="center">
  <img src="assets/screenshots/search.png" alt="Search" width="49%">
  <img src="assets/screenshots/downloads.png" alt="Downloads" width="49%">
</p>
<p align="center">
  <img src="assets/screenshots/player.png" alt="Player" width="49%">
  <img src="assets/screenshots/episodes.png" alt="Episodes" width="49%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Real--Debrid-Supported-4ade80?style=for-the-badge" alt="Real-Debrid">
  <img src="https://img.shields.io/badge/Torbox-Supported-8b5cf6?style=for-the-badge" alt="Torbox">
  <img src="https://img.shields.io/badge/PikPak-Supported-0ea5e9?style=for-the-badge" alt="PikPak">
</p>

---

## What is Debrify?

Debrify is a **debrid manager** that lets you browse, stream, and download content from your debrid accounts—all from one app. It comes with a **built-in video player** optimized for movies and TV shows, a **download manager** with queue support, and an **optional plugin system** for torrent search engines.

> **No torrenting on your device.** Debrify connects to debrid services that handle everything server-side. You just stream or download the finished files.

---

## ✨ Features

<table>
<tr>
<td width="50%">

### Debrid Management
- **Multi-provider support** — Real-Debrid, Torbox, and PikPak
- **Full feature parity** — Stream, download, and manage files across all providers
- **Account dashboard** — View status, expiration, and usage at a glance
- **File browser** — Browse and manage your debrid cloud storage

</td>
<td width="50%">

### Built-in Player
- **Native playback** — Powered by media_kit/libmpv
- **Track selection** — Switch audio and subtitle tracks on the fly
- **Resume playback** — Picks up where you left off, always
- **TV-optimized** — Gesture controls on mobile, remote-friendly on TV

</td>
</tr>
<tr>
<td width="50%">

### Download Manager
- **Background downloads** — Queue files and let them download
- **Pause & resume** — Full control over your download queue
- **Batch operations** — Select multiple files, download all at once
- **Cross-platform** — Works on mobile and desktop

</td>
<td width="50%">

### Search Plugins *(Optional)*
- **Engine marketplace** — Import community-built torrent search engines
- **Multi-engine search** — Query multiple sources simultaneously
- **Smart filtering** — Filter by quality, size, seeders, and more
- **One-click add** — Send results directly to your debrid provider

</td>
</tr>
</table>

---

## 📺 Android TV Mode

A dedicated lean-back experience for your living room.

<p align="center">
  <img src="assets/screenshots/tv-player.png" alt="TV Player" width="70%">
</p>

<p align="center">
  <img src="assets/screenshots/tv-player-channel.png" alt="TV Player Channel Mode" width="70%">
</p>

<p align="center">
  <img src="assets/screenshots/tv-subtitles.png" alt="TV Subtitle Settings" width="70%">
</p>

<p align="center">
  <img src="assets/screenshots/tv-channels.png" alt="TV Channels" width="49%">
  <img src="assets/screenshots/tv-guide.png" alt="TV Guide" width="49%">
</p>

- **Remote-friendly player** — Full playback controls with D-pad navigation
- **Subtitle customization** — Size, style, color, and background options
- **Channel mode** — Watch content like cable TV with channel numbers
- **Quick channel guide** — Switch channels on the fly

---

## 📱 Supported Platforms

Debrify runs everywhere. One codebase, full feature support across all platforms.

| Platform | Download | Notes |
|:---------|:---------|:------|
| **Android** | [APK](https://github.com/varunsalian/debrify/releases) | Phones and tablets |
| **Android TV** | [APK](https://github.com/varunsalian/debrify/releases) | Full D-pad navigation and remote support |
| **Windows** | [Installer](https://github.com/varunsalian/debrify/releases) | Windows 10/11 |
| **macOS** | [DMG](https://github.com/varunsalian/debrify/releases) | Intel and Apple Silicon |
| **Linux** | [AppImage](https://github.com/varunsalian/debrify/releases) | Requires libmpv ([see install notes](#linux)) |
| **iOS** | [IPA](https://github.com/varunsalian/debrify/releases) | Unsigned — requires sideloading ([guide](docs/iOS-Installation.md)) |

---

## 🚀 Installation

### Android / Android TV
Download the APK from [Releases](https://github.com/varunsalian/debrify/releases) and install. On TV, use a file manager app like Downloader or install via ADB.

### Windows
Download the installer, run it, and launch from the Start Menu. First run may trigger SmartScreen—click "More info" → "Run anyway".

### macOS
Download the DMG, drag Debrify to Applications. First launch: right-click → Open (app is not notarized).

### Linux
```bash
# Install libmpv (required)
sudo apt install libmpv2        # Ubuntu 24.04+
sudo apt install libmpv1        # Ubuntu 22.04 / Debian
sudo dnf install mpv-libs       # Fedora
sudo pacman -S mpv              # Arch

# Run the AppImage
chmod +x debrify-*.AppImage
./debrify-*.AppImage
```

### iOS
Download the unsigned IPA and sideload using **AltStore** or **Sideloadly**. See the [iOS Installation Guide](docs/iOS-Installation.md) for step-by-step instructions.

> **Note:** Sideloaded apps require re-signing every 7 days. AltStore can handle this automatically.

---

## 🔌 Provider Support

| Feature | Real-Debrid | Torbox | PikPak |
|:--------|:-----------:|:------:|:------:|
| Stream files | ✅ | ✅ | ✅ |
| Download files | ✅ | ✅ | ✅ |
| Browse cloud storage | ✅ | ✅ | ✅ |
| Add magnets/links | ✅ | ✅ | ✅ |
| Playlists | ✅ | ✅ | ✅ |
| Episode tracking | ✅ | ✅ | ✅ |

---

## 🛠️ Building from Source

```bash
git clone https://github.com/varunsalian/debrify.git
cd debrify
flutter pub get
flutter run
```

**Build commands:**
```bash
flutter build apk --release              # Android
flutter build ios --release --no-codesign # iOS (unsigned)
flutter build windows --release          # Windows
flutter build macos --release            # macOS
flutter build linux --release            # Linux
```

---

## 🗺️ Roadmap

- [ ] Enhanced desktop UX
- [ ] In-app update notifications
- [ ] More search engine plugins
- [ ] Improved test coverage

---

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am 'Add my feature'`
4. Push: `git push origin feature/my-feature`
5. Open a pull request

---

## 💬 Community

- **Reddit** — [r/debrify](https://www.reddit.com/r/debrify/) for discussion and tips
- **Discord** — [Join the server](https://discord.gg/nay3FVtAp) for help and updates
- **Issues** — [Report bugs](https://github.com/varunsalian/debrify/issues) or request features

---

## 📄 License

Debrify is released under the [Polyform Noncommercial License 1.0.0](LICENSE). Free for personal use. Commercial use is not permitted.

---

<p align="center">
  <a href="https://varunsalian.github.io/debrify/">
    <img src="https://img.shields.io/badge/Visit_Website-varunsalian.github.io/debrify-6366f1?style=for-the-badge" alt="Website">
  </a>
</p>

<p align="center">
  <sub>Made with Flutter. Free for personal use.</sub>
</p>
