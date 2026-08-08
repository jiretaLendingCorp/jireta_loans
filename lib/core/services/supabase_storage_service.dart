// lib/core/services/supabase_storage_service.dart
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../security/secure_storage.dart';
import '../utils/logger.dart';

class SupabaseStorageService {
  SupabaseStorageService._();
  static final SupabaseStorageService instance = SupabaseStorageService._();

  final _storage = Supabase.instance.client.storage;
  final _uuid = const Uuid();

  static const int maxSizeBytes = 5 * 1024 * 1024;
  static const List<String> allowedMimes = [
    'image/jpeg',
    'image/png',
    'application/pdf',
  ];

  /// The app authenticates through custom Edge Functions (auth-login /
  /// auth-verify-otp) and stores the returned JWT in SecureStorage, but it
  /// never signs in the supabase_flutter client itself. Without a session the
  /// storage API runs with the anon key, `auth.uid()` is NULL, and every
  /// upload fails with "new row violates row-level security".
  /// This restores the session from the stored tokens before any upload.
  Future<void> _ensureSession() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) return;
    final accessToken = await SecureStorage.getAccessToken();
    final refreshToken = await SecureStorage.getRefreshToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Not signed in');
    }
    try {
      await client.auth.setSession(
        refreshToken ?? '',
        accessToken: accessToken,
      );
    } catch (e) {
      AppLogger.error('[Storage] Failed to restore session: $e');
      rethrow;
    }
  }

  Future<String?> uploadFile({
    required Uint8List bytes,
    required String fileName,
    required String bucket,
    required String folder,
    String contentType = 'application/octet-stream',
    int maxBytes = maxSizeBytes,
  }) async {
    try {
      await _ensureSession();

      if (bytes.length > maxBytes) {
        throw Exception(
            'File exceeds maximum size of ${maxBytes ~/ 1024 ~/ 1024}MB');
      }

      final ext = fileName.split('.').last.toLowerCase();
      final storedName = '${_uuid.v4()}.$ext';
      final path = '$folder/$storedName';

      await _storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );

      return path;
    } catch (e) {
      AppLogger.error('[Storage] Upload error: $e');
      rethrow;
    }
  }

  Future<String> getSignedUrl({
    required String bucket,
    required String path,
    int expiresIn = 3600,
  }) async {
    await _ensureSession();
    final url = await _storage.from(bucket).createSignedUrl(path, expiresIn);
    return url;
  }
}
