# Debrify

A modern torrent search and debrid management app built with Flutter.

## Features

- **Torrent Search**: Search for torrents across multiple sources
- **Debrid Downloads**: Manage your debrid downloads and transfers
- **Modern UI**: Beautiful Material Design 3 interface with dark theme
- **Cross-platform**: Works on Android, iOS, and other platforms

## Getting Started

### Prerequisites

- Flutter SDK (3.8.1 or higher)
- Dart SDK
- Android Studio / VS Code
- Android SDK (for Android development)

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd torrent_search_app
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## Building for Production

### Android

To build a release APK:
```bash
flutter build apk --release
```

To build an App Bundle for Google Play Store:
```bash
flutter build appbundle --release
```

### iOS

To build for iOS:
```bash
flutter build ios --release
```

## Project Structure

```
lib/
├── main.dart              # App entry point
├── models/                # Data models
├── screens/               # UI screens
├── services/              # Business logic and API services
├── utils/                 # Utility functions
└── widgets/               # Reusable UI components
```

## Dependencies

- `flutter`: Core Flutter framework
- `http`: HTTP client for API requests
- `intl`: Internationalization support
- `shared_preferences`: Local data storage

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
