// lib/presentation/shared/providers/ci_detail_provider.dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/di/injection.dart';
import '../../../core/errors/error_handler.dart';
import '../../../data/datasources/remote/ci_remote_datasource.dart';
import 'realtime_refresh_mixin.dart';

/// State for a single CI assignment detail view.
class CiDetailState {
  final Map<String, dynamic>? ci;
  final bool isLoading;
  final String? error;
  const CiDetailState({this.ci, this.isLoading = false, this.error});

  // Sentinel so copyWith can distinguish "not provided" from an explicit
  // `error: null` (which must CLEAR a previous error).
  static const Object _unsetError = Object();

  CiDetailState copyWith({
    Map<String, dynamic>? ci,
    bool? isLoading,
    Object? error = _unsetError,
  }) =>
      CiDetailState(
        ci: ci ?? this.ci,
        isLoading: isLoading ?? this.isLoading,
        error: error == _unsetError ? this.error : error as String?,
      );
}

/// Loads a single CI assignment and keeps it live — re-fetches whenever the
/// `credit_investigations` / `ci_documents` tables change (rider accept,
/// report submit, documents upload, etc.) so HM/Employee details screens never
/// show a stale "awaiting acceptance" status.
class CiDetailNotifier extends StateNotifier<CiDetailState>
    with RealtimeRefreshMixin<CiDetailState> {
  final CiRemoteDataSource _ds;
  final String ciId;

  CiDetailNotifier(this._ds, this.ciId)
      : super(const CiDetailState(isLoading: true)) {
    bindRealtimeRefresh(['credit_investigations', 'ci_documents'],
        refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final ci = await _ds.getCiDetails(ciId);
      state = state.copyWith(ci: ci, isLoading: false, error: null);
    } catch (e) {
      if (silent && state.ci != null) return;
      state = state.copyWith(isLoading: false, error: _describeError(e));
    }
  }

  /// HM-only: palitan ang isang evidence photo ng bagong piniling larawan.
  ///
  /// Ang buong file ay ipinapadala bilang base64 (isang POST) at ang row sa
  /// `ci_documents` ay ina-update sa server — kaya ang id, `document_type` at
  /// pagkakasunod-sunod ng ebidensya ay hindi nagbabago. Nagre-refresh ito ng
  /// detalye pagkatapos, para agad na lumabas ang bagong larawan.
  ///
  /// Returns `null` kapag tagumpay, o user-facing error message kapag nabigo.
  Future<String?> replaceEvidencePhoto({
    required String documentId,
    required XFile file,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      await _ds.replaceCiDocument(
        ciId: ciId,
        documentId: documentId,
        fileName: file.name,
        mimeType: _mimeTypeFor(file.name),
        contentBase64: base64Encode(bytes),
      );
      await fetch(silent: true);
      return null;
    } catch (e) {
      final message = ErrorHandler.handle(e).message;
      return message.isEmpty
          ? 'Failed to replace the photo. Please try again.'
          : message;
    }
  }

  static String _mimeTypeFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  String _describeError(Object e) {
    final message = e.toString();
    if (message.contains('Unable to reach server') ||
        message.contains('No internet')) {
      return 'Cannot connect to server. Check your connection and try again.';
    }
    if (message.contains('timed out')) {
      return 'Request timed out. Please try again.';
    }
    if (message.contains('UNAUTHORIZED')) {
      return 'Session expired. Please log in again.';
    }
    return 'Failed to load CI details. Please try again.';
  }
}

final ciDetailProvider = AutoDisposeStateNotifierProvider.family<
    CiDetailNotifier, CiDetailState, String>((ref, ciId) {
  return CiDetailNotifier(sl<CiRemoteDataSource>(), ciId);
});
