// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, avoid_print
// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env_config.dart';
import 'core/di/injection.dart';
import 'core/services/fcm_service.dart';
import 'core/utils/logger.dart';
import 'core/utils/url_strategy.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    print('FlutterError: ${details.exception}');
    print(details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    print('PlatformDispatcher error: $error');
    print(stack);
    return true;
  };

  await dotenv.load(fileName: 'assets/env/.env');

  // ── Production placeholder guard ────────────────────────────────────────
  // If the bundled .env still contains your-project.supabase.co the app was
  // built without Vercel env vars (common after adding vars but forgetting
  // to Redeploy). Showing a clear banner is far more actionable than
  // "ERR_NAME_NOT_RESOLVED your-project.supabase.co" on every API call.
  if (EnvConfig.isPlaceholderEnv) {
    // No secrets/URLs printed here on purpose.
    runApp(const _PlaceholderEnvApp());
    return;
  }

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    publishableKey: EnvConfig.supabaseAnonKey,
  );

  try {
    // Explicit options (DefaultFirebaseOptions) instead of relying on native
    // init — standard FlutterFire pattern, works regardless of how the
    // google-services resources were generated.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Log, don't swallow: a failed init here means push notifications will
    // not work, and the FCM service must not crash the app over it.
    AppLogger.error('Firebase init failed: $e');
  }

  await setupDependencies();

  // FCM push channel (mobile) — permissions, token registration/refresh,
  // foreground display and tap deep-linking. No-op on web/desktop.
  try {
    await FcmService.instance.initialize();
  } catch (e) {
    AppLogger.error('FCM init failed: $e');
  }

  // Use clean path-based URLs (e.g. /login) instead of hash URLs (#/login) on web.
  configureUrlStrategy();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ProviderScope(child: JiretaApp()));
}

/// Full-screen error shown when the web build was produced without real
/// Vercel env vars. Generic message only — no API URL/key is hard-coded in
/// Flutter per user request. Details are in Vercel build logs.
class _PlaceholderEnvApp extends StatelessWidget {
  const _PlaceholderEnvApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jireta — Config Missing',
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              margin: const EdgeInsets.all(24),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 32),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Production configuration missing',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This web build was deployed without required env vars, so the app cannot reach the server. Every login/register will show “Cannot connect to server”.',
                      style: TextStyle(color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    const Text('Fix in Vercel (takes 2 min):', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const SelectableText(
                      '1. Vercel Dashboard → jireta → Settings → Environment Variables\n'
                      '2. Add for Production (and Preview) — copy values from Supabase Dashboard → Settings → API:\n'
                      '   SUPABASE_URL\n'
                      '   SUPABASE_ANON_KEY (Publishable key)\n'
                      '   EDGE_FUNCTIONS_URL (= SUPABASE_URL + /functions/v1)\n'
                      '   APP_ENV=production\n'
                      '3. Deployments → ••• → Redeploy (uncheck “Use existing Build Cache”)\n'
                      '4. Verify build logs show SUPABASE_URL is set (not placeholder)',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'If you already added the vars but still see this screen, you forgot the Redeploy — env vars only take effect on the next build.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No API URL/key is hard-coded in the app — all values come from Vercel env at build time (assets/env/.env).',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
