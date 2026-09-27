// lib/core/services/google_maps_loader.dart
//
// `ensureGoogleMapsLoaded()` — tinitiyak na naka-load na ang Google Maps
// JavaScript API bago buuin ang `GoogleMap` widget.
//
// Mahalaga lang ito sa web: `google_maps_flutter_web` ay umaasa sa
// `google.maps` global na dinedeklara ng `<script>` tag ng Maps JS API.
// Sa Android/iOS ang native SDK ang naglo-load (manifest / AppDelegate), kaya
// no-op ang [ensureGoogleMapsLoaded] doon.
export 'google_maps_loader_stub.dart'
    if (dart.library.html) 'google_maps_loader_web.dart';
