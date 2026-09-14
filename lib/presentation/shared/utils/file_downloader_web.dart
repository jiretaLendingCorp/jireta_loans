// lib/presentation/shared/utils/file_downloader_web.dart
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> saveFile(Uint8List bytes, String filename) async {
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// Nag-download ng remote file (hal. Android APK) NANG HINDI umaalis ang
/// user sa kasalukuyang page — isang hidden anchor na may `download`
/// attribute ang ginagamit imbes na i-redirect sa file.
///
/// Nagbabalik ng `true` kapag nai-trigger ang download.
Future<bool> downloadFromUrl(String url, {String? filename}) async {
  try {
    final anchor = web.HTMLAnchorElement()..style.display = 'none';
    anchor.href = url;
    if (filename != null && filename.isNotEmpty) {
      anchor.download = filename;
      // Fallback kapag cross-origin ang file: bubukas sa bagong tab ang
      // browser KUNG hindi papayagan ang `download` attribute.
      anchor.target = '_blank';
      anchor.rel = 'noopener';
    }
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}