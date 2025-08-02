# Torrent Search App

A modern, beautiful Flutter Android app for searching torrents with a clean Material Design 3 interface.

## Features

- 🔍 **Search Torrents**: Search for torrents using the torrents-csv.com API
- 📱 **Modern UI**: Beautiful Material Design 3 interface with smooth animations
- 📊 **Detailed Information**: View torrent size, seeders, leechers, and completion count
- 🔗 **Magnet Links**: One-tap magnet link generation and clipboard copying
- 📅 **Date Information**: See when torrents were created
- 🌙 **Responsive Design**: Works perfectly on all Android screen sizes

## Screenshots

The app features a clean, modern interface with:
- Search bar with real-time search functionality
- Card-based torrent listings with detailed statistics
- Color-coded stat chips for easy information scanning
- Smooth animations and transitions

## Getting Started

### Prerequisites

- Flutter SDK (3.8.1 or higher)
- Android Studio / VS Code
- Android device or emulator

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

### Building for Production

To build an APK for distribution:
```bash
flutter build apk --release
```

## API Integration

The app integrates with the torrents-csv.com API:
- **Endpoint**: `https://torrents-csv.com/service/search?q=SEARCH_QUERY`
- **Response Format**: JSON with torrent information including infohash, name, size, seeders, leechers, etc.

## Features in Detail

### Search Functionality
- Real-time search with debounced input
- Error handling for network issues
- Loading states with progress indicators
- Empty state handling

### Torrent Display
- **File Size**: Automatically formatted (B, KB, MB, GB)
- **Seeders**: Green chip showing number of seeders
- **Leechers**: Orange chip showing number of leechers  
- **Completed**: Purple chip showing download completion count
- **Creation Date**: Formatted date display

### Magnet Link Generation
- Automatic magnet link generation from infohash
- One-tap clipboard copying
- Visual feedback with snackbar notifications

## Dependencies

- `flutter`: Core Flutter framework
- `http`: For API requests
- `intl`: For date formatting
- `cupertino_icons`: iOS-style icons

## Permissions

The app requires the following Android permissions:
- `INTERNET`: For API communication

## Architecture

The app follows a simple, clean architecture:
- **Single Screen**: Main search and results display
- **State Management**: Flutter's built-in setState for simple state management
- **API Layer**: Direct HTTP requests with error handling
- **UI Layer**: Material Design 3 components with custom styling

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is for educational purposes. Please ensure you comply with local laws regarding torrent usage.

## Disclaimer

This app is provided for educational purposes only. Users are responsible for ensuring they comply with local laws and regulations regarding torrent usage and copyright.
