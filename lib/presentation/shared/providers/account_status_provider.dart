// lib/presentation/shared/providers/account_status_provider.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/realtime_service.dart';
import '../../../core/utils/logger.dart';
import 'auth_state_provider.dart';

/// `users.account_status` code na ibinibigay ng escalation rule (00152) kapag
/// pangalawa nang natapos ang loan term ng lender na may natitirang utang.
const String kAccountStatusPaused = 'paused';

/// Live na `users.account_status` ng kasalukuyang naka-login na user.
///
/// `null` kapag hindi authenticated o hindi pa nakuha ang value. Nakikinig ito
/// sa Realtime (`users` table), kaya kapag in-unpause ng staff ang account
/// habang bukas pa ang app ng lender, awtomatikong nagre-refresh at nawawala
/// ang blocking modal — walang kailangang logout/login.
///
/// Kapag nabigo ang fetch (offline, RLS, atbp.) ay `null` ang ibinabalik para
/// HINDI ma-block ang app dahil lang sa network hiccup.
final accountStatusProvider = FutureProvider<String?>((ref) async {
  final userId = ref.watch(
    authStateProvider.select(
      (s) => s.isAuthenticated ? s.user?.id : null,
    ),
  );
  if (userId == null || userId.isEmpty) return null;

  void onUserChanged() => ref.invalidateSelf();
  unawaited(
    RealtimeService.instance
        .subscribe('users', onUserChanged)
        .catchError((Object _) {}),
  );
  ref.onDispose(
    () => RealtimeService.instance.unsubscribe('users', onUserChanged),
  );

  try {
    final row = await Supabase.instance.client
        .from('users')
        .select('account_status')
        .eq('id', userId)
        .maybeSingle();
    return (row?['account_status'] as String?) ?? 'active';
  } catch (e) {
    AppLogger.debug('[AccountStatus] fetch failed: $e');
    return null;
  }
});

/// `true` kapag naka-pause ang account ng kasalukuyang user (lender).
final isAccountPausedProvider = Provider<bool>((ref) {
  final status = ref.watch(accountStatusProvider).valueOrNull;
  return status == kAccountStatusPaused;
});
