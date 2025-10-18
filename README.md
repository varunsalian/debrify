# Debrify

A modern torrent search and debrid management app built with Flutter.

## Features

- **Multi-Source Torrent Search**: Toggle TorrentsCSV and Pirate Bay feeds, surface engine result counts, and sort by relevance, name, size, seeders, or freshness
- **Real-Debrid Integration**: Validate API keys, control default file-selection/post-download behaviour, and view live account status from inside the app
- **Smart Download Manager**: Persistent queued downloads with pause/resume, grouped torrent actions, bandwidth awareness, and crash-safe recovery
- **Debrify TV Mode**: Lean-back autoplay based on keyword rules with aggressive prefetching, queue management, and remote-friendly controls
- **Advanced Video Player**: Gesture seeking, aspect and speed toggles, audio/subtitle track switching, playlist auto-advance, and Debrify TV overlays
- **Episode Intelligence**: Persist series progress, mark finished episodes per season, and enrich data using TVMaze with resume-last logic
- **Personal Playlists**: Store unrestricted and RD torrents, recover single-file playback, and auto-order multi-episode collections
- **Modern UI**: Material 3 design with animated navigation, dark theme, and orientation handling across phones and Android TV
- **Cross-platform**: Runs on Android, iOS, macOS, Windows, Linux, and web targets

## Getting Started

### Prerequisites

- Flutter SDK (3.8.1 or higher)
- Dart SDK
- Android Studio / VS Code
- Android SDK (for Android development)

### Installation

#### Android

- Download the latest `app-release.apk` from the GitHub Releases page and sideload it on your device.

#### macOS, Windows, Linux, and Web

1. Clone the repository:
```bash
git clone <repository-url>
cd debrify
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app on your target device:
```bash
flutter run
```

## Building for Production

### Local Build

To build a release APK locally:
```bash
flutter build apk --release
```


### Automated CI/CD

This project uses GitHub Actions for automated builds and releases:

- **Automatic Builds**: Every push to `main` branch triggers an automated build
- **Artifacts**: Built APKs are automatically uploaded to GitHub Actions artifacts
- **Releases**: Tagged releases (v1.0.0, v1.1.0, etc.) automatically create GitHub releases with downloadable APKs

#### Workflow Files:
- `.github/workflows/build.yml` - Simple build and upload to artifacts
- `.github/workflows/ci-cd.yml` - Comprehensive CI/CD with testing and releases
- `.github/workflows/build-android.yml` - Android-specific build workflow

#### To create a release:
1. Create and push a tag: `git tag v1.0.0 && git push origin v1.0.0`
2. GitHub Actions will automatically build and create a release
3. Download the APK from the GitHub releases page

## Dependencies

- `flutter`: Core Flutter framework
- `http`: HTTP client for API requests
- `intl`: Internationalization support
- `shared_preferences`: Local data storage
- `media_kit`: Advanced video player
- `cached_network_image`: Image caching for episode posters

## Episode Tracking

The app includes a comprehensive episode tracking system for series content:

### Features
- **Automatic Tracking**: Episodes are automatically marked as finished when they complete
- **Visual Indicators**: Finished episodes show a green checkmark and "DONE" badge
- **Playlist Integration**: Episode status is displayed in both series browser and simple playlists
- **Persistent Storage**: Episode completion status is saved locally and persists across app sessions
- **Season Management**: Track episodes across different seasons of a series

### How It Works
1. When watching a series, the app automatically detects episode completion
2. Completed episodes are marked with a green checkmark icon and "DONE" label
3. Episode status is saved to local storage and restored when reopening the series
4. The series browser shows different visual states for current, last played, and finished episodes

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Version

Current version: 1.0.0
