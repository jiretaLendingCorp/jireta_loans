// lib/presentation/shared/widgets/forms/app_file_picker.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_colors.dart';

class PickedFile {
  final String name;
  final String path;
  final String mimeType;
  final int bytes;

  const PickedFile({
    required this.name,
    required this.path,
    required this.mimeType,
    required this.bytes,
  });
}

class AppFilePicker extends StatelessWidget {
  final PickedFile? value;
  final ValueChanged<PickedFile?> onChanged;
  final String label;
  final List<String> allowedExtensions;
  final int maxSizeMb;
  final bool allowCamera;

  const AppFilePicker({
    super.key,
    this.value,
    required this.onChanged,
    this.label = 'Upload File',
    this.allowedExtensions = const ['jpg', 'jpeg', 'png', 'pdf'],
    this.maxSizeMb = 5,
    this.allowCamera = true,
  });

  Future<void> _pick(BuildContext context) async {
    final options = <String>[];
    if (allowCamera) options.addAll(['Camera', 'Gallery']);
    options.add('File');

    if (allowCamera && context.mounted) {
      await showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _camera();
                }),
            ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _gallery();
                }),
            ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Choose File'),
                onTap: () {
                  Navigator.pop(ctx);
                  _file();
                }),
            const SizedBox(height: 8),
          ]),
        ),
      );
    } else {
      await _file();
    }
  }

  Future<void> _camera() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 85);
    if (img == null) return;
    final file = File(img.path);
    final size = await file.length();
    if (size > maxSizeMb * 1024 * 1024) return;
    onChanged(PickedFile(
        name: img.name, path: img.path, mimeType: 'image/jpeg', bytes: size));
  }

  Future<void> _gallery() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img == null) return;
    final file = File(img.path);
    final size = await file.length();
    if (size > maxSizeMb * 1024 * 1024) return;
    onChanged(PickedFile(
        name: img.name, path: img.path, mimeType: 'image/jpeg', bytes: size));
  }

  Future<void> _file() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.size > maxSizeMb * 1024 * 1024) return;
    final mime =
        f.extension == 'pdf' ? 'application/pdf' : 'image/${f.extension}';
    onChanged(PickedFile(
        name: f.name, path: f.path ?? '', mimeType: mime, bytes: f.size));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label.isNotEmpty) ...[
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
      ],
      GestureDetector(
        onTap: () => _pick(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: value != null ? AppColors.deepNavy : AppColors.border,
              width: value != null ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
            color: value != null
                ? AppColors.deepNavy.withValues(alpha: 0.03)
                : Colors.white,
          ),
          child: value != null
              ? Row(children: [
                  const Icon(Icons.attach_file,
                      size: 20, color: AppColors.deepNavy),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(value!.name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.deepNavy),
                            overflow: TextOverflow.ellipsis),
                        Text('${(value!.bytes / 1024).toStringAsFixed(1)} KB',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textHint)),
                      ])),
                  GestureDetector(
                      onTap: () => onChanged(null),
                      child: const Icon(Icons.close,
                          size: 18, color: AppColors.error)),
                ])
              : Column(children: [
                  Icon(Icons.cloud_upload_outlined,
                      size: 36, color: AppColors.textHint.withValues(alpha: 0.7)),
                  const SizedBox(height: 8),
                  Text('Tap to upload (max ${maxSizeMb}MB)',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textHint)),
                  const SizedBox(height: 4),
                  Text(allowedExtensions.join(', ').toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint)),
                ]),
        ),
      ),
    ]);
  }
}
