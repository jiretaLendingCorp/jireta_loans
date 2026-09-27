// lib/core/services/google_maps_loader_web.dart
import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../config/env_config.dart';

/// `id` ng `<script>` element na ini-inject natin — hindi tayo nagdadagdag ng
/// pangalawa dahil nag-e-error ang Google kapag dalawang beses na-load ang JS
/// API sa isang page ("You have included the Google Maps JavaScript API
/// multiple times on this page").
const String _scriptElementId = 'jireta-google-maps-js';

/// Ang mismong endpoint na hinahanap ng `google_maps_flutter_web`.
const String _mapsApiUrl = 'https://maps.googleapis.com/maps/api/js';

/// Pangalan ng global callback na itinatawag ng Maps JS API kapag kumpleto na
/// ang pag-load nito. Kailangan ito kasabay ng `loading=async` — kapag async,
/// HINDI na ang `load` event ng `<script>` ang senyas ng pagiging ready ng API.
const String _readyCallbackName = 'jiretaGoogleMapsReady';

/// Mga placeholder na laman ng `.env.example` at ng dating `web/index.html`.
/// Hindi tunay na key — walang saysay na i-load.
const Set<String> _placeholderKeys = {
  'YOUR_GOOGLE_MAPS_API_KEY',
  'your-google-maps-key',
};

Future<void>? _inFlight;

/// Sinasalo ang `window.gm_authFailure` global ng Maps JS API (tinatawag ng
/// Google kapag tinanggihan ang key) para hindi tayo tahimik na blangkong
/// mapa lang kapag mali ang key.
@JS('gm_authFailure')
external set _gmAuthFailureHandler(JSFunction? handler);

/// Nakasalang handler para sa `window.jiretaGoogleMapsReady` — ang global na
/// tinatawag ng Maps JS API kapag ready na itong gamitin.
@JS('jiretaGoogleMapsReady')
external set _mapsReadyCallback(JSFunction? handler);

/// Nakasalang `gm_authFailure` handler: kapag tinanggihan ng Google ang key,
/// hindi na tayo tahimik na blangkong mapa lang — may malinaw na dahilan at
/// sunod-sunod na dapat ayusin sa Google Cloud Console.
void _onAuthFailure() {
  debugPrint(
    '[GoogleMaps] Google REJECTED GOOGLE_MAPS_API_KEY for the Maps JavaScript '
    'API (gm_authFailure). The map will stay blank until this is fixed.\n'
    '  Check the key in Google Cloud Console → APIs & Services → Credentials:\n'
    '   • "API restrictions" must include Maps JavaScript API (and Routes/Directions/'
    'Geocoding if those web services are used);\n'
    '   • "Application restrictions" → HTTP referrers must include this origin '
    '(add http://localhost:* for local dev), and the production domains;\n'
    '   • the Maps JavaScript API must be enabled on the project and billing active.\n'
    '  The browser console shows the exact code from the API itself '
    '("Google Maps JavaScript API error: <Code>MapError").',
  );
}

/// Idinadagdag ang Google Maps JavaScript API `<script>` **sa runtime**, gamit
/// ang `GOOGLE_MAPS_API_KEY` mula sa `assets/env/.env`.
///
/// BAKIT RUNTIME AT HINDI `<script>` SA `web/index.html`:
/// ang `web/index.html` ay naka-commit. Doon, (a) nabubunyag ang key sa git
/// history kahit git-ignored ang `.env`, at (b) kailangang i-`sed` ito ng
/// `scripts/vercel-build.sh` tuwing release build — kaya hindi umiiral ang
/// key sa lokal na `flutter run -d chrome`. Ito ang dati naging sanhi ng
/// blangkong mapa (placeholder na `YOUR_GOOGLE_MAPS_API_KEY` ang na-load).
/// Ngayon, iisa lang ang source of truth: `assets/env/.env` (git-ignored),
/// pareho para sa dev at release.
///
/// No-op kapag nasa non-web platform, walang key, placeholder ang key, o
/// naka-load/naka-inject na ang API.
Future<void> ensureGoogleMapsLoaded() => _inFlight ??= _load();

Future<void> _load() async {
  if (web.document.getElementById(_scriptElementId) != null) return;

  final key = EnvConfig.googleMapsApiKey.trim();
  if (key.isEmpty || _placeholderKeys.contains(key)) {
    debugPrint(
      '[GoogleMaps] GOOGLE_MAPS_API_KEY is missing or still a placeholder — '
      'the Live Tracking map will stay blank. Set it in assets/env/.env '
      '(see assets/env/.env.example).',
    );
    return;
  }

  // Nakasalang `gm_authFailure` handler: kapag tinanggihan ng Google ang key,
  // may malinaw na dahilan sa console imbes na blangkong mapa lamang. Ang API
  // mismo ang naglo-log ng exact code (hal. `ApiTargetBlockedMapError` = hindi
  // kasama ang Maps JavaScript API sa "API restrictions" ng key).
  // Kailangang nakalista BAGO ma-load ang script — doon ito tinatawag.
  _gmAuthFailureHandler = _onAuthFailure.toJS;

  final completer = Completer<void>();

  void finish() {
    if (!completer.isCompleted) completer.complete();
  }

  // Hindi na ang `load` event ng script ang hinihintay: sa `loading=async`,
  // ang `callback` param ang tinatawag ng Google kapag kumpleto na ang API
  // ("no JavaScript code is triggered by the script's load event"). Ito rin
  // ang nagtatanggal ng console warning na "Google Maps JavaScript API has
  // been loaded directly without loading=async".
  _mapsReadyCallback = (() => finish()).toJS;

  final script = web.HTMLScriptElement()
    ..id = _scriptElementId
    ..src =
        '$_mapsApiUrl?key=$key&loading=async&callback=$_readyCallbackName';
  script.addEventListener(
    'error',
    ((web.Event _) {
      debugPrint(
        '[GoogleMaps] Failed to load the Maps JavaScript API — check that the '
        'key is enabled for "Maps JavaScript API" and allows this origin '
        '(HTTP referrer restrictions).',
      );
      finish();
    }).toJS,
  );

  // Safety net: kapag hindi tumawag ang callback (hal. na-block ng adblocker o
  // offline), hindi dapat ma-stuck nang tuluyan ang app startup.
  final watchdog = Timer(const Duration(seconds: 15), () {
    debugPrint(
      '[GoogleMaps] The Maps JS API ready callback did not fire within 15s — '
      'continuing, but the map may stay blank. Check the network tab.',
    );
    finish();
  });

  web.document.head?.appendChild(script);
  await completer.future;
  watchdog.cancel();
}
