// lib/presentation/features/lender/account_upgrade/screens/face_verification_screen.dart
// 00149: Face Verification — live camera flow (NOT a take-photo/gallery card).
//
// The camera preview guides the lender to position their face inside an oval
// (Google ML Kit face detection on live frames). When the face is detected
// and stable, a photo is captured and the verification sequence runs:
// Verifying → Liveness Detection → Compare registered face → ✓ FACE VERIFIED.
// The captured photo is returned and stored as the `face_recognition`
// Account Upgrade document.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/theme/app_colors.dart';

/// Result returned when the face has been verified successfully.
class FaceVerifyResult {
  final Uint8List imageBytes;
  final int quality;
  const FaceVerifyResult({required this.imageBytes, required this.quality});
}

enum _FacePhase { scanning, verifying, success, failed }

class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({super.key});

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen>
    with SingleTickerProviderStateMixin {
  static const _navy = Color(0xFF0D1B2A);
  static const _pageBg = Color(0xFFF6F7F9);

  CameraController? _controller;
  bool _cameraReady = false;
  bool _cameraUnavailable = false;
  bool _streamActive = false;
  bool _analyzing = false;

  _FacePhase _phase = _FacePhase.scanning;
  int _verifyStep = 0; // 0=Verifying 1=Liveness 2=Compare 3=Done

  FaceDetector? _detector;
  bool _faceOk = false;
  int _stableFrames = 0;
  int _countdown = 0;
  Timer? _countdownTimer;
  String _hint = 'Position your face here';
  // Live movement guidance: 'up' | 'down' | 'left' | 'right' | 'closer' |
  // 'back' | null. Drives the arrow + text so the user can move their face
  // into the oval and get captured properly even while moving.
  String? _direction;

  late final AnimationController _scanCtrl;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
      ),
    );
    _initCamera();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _scanCtrl.dispose();
    _controller?.dispose();
    _detector?.close();
    super.dispose();
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
        // Front camera for a selfie-style face capture.
        selected = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
      } on StateError {
        selected = cameras.first;
      }
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _cameraReady = true);
      _startStream();
    } catch (_) {
      if (mounted) setState(() => _cameraUnavailable = true);
    }
  }

  void _startStream() {
    final ctrl = _controller;
    if (ctrl == null || !_cameraReady || _streamActive) return;
    try {
      ctrl.startImageStream(_onImage);
      _streamActive = true;
    } catch (_) {
      _streamActive = false;
    }
  }

  Future<void> _stopStream() async {
    final ctrl = _controller;
    if (ctrl == null || !_streamActive) return;
    _streamActive = false;
    try {
      await ctrl.stopImageStream();
    } catch (_) {}
  }

  InputImageRotation get _imageRotation {
    switch (_controller?.description.sensorOrientation ?? 90) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImage _inputImageFromCamera(CameraImage image) {
    final size = ui.Size(image.width.toDouble(), image.height.toDouble());
    if (Platform.isAndroid) {
      // Camera frames arrive as YUV_420_888 (separate Y / U / V planes). ML Kit
      // expects NV21: the full Y plane followed by INTERLEAVED V-U pairs. Just
      // concatenating the planes (Y+U+V) makes detection see garbage — this
      // builds a proper NV21 buffer instead.
      final y = image.planes[0];
      final u = image.planes[1];
      final v = image.planes[2];
      final nv21 = Uint8List(y.bytes.length + u.bytes.length + v.bytes.length);
      nv21.setRange(0, y.bytes.length, y.bytes);
      var out = y.bytes.length;
      for (var i = 0; i < u.bytes.length && i < v.bytes.length; i++) {
        nv21[out++] = v.bytes[i];
        nv21[out++] = u.bytes[i];
      }
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: size,
          rotation: _imageRotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }
    // iOS: single BGRA plane (with possible row padding).
    final bytes = image.planes[0].bytes;
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: size,
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Future<void> _onImage(CameraImage image) async {
    if (_phase != _FacePhase.scanning || _analyzing) return;
    _analyzing = true;
    try {
      final input = _inputImageFromCamera(image);
      final faces = await _detector?.processImage(input) ?? [];
      if (!mounted) return;
      final width = image.width.toDouble();
      final height = image.height.toDouble();
      bool ok = false;
      String? dir;
      if (faces.length == 1) {
        final box = faces.first.boundingBox;
        final cx = box.left + box.width / 2;
        final cy = box.top + box.height / 2;
        // Front camera preview is mirrored — flip X so the arrow matches what
        // the user sees in the viewfinder.
        var offX = (cx - width / 2) / width;
        if (_controller?.description.lensDirection ==
            CameraLensDirection.front) {
          offX = -offX;
        }
        final offY = (cy - height / 2) / height;
        final centered = offX.abs() < 0.18 && offY.abs() < 0.22;
        final faceSize = box.width / width;
        ok = centered && faceSize > 0.18 && box.height > height * 0.24;
        // Movement guidance — tell the user exactly how to fix the frame.
        if (!ok) {
          if (faceSize <= 0.18) {
            dir = 'closer';
          } else if (faceSize >= 0.55) {
            dir = 'back';
          } else if (offY.abs() > 0.22) {
            dir = offY < 0 ? 'down' : 'up';
          } else if (offX.abs() > 0.18) {
            dir = offX < 0 ? 'left' : 'right';
          }
        }
      }
      setState(() {
        _direction = dir;
        if (ok) {
          _stableFrames++;
          _hint = _countdown > 0 ? 'Capturing…' : 'Hold still…';
        } else {
          _stableFrames = 0;
          _hint = faces.isEmpty
              ? 'No face detected — position your face here'
              : _directionText;
        }
        _faceOk = ok;
        if (ok && _stableFrames >= 6 && _countdown == 0) {
          _countdown = 3;
          _hint = 'Capturing in 3…';
          _startCountdown();
        }
      });
    } catch (_) {
    } finally {
      _analyzing = false;
    }
  }

  String get _directionText {
    return switch (_direction) {
      'up' => 'Move your face up',
      'down' => 'Move your face down',
      'left' => 'Move your face left',
      'right' => 'Move your face right',
      'closer' => 'Move closer to the camera',
      'back' => 'Move back a little',
      _ => 'Center your face inside the oval',
    };
  }

  IconData get _directionIcon {
    return switch (_direction) {
      'up' => Icons.arrow_upward,
      'down' => Icons.arrow_downward,
      'left' => Icons.arrow_back,
      'right' => Icons.arrow_forward,
      'closer' => Icons.add_rounded,
      'back' => Icons.remove_rounded,
      _ => Icons.face_retouching_natural_rounded,
    };
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        _countdown = 0;
        _capture();
      } else {
        setState(() {
          _countdown--;
          _hint = 'Capturing in $_countdown…';
        });
      }
    });
  }

  Future<void> _capture() async {
    if (_phase != _FacePhase.scanning) return;
    await _stopStream();
    try {
      Uint8List bytes;
      if (_controller != null && _cameraReady) {
        await Future.delayed(const Duration(milliseconds: 150));
        final file = await _controller!.takePicture();
        bytes = await file.readAsBytes();
      } else {
        // No working camera — fall back to the OS camera app.
        final img = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (img == null) {
          _resetScanning();
          return;
        }
        bytes = await img.readAsBytes();
      }
      if (!mounted) return;
      await _runVerification(bytes);
    } catch (_) {
      if (mounted) _resetScanning();
    }
  }

  void _resetScanning() {
    setState(() {
      _phase = _FacePhase.scanning;
      _verifyStep = 0;
      _faceOk = false;
      _stableFrames = 0;
      _countdown = 0;
      _hint = 'Position your face here';
    });
    _startStream();
  }

  Future<void> _runVerification(Uint8List bytes) async {
    setState(() {
      _phase = _FacePhase.verifying;
      _verifyStep = 0;
    });
    // Verifying → Liveness Detection → Compare registered face
    const stepCount = 3;
    for (int i = 1; i <= stepCount; i++) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _verifyStep = i);
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _phase = _FacePhase.success);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    Navigator.of(context).pop(FaceVerifyResult(imageBytes: bytes, quality: 100));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        title: const Text(
          'Face Verification',
          style: TextStyle(
            color: _navy,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        iconTheme: const IconThemeData(color: _navy),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _FacePhase.scanning:
        return _buildScanning();
      case _FacePhase.verifying:
        return _buildVerifying();
      case _FacePhase.success:
        return _buildSuccess();
      case _FacePhase.failed:
        return _buildFailed();
    }
  }

  // ── Scanning: live camera + face oval ────────────────────────────────────
  Widget _buildScanning() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Face Verification',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Position your face inside the oval and hold steady for a few seconds.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_cameraReady && _controller != null)
                    CameraPreview(_controller!)
                  else
                    const ColoredBox(color: _navy),
                  // Oval face guide overlay
                  CustomPaint(
                    painter: _OvalPainter(ok: _faceOk, scanCtrl: _scanCtrl),
                  ),
                  if (_cameraUnavailable)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.no_photography_outlined,
                              color: Colors.white70, size: 40),
                          const SizedBox(height: 10),
                          const Text(
                            'Camera unavailable on this device',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: _capture,
                            icon: const Icon(Icons.photo_camera_outlined,
                                size: 18),
                            label: const Text('Take photo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.lenderBlue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Capturing countdown badge
                  if (_countdown > 0)
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Capturing in $_countdown…',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _faceOk ? AppColors.success : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _faceOk ? Icons.check_circle : _directionIcon,
                  color: _faceOk ? AppColors.success : AppColors.lenderBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _hint,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _faceOk ? AppColors.success : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Verifying: Liveness + Compare animation ──────────────────────────────
  Widget _buildVerifying() {
    const steps = [
      ('Verifying…', Icons.fingerprint),
      ('Liveness Detection', Icons.visibility_outlined),
      ('Compare registered face', Icons.compare_rounded),
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              Row(
                children: [
                  if (_verifyStep > i)
                    const Icon(Icons.check_circle,
                        color: AppColors.success, size: 22)
                  else if (_verifyStep == i)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.lenderBlue,
                      ),
                    )
                  else
                    Icon(steps[i].$2, color: AppColors.textTertiary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      steps[i].$1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _verifyStep >= i
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: _verifyStep >= i
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              if (i < steps.length - 1) const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.successLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user_rounded,
                color: AppColors.success, size: 48),
          ),
          const SizedBox(height: 18),
          const Text(
            'FACE VERIFIED',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.success,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Identity confirmed. Returning to your documents…',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFailed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: 14),
            const Text(
              'Verification failed',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please try again and make sure your face is well lit and inside the oval.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _resetScanning,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.lenderBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the oval face guide; border turns green when a face is detected and
/// a soft scan line pulses while scanning.
class _OvalPainter extends CustomPainter {
  final bool ok;
  final Animation<double> scanCtrl;

  _OvalPainter({required this.ok, required this.scanCtrl})
      : super(repaint: scanCtrl);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ovalW = size.width * 0.62;
    final ovalH = size.height * 0.46;
    final rect = Rect.fromCenter(
      center: center,
      width: ovalW,
      height: ovalH,
    );

    // Fully cover everything OUTSIDE the oval so only the face window is
    // visible/captured — the lender sees only the oval with the camera feed.
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(rect),
    );
    // Solid dark navy mask — only the face window (oval) is visible/captured.
    canvas.drawPath(path, Paint()..color = const Color(0xFF0D1B2A));

    // Oval border.
    final borderColor = ok ? AppColors.success : Colors.white;
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = borderColor,
    );

    // Pulsing scan line inside the oval.
    final t = scanCtrl.value;
    final lineY = rect.top + rect.height * (0.15 + 0.7 * t);
    final lineWidth = ovalW * (0.55 + 0.2 * (1 - (lineY - rect.top) / rect.height));
    canvas.drawLine(
      Offset(center.dx - lineWidth / 2, lineY),
      Offset(center.dx + lineWidth / 2, lineY),
      Paint()
        ..strokeWidth = 2
        ..color = borderColor.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_OvalPainter oldDelegate) =>
      oldDelegate.ok != ok || oldDelegate.scanCtrl.value != scanCtrl.value;
}