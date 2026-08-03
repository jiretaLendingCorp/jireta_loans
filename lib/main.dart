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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: 'assets/env/.env');

  assert(() {
    EnvConfig.debugPrint();
    return true;
  }());

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig
        .supabaseAnonKey, // FIX: was `publishableKey` — wrong param name for supabase_flutter 2.x
  );

  try {
    await Firebase.initializeApp();
  } catch (_) {}

  await setupDependencies();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ProviderScope(child: JiretaApp()));
}
