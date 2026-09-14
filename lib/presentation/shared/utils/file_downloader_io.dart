// lib/presentation/shared/utils/file_downloader_io.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> saveFile(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(file.path);
}

/// Sa mobile/desktop, binuksan ang URL sa browser/downloader ng device.
/// Nagbabalik ng `true` kapag nai-trigger ang pagbukas.
Future<bool> downloadFromUrl(String url, {String? filename}) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}