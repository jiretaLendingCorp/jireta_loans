// lib/presentation/shared/providers/connectivity_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/connectivity_service.dart';

/// Provides the current online/offline status (true = online).
///
/// The first value is resolved from a one-shot check so login screens know the
/// state immediately instead of waiting for the plugin's change stream.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final service = ConnectivityService.instance;
  yield await service.isOnline;
  yield* service.onConnectionChanged;
});
