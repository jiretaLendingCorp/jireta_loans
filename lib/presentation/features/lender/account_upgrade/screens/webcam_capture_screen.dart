// lib/presentation/features/lender/account_upgrade/screens/webcam_capture_screen.dart
//
// Webcam capture para sa browser (Flutter web). Sa web, ang `image_picker`
// camera source ay nagbubukas lang ng FILE CHOOSER (walang totoong camera
// capture), kaya dito tayo gumagamit ng `camera` package (camera_web) para sa
// tunay na webcam preview + snapshot.
//
// Android/iOS ay gumagamit pa rin ng ImagePicker / live scanner; ang screen na
// ito ay para sa web lang (`isSupported`).
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';

/// Result ng webcam screen.
class WebcamCaptureResult {
  /// Nakuha ang litrato.
  final Uint8List? bytes;

  /// Pinili ng user na mag-upload na lang ng file (walang camera sa device).
  final bool useFileFallback;

  const WebcamCaptureResult.captured(Uint8List this.bytes)
      : useFileFallback = false;

  const WebcamCaptureResult.fileFallback()
      : bytes = null,
        useFileFallback = true;
}

class WebcamCaptureScreen extends StatefulWidget {
  final String title;

  /// Mas gusto ang front camera (selfie/face) kung meron.
  final bool preferFrontCamera;

  /// Web lang: walang camera plugin sa Windows/Linux/macOS build.
  static bool get isSupported => kIsWeb;

  const WebcamCaptureScreen({
    super.key,
    required this.title,
    this.preferFrontCamera = false,
  });

  @override
  State<WebcamCaptureScreen> createState() => _WebcamCaptureScreenState();
}

class _WebcamCaptureScreenState extends State<WebcamCaptureScreen> {
  CameraController? _controller;
  bool _ready = false;
  bool _starting = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _starting = false;
            _error = 'No camera was found on this device.';
          });
        }
        return;
      }

      CameraDescription selected;
      try {
        selected = cameras.firstWhere(
          (c) => widget.preferFrontCamera
              ? c.lensDirection == CameraLensDirection.front
              : c.lensDirection == CameraLensDirection.back,
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
      setState(() {
        _ready = true;
        _starting = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'Camera permission was denied or the camera is in use.';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !_ready || _capturing) return;
    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(WebcamCaptureResult.captured(bytes));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = 'Could not capture a photo. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.lenderBlue,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Expanded(
                child: _error != null
                    ? _buildUnavailable()
                    : _buildPreview(),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(
                            const WebcamCaptureResult.fileFallback(),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Choose a file instead'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _ready && !_capturing ? _capture : null,
                          icon: _capturing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.camera_alt_rounded, size: 18),
                          label: const Text('Capture'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: AppColors.deepNavy,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_starting) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final controller = _controller;
    if (controller == null || !_ready) {
      return const Center(
        child: Text('Camera is not ready.',
            style: TextStyle(color: Colors.white70)),
      );
    }
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0
                ? 4 / 3
                : controller.value.aspectRatio,
            child: CameraPreview(controller),
          );
        },
      ),
    );
  }

  Widget _buildUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded,
                color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Camera is not available.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
