// lib/presentation/shared/utils/file_downloader.dart
//
// `saveFile` — in-memory bytes (PDF/Excel exports).
// `downloadFromUrl` — remote file (hal. ang Android APK sa login page).
export 'file_downloader_stub.dart'
    if (dart.library.io) 'file_downloader_io.dart'
    if (dart.library.html) 'file_downloader_web.dart';