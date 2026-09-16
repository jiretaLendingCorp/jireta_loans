// lib/presentation/shared/utils/file_downloader_web.dart
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// MIME type na ginagamit ng browser kapag sine-save ang file. Mahalaga ito
/// para sa `.apk` — kapag mali/empty ang type, may browsers na nag-o-open ng
/// file sa tab imbes na i-save ito.
String _mimeTypeFor(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.apk')) return 'application/vnd.android.package-archive';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.csv')) return 'text/csv';
  return 'application/octet-stream';
}

Future<void> saveFile(Uint8List bytes, String filename) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: _mimeTypeFor(filename)),
  );
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

String _fileNameFromUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final segments = path.split('/').where((s) => s.isNotEmpty);
  return segments.isEmpty ? 'download' : segments.last;
}

/// Sinusuri kung tunay na file ang naka-serve sa URL — `false` kapag HTML/JSON
/// (error page o ang SPA fallback na `/index.html`) o hindi `ok` ang status,
/// `true` kapag mukhang file, at `null` kapag hindi masuri.
///
/// `HEAD` lang ang request: hindi binubuksan/bina-buffer ang buong file, kaya
/// walang 141 MB na memory na kakailanganin sa phone. Ang browser mismo ang
/// nagda-download ng file pagkatapos (may progreso at resume).
Future<bool?> _urlServesAFile(String url) async {
  try {
    final response =
        await web.window.fetch(url.toJS, web.RequestInit(method: 'HEAD')).toDart;
    if (!response.ok) return false;

    final type = response.headers.get('content-type')?.toLowerCase() ?? '';
    if (type.contains('text/html') || type.contains('application/json')) {
      return false;
    }

    // Error page ang maliliit na tugon (hal. "Not Found" na JSON).
    final length = int.tryParse(response.headers.get('content-length') ?? '');
    if (length != null && length < 512) return false;

    return true;
  } catch (_) {
    // Cross-origin na walang CORS header o network error — hindi masusuri, kaya
    // hindi haharangin ang download (best effort).
    return null;
  }
}

/// Sinusuri sa GitHub REST API kung may asset na ganito ang pangalan sa
/// release — `null` kapag hindi GitHub Releases URL ang ibinigay.
///
/// Kailangan ito dahil **walang `Access-Control-Allow-Origin` header** ang
/// asset CDN ng GitHub (`release-assets.githubusercontent.com`), kaya palaging
/// `null` ang resulta ng `_urlServesAFile` doon. Malaking problema iyon sa
/// nawawalang release: 9-byte na `text/plain` na "Not Found" ang ibinabalik ng
/// github.com, at iyon ang mada-download ng user na akala nila ay APK.
///
/// Ang `api.github.com` naman ay may `Access-Control-Allow-Origin: *`, kaya
/// maaasahan ito. Sinusuportahan ang dalawang anyo ng URL:
/// `/OWNER/REPO/releases/latest/download/ASSET` at
/// `/OWNER/REPO/releases/download/TAG/ASSET`.
Future<bool?> _githubReleaseAssetExists(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != 'github.com') return null;

  final segments = uri.pathSegments;
  if (segments.length < 6 || segments[2] != 'releases') return null;

  final owner = segments[0];
  final repo = segments[1];

  final String assetName;
  final String releasePath;
  if (segments[3] == 'latest' && segments[4] == 'download') {
    assetName = segments[5];
    releasePath = '$owner/$repo/releases/latest';
  } else if (segments[3] == 'download') {
    final tag = segments[4];
    assetName = segments[5];
    releasePath = '$owner/$repo/releases/tags/$tag';
  } else {
    return null;
  }

  try {
    final response = await web.window
        .fetch('https://api.github.com/repos/$releasePath'.toJS)
        .toDart;
    if (!response.ok) return false;

    final body = (await response.text().toDart).toDart;
    final data = jsonDecode(body);
    if (data is! Map) return null;

    final assets = data['assets'];
    if (assets is! List) return null;
    return assets
        .whereType<Map>()
        .any((asset) => asset['name'] == assetName);
  } catch (_) {
    return null;
  }
}

/// Nag-download ng remote file (hal. Android APK) NANG HINDI umaalis ang user
/// sa kasalukuyang page.
///
/// Sinusuri muna kung file nga ang nasa URL bago i-trigger ang download, para
/// hindi HTML/error page ang makuha ng user na akala nila ay APK. Nagbabalik ng
/// `false` kapag tiyak na wala/HTML ang file para makapagpakita ng error ang UI.
///
/// Kapag hindi masuri (CORS/network) at hindi GitHub Releases URL, tuloy pa rin
/// ang download — best effort.
Future<bool> downloadFromUrl(String url, {String? filename}) async {
  final servesAFile = await _urlServesAFile(url);
  if (servesAFile == true) return _downloadViaAnchor(url, filename);
  if (servesAFile == false) return false;

  // Hindi masuri sa HEAD (CORS) — kung GitHub Releases, doon magtanong.
  final assetExists = await _githubReleaseAssetExists(url);
  if (assetExists == false) return false;

  return _downloadViaAnchor(url, filename);
}

/// Plain anchor download — ang browser ang humahawak ng streaming papuntang
/// disk, kaya normal ang progreso/resume. Kapag cross-origin at hindi
/// pinapayagan ang `download` attribute, ang `Content-Disposition` header ng
/// server (hal. GitHub Releases) ang nagpapa-download pa rin.
bool _downloadViaAnchor(String url, String? filename) {
  try {
    final anchor = web.HTMLAnchorElement()..style.display = 'none';
    anchor.href = url;
    anchor.download = (filename != null && filename.isNotEmpty)
        ? filename
        : _fileNameFromUrl(url);
    anchor.rel = 'noopener';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}