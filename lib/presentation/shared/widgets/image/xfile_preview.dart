// lib/presentation/shared/widgets/image/xfile_preview.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Renders a locally-picked image on any platform (mobile + web).
///
/// `dart:io`'s `File` does not exist on web, so `Image.file(...)` throws
/// `Unsupported operation`. This widget reads the picked `XFile` bytes and
/// renders them with `Image.memory` instead.
class XFilePreview extends StatefulWidget {
  final XFile file;
  final double? width;
  final double? height;
  final BoxFit fit;

  const XFilePreview({
    super.key,
    required this.file,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<XFilePreview> createState() => _XFilePreviewState();
}

class _XFilePreviewState extends State<XFilePreview> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant XFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.file.readAsBytes();
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      // Ignore unreadable files; fallback renders an empty box.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0x11000000),
      );
    }
    return Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}
