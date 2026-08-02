// lib/core/config/env_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  EnvConfig._();

  static String get supabaseUrl {
    final v = dotenv.env['SUPABASE_URL'];
    if (v == null || v.isEmpty) throw Exception('SUPABASE_URL not configured');
    return v;
  }

  static String get supabaseAnonKey {
    final v = dotenv.env['SUPABASE_ANON_KEY'];
    if (v == null || v.isEmpty) {
      throw Exception('SUPABASE_ANON_KEY not configured');
    }
    return v;
  }

  static String get edgeFunctionsUrl {
    final v = dotenv.env['EDGE_FUNCTIONS_URL'];
    if (v == null || v.isEmpty) {
      throw Exception('EDGE_FUNCTIONS_URL not configured');
    }
    return v;
  }

  static String get googleMapsApiKey {
    return dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  }

  static String get appEnv {
    return dotenv.env['APP_ENV'] ?? 'development';
  }

  static bool get isProduction => appEnv == 'production';
  static bool get isDevelopment => appEnv == 'development';
}
