import 'package:flutter/foundation.dart';
import 'dropbox_auth_service.dart';
import 'dropbox_service.dart';
import 'playlist_sync_service.dart';

class SyncSettingsViewModel extends ChangeNotifier {
  bool _isLoading = false;
  bool _isConnected = false;
  String? _accountEmail;
  String? _errorMessage;

  // Getters
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  String? get accountEmail => _accountEmail;
  String? get errorMessage => _errorMessage;

  /// Initialize the view model by checking current connection status
  Future<void> initialize() async {
    _setLoading(true);
    try {
      final connected = await DropboxAuthService.isConnected();
      if (connected) {
        _accountEmail = await DropboxAuthService.getAccountEmail();
        _isConnected = true;
      } else {
        _isConnected = false;
        _accountEmail = null;
      }
      _clearError();
    } catch (e) {
      _setError('Failed to check connection status: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Connect to Dropbox using OAuth2 + PKCE
  Future<void> connectToDropbox() async {
    _setLoading(true);
    _clearError();

    try {
      // Step 1: Authenticate with Dropbox
      final authResult = await DropboxAuthService.authenticate();
      
      if (!authResult.success) {
        _setError(authResult.error ?? 'Authentication failed');
        return;
      }

      // Step 2: Get account information
      final accountResult = await DropboxService.getCurrentAccount();
      
      if (!accountResult.success) {
        _setError(accountResult.error ?? 'Failed to get account information');
        return;
      }

      final email = accountResult.email;
      if (email == null) {
        _setError('Failed to get account email');
        return;
      }

      // Step 3: Store account info (App Folder access provides dedicated folder automatically)
      await DropboxAuthService.storeAccountInfo(email, '/Apps/Debrify');

      // Step 4: Initial playlist sync - upload local playlist to Dropbox
      await PlaylistSyncService.uploadPlaylist();

      // Update UI state
      _accountEmail = email;
      _isConnected = true;
      _clearError();

    } catch (e) {
      _setError('Connection failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Disconnect from Dropbox
  Future<void> disconnectFromDropbox() async {
    _setLoading(true);
    _clearError();

    try {
      // Clear sync status (but keep remote data safe in Dropbox)
      await PlaylistSyncService.clearSyncStatus();
      
      // Disconnect from Dropbox
      await DropboxAuthService.disconnect();
      
      // Update UI state
      _isConnected = false;
      _accountEmail = null;
      _clearError();

    } catch (e) {
      _setError('Disconnect failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Refresh the connection status
  Future<void> refreshConnectionStatus() async {
    _setLoading(true);
    _clearError();

    try {
      final connected = await DropboxAuthService.isConnected();
      
      if (connected) {
        // Try to refresh the token if needed
        final accountResult = await DropboxService.getCurrentAccount();
        
        if (accountResult.success && accountResult.email != null) {
          _accountEmail = accountResult.email;
          _isConnected = true;
          
          // Update stored email if it changed
          final currentEmail = await DropboxAuthService.getAccountEmail();
          if (currentEmail != accountResult.email) {
            await DropboxAuthService.storeAccountInfo(accountResult.email!, '/Apps/Debrify');
          }
        } else {
          // Token might be invalid, try to refresh
          final refreshResult = await DropboxAuthService.refreshAccessToken();
          
          if (refreshResult.success) {
            final accountResult = await DropboxService.getCurrentAccount();
            if (accountResult.success && accountResult.email != null) {
              _accountEmail = accountResult.email;
              _isConnected = true;
              await DropboxAuthService.storeAccountInfo(accountResult.email!, '/Apps/Debrify');
            } else {
              _isConnected = false;
              _accountEmail = null;
            }
          } else {
            _isConnected = false;
            _accountEmail = null;
          }
        }
      } else {
        _isConnected = false;
        _accountEmail = null;
      }
      
      _clearError();

    } catch (e) {
      _setError('Failed to refresh connection: $e');
      _isConnected = false;
      _accountEmail = null;
    } finally {
      _setLoading(false);
    }
  }

  /// Get the display text for the connection status
  String getConnectionStatusText() {
    if (_isLoading) {
      return 'Checking connection...';
    } else if (_isConnected && _accountEmail != null) {
      return 'Connected as $_accountEmail';
    } else {
      return 'Connect with Dropbox';
    }
  }

  /// Clear any error message
  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Set an error message
  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Set loading state
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  /// Clear any error message (public method for UI)
  void clearError() {
    _clearError();
  }

  /// Manually sync playlist to Dropbox
  Future<void> syncPlaylistNow() async {
    _setLoading(true);
    _clearError();

    try {
      if (!_isConnected) {
        _setError('Not connected to Dropbox');
        return;
      }

      await PlaylistSyncService.uploadPlaylist();
      _clearError();

    } catch (e) {
      _setError('Sync failed: $e');
    } finally {
      _setLoading(false);
    }
  }
}
