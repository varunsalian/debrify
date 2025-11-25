# Debrify

![Flutter](https://img.shields.io/badge/Flutter-3.8+-blue?logo=flutter&logoColor=white)
![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20Android%20TV%20%7C%20Windows%20%7C%20macOS%20%7C%20Web-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)

> Built as a personal “vibe coded” spare-time project—open-sourced so others can test-drive it or take it further. Most polish currently targets **Android**; the desktop builds work, but expect the occasional rough edge.

A modern debrid companion built with Flutter, featuring plugin-based torrent search, a powerful search UI, lean-back Android TV mode, advanced player, and persistent playlists. Supports Real-Debrid and Torbox.

---

## Table of Contents
- [✨ Features](#-features)
- [🧭 Platform Snapshot](#-platform-snapshot)
- [🚀 Quick Start](#-quick-start)
- [📦 Installation Details](#-installation-details)
- [🛠️ Build & Release Notes](#️-build--release-notes)
- [📺 Episode Tracking Deep-Dive](#-episode-tracking-deep-dive)
- [🧱 Tech Stack](#-tech-stack)
- [🗺️ Roadmap](#️-roadmap)
- [🤝 Contributing](#-contributing)
- [💬 Support](#-support)
- [📄 License](#-license)

---

## ✨ Features
- 🔍 **Multi-source torrent search** with engine toggles, live counts, and smart sorting
- 🔐 **Debrid service integration** (Real-Debrid & Torbox) for API validation, file-selection defaults, and account snapshot
- 📥 **Smart-ish download manager** (still evolving) with queue persistence, pause/resume, and grouped actions
- 📺 **Debrify TV mode** with Android TV support for lean-back autoplay, keyword queues, and remote-friendly controls
- 🎬 **Advanced player** powered by `media_kit`: gestures, audio/subtitle tracks, resume points, and Debrify TV overlays
- 🧠 **Episode intelligence** via TVMaze enrichment, per-season progress, and resume-last logic
- 🎞️ **Personal playlists** that recover restricted links, order multi-episode packs, and remember Real-Debrid torrents
- 🎨 **Material 3 UI** with dark theme, animated navigation, and Android TV aware orientation

> ⚠️ **Heads-up:** Desktop builds are convenient ports of the Android flow. Windows, macOS, and web are fully usable but not yet as polished.

> ℹ️ **Note:** Downloads are not yet supported for Torbox. Streaming and playlist features work fully with both Real-Debrid and Torbox.

---

## 🧭 Platform Snapshot

| Platform | Status | Notes |
|----------|--------|-------|
| Android | ✅ Stable | Primary target; APK ships with each release |
| Android TV | ✅ Stable | Full TV mode support with D-pad navigation and remote controls |
| Windows | ✅ Usable | Installer maximizes into fullscreen and stores downloads in `~/Downloads/Debrify` |
| macOS | ✅ Usable | DMG available; fullscreen & downloads behave similar to Windows |
| Linux | ⚠️ Dev only | Run from source (`flutter run`) |
| Web | ⚠️ Dev only | Build/run from source; some features (local downloads) disabled |

---

## 🚀 Quick Start
- **Prefer the easy route?** Grab the latest release artifacts (APK / DMG / Windows setup) from the [GitHub Releases page](https://github.com/varunsalian/debrify/releases).
- **Want to tinker?** Clone the repo and run `flutter run` on your target device.

---

## 📦 Installation Details

### Android Phone/TV
1. Download the APK from the [GitHub Releases page](https://github.com/varunsalian/debrify/releases)
2. Install the APK on your Android device (you can use file managers like Downloader or X-plore for TV, or install via ADB)

The app automatically detects Android TV and optimizes the UI for D-pad navigation and remote controls.

### Windows
1. Download `debrify-<version>-setup.exe`
2. Run the installer (expect SmartScreen on first run since it’s self-signed)
3. Launch from Start Menu; downloads land in `C:\Users\<you>\Downloads\Debrify`

### macOS
1. Download `debrify-<version>.dmg`
2. Drag **Debrify** into **Applications**
3. First launch may require Control+Open because the app isn’t notarized yet

### Linux & Web (from source)
```bash
git clone https://github.com/varunsalian/debrify.git
cd debrify
flutter pub get
flutter run
```

---

## 🛠️ Build & Release Notes
- `flutter build apk --release` – local Android release build
- `flutter build macos --release` – produces `build/macos/Build/Products/Release/debrify.app`
- `flutter build windows --release` – generates the runner binaries used by the Inno Setup installer
- GitHub Actions workflow (`.github/workflows/build.yml`) builds all three artifacts on tagged releases and attaches them automatically.

---

## 📺 Episode Tracking Deep-Dive
- ✅ **Automatic detection** of finished episodes with persistent markers
- 🎯 **State restoration** for current, last played, and completed content
- 📂 **Playlist integration** showing progress across different entry points
- 🗂️ **Season-aware storage** so you can jump between seasons without losing place

Under the hood, progress is stored via `StorageService` and enriched by `EpisodeInfoService` (TVMaze).

---

## 🧱 Tech Stack
- **Flutter** (Material 3, Google Fonts, Animations)
- **media_kit / media_kit_video** for the player
- **background_downloader** + custom queue logic for downloads
- **Real-Debrid & Torbox APIs** wrapped in `DebridService`
- **Provider** for lightweight state management
- **window_manager** (desktop) for window control

---

## 🗺️ Roadmap
- [ ] Polish desktop UX (window chrome, settings panels)
- [ ] Expand download manager reliability on Windows/macOS
- [ ] Add in-app release notes and update prompts
- [ ] Bundle optional analytics/telemetry toggle for debugging
- [ ] Improve automated tests and CI coverage

Have ideas? [Open an issue](../../issues) or send a PR.

---

## 🤝 Contributing
1. Fork the repo
2. Create a branch (`git checkout -b feature/amazing-idea`)
3. Commit your changes (`git commit -am 'feat: add amazing idea'`)
4. Push (`git push origin feature/amazing-idea`)
5. Open a pull request 🚀

> Tip: Attach screenshots or screen captures when tweaking UI/UX—they help reviewers a ton.

---

## 💬 Support
- Found a bug? [File an issue](../../issues/new/choose)
- Questions? Start a discussion or ping via issues
- Want to collaborate? PRs are welcome; please include a short summary + testing notes

---

## 📄 License
Debrify is released under the [MIT License](LICENSE).

---

## 📌 Version
Current release: **0.1.0** (see [`pubspec.yaml`](pubspec.yaml))
