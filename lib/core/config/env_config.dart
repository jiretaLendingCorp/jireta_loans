// lib/core/config/env_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  EnvConfig._();

  static String get supabaseUrl {
    final v = dotenv.env['SUPABASE_URL'];
    if (v == null || v.isEmpty) {
      throw StateError(
        'SUPABASE_URL is not set.\n'
        'Check assets/env/.env and ensure it is listed in pubspec.yaml assets.',
      );
    }
    return v;
  }

  /// The Supabase publishable / anon key.
  ///
  /// Local dev (new CLI):  sb_publishable_...   (from `supabase status`)
  /// Production (cloud):   eyJ...               (from Dashboard → Settings → API)
  ///
  /// Both formats are accepted — do NOT add a startsWith('eyJ') guard here.
  /// The new Supabase CLI no longer issues JWT anon keys for local dev.
  static String get supabaseAnonKey {
    final v = dotenv.env['SUPABASE_ANON_KEY'];
    if (v == null || v.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY is not set.\n'
        'Run `supabase status` and copy the "Publishable" key.',
      );
    }
    return v;
  }

  static String get edgeFunctionsUrl {
    var v = dotenv.env['EDGE_FUNCTIONS_URL'];
    // Fallback: derive from SUPABASE_URL when EDGE_FUNCTIONS_URL was not set
    // (e.g. Vercel env only has SUPABASE_URL). This prevents a hard crash in
    // production that previously surfaced as "Cannot connect to server".
    if (v == null || v.isEmpty) {
      final supa = dotenv.env['SUPABASE_URL'];
      if (supa != null && supa.isNotEmpty) {
        v = '${supa.replaceAll(RegExp(r'/$'), '')}/functions/v1';
      }
    }
    if (v == null || v.isEmpty) {
      throw StateError(
        'EDGE_FUNCTIONS_URL is not set.\n'
        'It should be \$SUPABASE_URL/functions/v1',
      );
    }
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  /// True when the bundled .env still contains the vercel-build.sh placeholder
  /// (Vercel env vars were missing at build time). Used by
  /// [ConnectivityService] to avoid marking the app "offline" due to DNS
  /// failure for your-project.supabase.co.
  static bool get isPlaceholderEnv =>
      (dotenv.env['SUPABASE_URL'] ?? '').contains('your-project.supabase.co') ||
      (dotenv.env['EDGE_FUNCTIONS_URL'] ?? '')
          .contains('your-project.supabase.co');

  static String get googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  static String get xenditPublicKey => dotenv.env['XENDIT_PUBLIC_KEY'] ?? '';

  static String get appEnv => dotenv.env['APP_ENV'] ?? 'development';

  static bool get isProduction => appEnv == 'production';
  static bool get isDevelopment => appEnv == 'development';

  static void debugPrint() {
    final url = dotenv.env['SUPABASE_URL'] ?? '(not set)';
    final key = dotenv.env['SUPABASE_ANON_KEY'] ?? '(not set)';
    final keyPreview = key.length > 24 ? '${key.substring(0, 24)}...' : key;
    final efUrl = dotenv.env['EDGE_FUNCTIONS_URL'] ?? '(not set)';
    // ignore: avoid_print
    print('''
╔══════════════════════════════════════════════════╗
║  EnvConfig                                       ║
╠══════════════════════════════════════════════════╣
║  APP_ENV:            $appEnv
║  SUPABASE_URL:       $url
║  SUPABASE_ANON_KEY:  $keyPreview
║  EDGE_FUNCTIONS_URL: $efUrl
╚══════════════════════════════════════════════════╝
''');
  }
}
