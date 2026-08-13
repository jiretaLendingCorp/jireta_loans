// lib/presentation/features/lender/account_upgrade/screens/valid_id_scanner_screen.dart
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/theme/app_colors.dart';

/// Full-screen Valid ID Scanner UI.
///
/// Shows a live camera preview inside a scanning frame with an animated scan
/// line. If the camera cannot be initialized (e.g. web without a camera or a
/// denied permission) it falls back to the device camera via image_picker.
/// Once a photo is captured it shows a confirmation preview before returning
/// the image bytes to the caller through `Navigator.pop<Uint8List>`.
class ValidIdScannerScreen extends StatefulWidget {
  const ValidIdScannerScreen({super.key});

  @override
  State<ValidIdScannerScreen> createState() => _ValidIdScannerScreenState();
}

class _ValidIdScannerScreenState extends State<ValidIdScannerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanCtrl;
  CameraController? _controller;
  bool _cameraReady = false;
  bool _cameraUnavailable = false;
  Uint8List? _captured;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraUnavailable = true);
        return;
      }
      CameraDescription selected;
      try {
        selected = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
      } on StateError {
        selected = cameras.first;
      }
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _cameraReady = true);
    } catch (_) {
      if (mounted) setState(() => _cameraUnavailable = true);
    }
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ctrl = _controller;
      if (_cameraReady && ctrl != null) {
        final file = await ctrl.takePicture();
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() => _captured = bytes);
      } else {
        await _captureViaPicker(ImageSource.camera);
      }
    } catch (_) {
      await _captureViaPicker(ImageSource.camera);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _captureViaPicker(ImageSource source) async {
    try {
      final img = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (img == null) return;
      final bytes = await img.readAsBytes();
      if (!mounted) return;
      setState(() => _captured = bytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (img == null) return;
      final bytes = await img.readAsBytes();
      if (!mounted) return;
      setState(() => _captured = bytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _usePhoto() {
    final bytes = _captured;
    if (bytes == null) return;
    Navigator.of(context).pop(bytes);
  }

  void _retake() => setState(() => _captured = null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: _captured == null ? _buildScanner(context) : _buildPreview(context),
    );
  }

  Widget _buildScanner(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Valid ID Scanner',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _VignettePainter(),
                  ),
                ),
                AspectRatio(
                  aspectRatio: 1.586,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _cameraReady
                              ? _buildCameraPreview()
                              : Container(color: const Color(0xFF101A2E)),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.lenderBlueLight.withValues(
                              alpha: 0.45,
                            ),
                            width: 1,
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _scanCtrl,
                        builder: (context, _) {
                          return Align(
                            alignment: Alignment(
                                0, -1 + 2 * _scanCtrl.value),
                            child: Container(
                              height: 2,
                              margin: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppColors.lenderBlueLight,
                                    Colors.transparent,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.lenderBlueLight
                                        .withValues(alpha: 0.8),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const _CornerMarker(
                          top: true, left: true),
                      const _CornerMarker(top: true, right: true),
                      const _CornerMarker(bottom: true, left: true),
                      const _CornerMarker(bottom: true, right: true),
                      if (!_cameraReady && !_cameraUnavailable)
                        const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.lenderBlueLight,
                            strokeWidth: 2.5,
                          ),
                        )
                      else if (_cameraUnavailable)
                        const Center(
                          child: Icon(
                            Icons.no_photography_outlined,
                            color: Colors.white38,
                            size: 44,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Position your government-issued ID within the frame.\nMake sure all corners are clearly visible.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ScannerAction(
                label: 'Gallery',
                icon: Icons.photo_library_outlined,
                onTap: _busy ? null : _pickFromGallery,
              ),
              const SizedBox(width: 20),
              _ScannerAction(
                label: 'Capture',
                icon: Icons.camera_alt,
                filled: true,
                busy: _busy,
                onTap: _busy ? null : _capture,
              ),
              const SizedBox(width: 20),
              _ScannerAction(
                label: 'Cancel',
                icon: Icons.close,
                onTap: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final ctrl = _controller;
    if (ctrl == null) return const SizedBox.expand();
    final size = ctrl.value.previewSize;
    if (size == null) return const SizedBox.expand();
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: CameraPreview(ctrl),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final bytes = _captured!;
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    color: AppColors.lenderBlueLight, size: 24),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Confirm your ID photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Make sure the ID is fully visible and not blurry.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ScannerConfirmButton(
                label: 'Retake',
                icon: Icons.refresh,
                onTap: _busy ? null : _retake,
              ),
              const SizedBox(width: 16),
              _ScannerConfirmButton(
                label: 'Use Photo',
                icon: Icons.check,
                filled: true,
                onTap: _busy ? null : _usePhoto,
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _ScannerConfirmButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;
  const _ScannerConfirmButton({
    required this.label,
    required this.icon,
    this.filled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.lenderBlueLight : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: filled
                ? null
                : Border.all(color: Colors.white54),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final bool busy;
  final VoidCallback? onTap;

  const _ScannerAction({
    required this.label,
    required this.icon,
    this.filled = false,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: filled ? AppColors.lenderBlue : Colors.white10,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 62,
              height: 62,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon,
                      color: filled ? Colors.white : Colors.white70, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class _CornerMarker extends StatelessWidget {
  final bool top;
  final bool bottom;
  final bool left;
  final bool right;

  const _CornerMarker({
    this.top = false,
    this.bottom = false,
    this.left = false,
    this.right = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top ? 0 : null,
      bottom: bottom ? 0 : null,
      left: left ? 0 : null,
      right: right ? 0 : null,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border(
            top: top
                ? const BorderSide(
                    color: AppColors.lenderBlueLight, width: 4)
                : BorderSide.none,
            bottom: bottom
                ? const BorderSide(
                    color: AppColors.lenderBlueLight, width: 4)
                : BorderSide.none,
            left: left
                ? const BorderSide(
                    color: AppColors.lenderBlueLight, width: 4)
                : BorderSide.none,
            right: right
                ? const BorderSide(
                    color: AppColors.lenderBlueLight, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _VignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.55),
        ],
        stops: const [0.6, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
