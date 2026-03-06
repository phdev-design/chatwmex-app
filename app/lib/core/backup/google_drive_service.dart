import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleDriveException implements Exception {
  final String message;
  GoogleDriveException(this.message);

  @override
  String toString() => message;

  factory GoogleDriveException.notAuthenticated() =>
      GoogleDriveException('請先連接 Google Drive');
  factory GoogleDriveException.folderCreationFailed() =>
      GoogleDriveException('無法建立備份資料夾');
  factory GoogleDriveException.uploadFailed(String msg) =>
      GoogleDriveException('上傳失敗：$msg');
  factory GoogleDriveException.downloadFailed(String msg) =>
      GoogleDriveException('下載失敗：$msg');
  factory GoogleDriveException.deleteFailed(String msg) =>
      GoogleDriveException('刪除失敗：$msg');
}

/// Thin HTTP client that wraps a GoogleSignInClientAuthorization access token.
class _AuthorizedClient extends http.BaseClient {
  _AuthorizedClient(this._inner, this._accessToken);

  final http.Client _inner;
  final String _accessToken;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class GoogleDriveService {
  static const _driveScopes = [drive.DriveApi.driveFileScope];

  final _signIn = GoogleSignIn.instance;
  bool _initialized = false;
  GoogleSignInAccount? _currentUser;

  GoogleSignInAccount? get currentUser => _currentUser;

  /// Call once at app start. Safe to call multiple times.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      await _signIn.initialize();
      _initialized = true;
      debugPrint('[GoogleDrive] initialized successfully');
    } catch (e, st) {
      debugPrint('[GoogleDrive] initialize error: $e\n$st');
      rethrow;
    }
  }

  /// Sign in interactively (must be called from user gesture).
  /// Step 1: authenticate (Google account) → Step 2: authorize Drive scope.
  Future<bool> signIn() async {
    await ensureInitialized();
    try {
      _currentUser = await _signIn.authenticate();
      debugPrint('[GoogleDrive] signIn user: ${_currentUser?.email}');
      if (_currentUser == null) return false;

      // Request Drive scope authorization (shows consent screen).
      await _currentUser!.authorizationClient.authorizeScopes(_driveScopes);
      debugPrint('[GoogleDrive] signIn Drive scope authorized');
      return true;
    } catch (e, st) {
      debugPrint('[GoogleDrive] signIn error: $e\n$st');
      _currentUser = null;
      return false;
    }
  }

  /// Try silent sign-in on app launch.
  /// Returns true ONLY if both authentication AND Drive scope are available.
  Future<bool> signInSilently() async {
    await ensureInitialized();
    try {
      final account = await _signIn.attemptLightweightAuthentication();
      debugPrint('[GoogleDrive] attemptLightweightAuthentication: ${account?.email}');
      if (account == null) return false;
      _currentUser = account;

      // Verify Drive scope is already authorized (silent only, no UI prompt).
      final auth = await account.authorizationClient
          .authorizationForScopes(_driveScopes);
      debugPrint('[GoogleDrive] authorizationForScopes result: $auth');
      if (auth == null) {
        // Account exists but Drive was never authorized → show Connect button.
        _currentUser = null;
        return false;
      }
      return true;
    } catch (e, st) {
      debugPrint('[GoogleDrive] signInSilently error: $e\n$st');
      _currentUser = null;
      return false;
    }
  }

  Future<void> signOut() async {
    await ensureInitialized();
    await _signIn.signOut();
    _currentUser = null;
  }

  Future<drive.DriveApi?> getDriveApi() async {
    final user = _currentUser;
    if (user == null) return null;

    try {
      // Try silent first; request interactively if needed.
      GoogleSignInClientAuthorization? auth = await user.authorizationClient
          .authorizationForScopes(_driveScopes);
      auth ??= await user.authorizationClient.authorizeScopes(_driveScopes);

      final client = _AuthorizedClient(http.Client(), auth.accessToken);
      return drive.DriveApi(client);
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getAppFolderId(drive.DriveApi driveApi) async {
    try {
      const folderName = 'ChatApp Backups';
      final fileList = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed=false",
        spaces: 'drive',
      );
      if (fileList.files != null && fileList.files!.isNotEmpty) {
        return fileList.files!.first.id;
      }

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final createdFolder = await driveApi.files.create(folder);
      return createdFolder.id;
    } catch (e) {
      return null;
    }
  }

  Future<List<drive.File>> listBackups() async {
    final driveApi = await getDriveApi();
    if (driveApi == null) throw GoogleDriveException.notAuthenticated();

    final folderId = await _getAppFolderId(driveApi);
    if (folderId == null) throw GoogleDriveException.folderCreationFailed();

    try {
      final fileList = await driveApi.files.list(
        q: "'$folderId' in parents and mimeType='application/json' and name contains 'backup_' and trashed=false",
        orderBy: 'createdTime desc',
        spaces: 'drive',
        $fields: 'files(id, name, createdTime, size)',
      );
      return fileList.files ?? [];
    } catch (e) {
      throw GoogleDriveException.downloadFailed(e.toString());
    }
  }

  Future<String?> downloadBackup(String fileId) async {
    final driveApi = await getDriveApi();
    if (driveApi == null) return null;

    try {
      final media = await driveApi.files.get(
            fileId,
            downloadOptions: drive.DownloadOptions.fullMedia,
          )
          as drive.Media;

      final buffer = <int>[];
      await for (final chunk in media.stream) {
        buffer.addAll(chunk);
      }
      return utf8.decode(buffer);
    } catch (e) {
      return null;
    }
  }

  Future<bool> uploadBackup(String jsonString, String fileName) async {
    final driveApi = await getDriveApi();
    if (driveApi == null) return false;

    final folderId = await _getAppFolderId(driveApi);
    if (folderId == null) return false;

    final fileToUpload = drive.File()
      ..name = fileName
      ..parents = [folderId]
      ..mimeType = 'application/json';

    final bytes = utf8.encode(jsonString);
    final media = drive.Media(Stream.value(bytes), bytes.length);

    try {
      await driveApi.files.create(fileToUpload, uploadMedia: media);
      await _cleanupOldBackups(driveApi, folderId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _cleanupOldBackups(
    drive.DriveApi driveApi,
    String folderId,
  ) async {
    try {
      final fileList = await driveApi.files.list(
        q: "'$folderId' in parents and mimeType='application/json' and trashed=false",
        orderBy: 'createdTime desc',
        spaces: 'drive',
      );

      final files = fileList.files;
      if (files != null && files.length > 10) {
        final toDelete = files.sublist(10);
        for (final file in toDelete) {
          if (file.id != null) {
            await driveApi.files.delete(file.id!);
          }
        }
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }
}

final googleDriveServiceProvider = Provider((ref) => GoogleDriveService());
