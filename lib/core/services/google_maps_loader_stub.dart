// lib/core/services/google_maps_loader_stub.dart
//
// Android / iOS / desktop: ang native Google Maps SDK ang naglo-load ng mapa
// (AndroidManifest meta-data / AppDelegate), kaya wala tayong kailangang gawin.
// Ginagamit din ito sa mga widget test.

/// No-op sa non-web platforms.
Future<void> ensureGoogleMapsLoaded() async {}
