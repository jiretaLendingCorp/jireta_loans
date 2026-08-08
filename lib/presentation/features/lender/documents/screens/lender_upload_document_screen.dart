// lib/presentation/features/lender/documents/screens/lender_upload_document_screen.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/forms/app_dropdown.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/upload_progress_widget.dart';
import '../providers/lender_documents_provider.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.account_balance_outlined,
      activeIcon: Icons.account_balance,
      label: 'My Loan',
      route: RouteConstants.lenderLoans),
  MobileNavItem(
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile),
];

const _docTypes = [
  {'label': 'Valid ID', 'value': 'valid_id'},
  {'label': 'Selfie / Photo', 'value': 'selfie'},
  {'label': 'Proof of Billing', 'value': 'proof_of_billing'},
  {'label': 'Proof of Income', 'value': 'proof_of_income'},
  {'label': 'Co-Maker Document', 'value': 'co_maker'},
  {'label': 'Other', 'value': 'other'},
];

class LenderUploadDocumentScreen extends ConsumerStatefulWidget {
  const LenderUploadDocumentScreen({super.key});

  @override
  ConsumerState<LenderUploadDocumentScreen> createState() => _State();
}

class _State extends ConsumerState<LenderUploadDocumentScreen> {
  String? _selectedType;
  Uint8List? _selectedBytes;
  String? _mimeType;
  String? _fileName;
  String? _fileSizeText;

  Future<void> _pickFromCamera() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 80);
    if (img != null) {
      final bytes = await img.readAsBytes();
      setState(() {
        _selectedBytes = bytes;
        _mimeType = 'image/jpeg';
        _fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        _fileSizeText = _kb(bytes.length);
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      final ext = file.extension?.toLowerCase() ?? '';
      final bytes = file.bytes;
      if (file.size > 5 * 1024 * 1024) {
        if (mounted) {
          showDialog(
              context: context,
              builder: (_) => const ErrorDialog(
                  message: 'File too large. Maximum size is 5MB.'));
        }
        return;
      }
      setState(() {
        _selectedBytes = bytes;
        _mimeType = ext == 'pdf'
            ? 'application/pdf'
            : 'image/${ext == 'jpg' ? 'jpeg' : ext}';
        _fileName = file.name;
        _fileSizeText = _kb(bytes?.length ?? 0);
      });
    }
  }

  String _kb(int length) => '${(length / 1024).toStringAsFixed(1)} KB';

  Future<void> _upload() async {
    if (_selectedType == null || _selectedBytes == null) return;
    final success =
        await ref.read(lenderDocumentsProvider.notifier).uploadDocument(
              bytes: _selectedBytes!,
              fileName: _fileName ?? 'document',
              docType: _selectedType!,
              mimeType: _mimeType ?? 'image/jpeg',
            );
    // Use mounted (not context.mounted) to guard all async context use
    if (success) {
      if (!mounted) return;
      await showDialog(
          context: context,
          builder: (_) =>
              const SuccessDialog(message: 'Document uploaded successfully.'));
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      if (!mounted) return;
      showDialog(
          context: context,
          builder: (_) => ErrorDialog(
              message:
                  ref.read(lenderDocumentsProvider).error ?? 'Upload failed.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderDocumentsProvider);

    return MobileScaffold(
      title: 'Upload Document',
      accentColor: AppColors.lenderPurple,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Document Type',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            AppDropdown(
              label: 'Select document type',
              value: _selectedType,
              items: _docTypes
                  .map((t) => DropdownMenuItem(
                      value: t['value']!, child: Text(t['label']!)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedType = v),
            ),
            const SizedBox(height: 20),
            const Text('Select File',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            if (_selectedBytes == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.border, style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.upload_file_outlined,
                        size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: 12),
                    const Text('Tap to upload a file',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    const Text('JPEG, PNG, PDF — Max 5MB',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textTertiary)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickFromCamera,
                            icon:
                                const Icon(Icons.camera_alt_outlined, size: 16),
                            label: const Text('Camera'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.lenderPurple,
                                side: const BorderSide(
                                    color: AppColors.lenderPurple)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickFromGallery,
                            icon: const Icon(Icons.folder_outlined, size: 16),
                            label: const Text('Browse'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.lenderPurple,
                                side: const BorderSide(
                                    color: AppColors.lenderPurple)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.lenderPurple.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.lenderPurple.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file,
                        color: AppColors.lenderPurple, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_fileName ?? 'Selected file',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis),
                          Text(
                              _fileSizeText ?? '',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _selectedBytes = null;
                        _mimeType = null;
                        _fileName = null;
                        _fileSizeText = null;
                      }),
                      icon: const Icon(Icons.close,
                          color: AppColors.textSecondary, size: 20),
                    ),
                  ],
                ),
              ),
            if (state.isUploading) ...[
              const SizedBox(height: 16),
              UploadProgressWidget(
                  fileName: _fileName ?? 'document',
                  progress: state.uploadProgress),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.info, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'Accepted: JPEG, PNG, PDF. Max 5MB per file. Documents will be reviewed by our team.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary))),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'Upload Document',
                icon: Icons.cloud_upload_outlined,
                backgroundColor: AppColors.lenderPurple,
                isLoading: state.isUploading,
                onPressed: (_selectedType != null &&
                        _selectedBytes != null &&
                        !state.isUploading)
                    ? _upload
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
