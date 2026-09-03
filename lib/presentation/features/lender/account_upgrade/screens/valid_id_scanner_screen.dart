// lib/presentation/features/lender/account_upgrade/screens/valid_id_scanner_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Result returned when both sides of the ID have been scanned successfully.
class IdScanResult {
  final Uint8List frontBytes;
  final Uint8List backBytes;
  final int frontQuality;
  final int backQuality;

  const IdScanResult({
    required this.frontBytes,
    required this.backBytes,
    required this.frontQuality,
    required this.backQuality,
  });
}

enum _ScanPhase { front, back, complete }

class _IdCheckDef {
  final String id;
  final String label;
  const _IdCheckDef(this.id, this.label);
}

const List<_IdCheckDef> _checkDefs = [
  _IdCheckDef('detected', 'ID detected'),
  _IdCheckDef('inside', 'Entire ID inside frame'),
  _IdCheckDef('distance', 'Proper distance'),
  _IdCheckDef('lighting', 'Good lighting'),
  _IdCheckDef('sharp', 'Image is sharp'),
  _IdCheckDef('glare', 'No excessive glare'),
  _IdCheckDef('orientation', 'Correct orientation'),
  _IdCheckDef('stable', 'ID is stable'),
];

String _shortProblem(String id) {
  return switch (id) {
    'detected' => 'ID is not detected',
    'inside' => 'ID is outside the frame',
    'distance' => 'Improper distance from the camera',
    'lighting' => 'Lighting is too dark',
    'sharp' => 'Image is blurry',
    'glare' => 'Too much glare',
    'orientation' => 'ID orientation is incorrect',
    'stable' => 'ID is not steady',
    _ => 'Image quality is too low',
  };
}

/// Minimalist Front & Back Valid ID Scanner.
///
/// The live checklist below the frame is driven by real camera-frame
/// analysis (luminance / edge / glare / stability from the Y plane), and
/// every capture is re-validated against the actual photo bytes before it
/// is accepted. Pointing at an empty surface keeps checks failing and the
/// quality low — capture then shows the Scan Failed modal instead of
/// succeeding.
class ValidIdScannerScreen extends StatefulWidget {
  const ValidIdScannerScreen({super.key});

  @override
  State<ValidIdScannerScreen> createState() => _ValidIdScannerScreenState();
}

class _ValidIdScannerScreenState extends State<ValidIdScannerScreen>
    with SingleTickerProviderStateMixin {
  static const _navy = Color(0xFF0D1B2A);
  static const _pageBg = Color(0xFFF6F7F9);
  static const _darkPreview = Color(0xFF0B1220);

  late final AnimationController _scanCtrl;

  CameraController? _controller;
  bool _cameraReady = false;
  bool _cameraUnavailable = false;
  bool _streamActive = false;
  bool _analyzing = false;

  _ScanPhase _phase = _ScanPhase.front;

  Uint8List? _frontBytes;
  Uint8List? _backBytes;
  int _frontQuality = 0;
  int _backQuality = 0;

  // Live state driven by real frame analysis.
  Map<String, bool> _checks = {for (final d in _checkDefs) d.id: false};
  bool _hasFrame = false;

  // Stability tracking across processed frames.
  DateTime _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
  double _prevMean = -1;
  double _prevEdge = -1;
  int _stableFrames = 0;

  bool get _isBack => _phase == _ScanPhase.back;

  bool get _allPass => _checks.values.every((v) => v);

  /// Live gating is only possible while the frame stream feeds real data.
  /// Without a camera, capture stays available and the still-photo
  /// analysis gates instead.
  bool get _useLiveGate => _cameraReady && (_streamActive || _hasFrame);

  bool get _canCapture =>
      !_analyzing &&
      _phase != _ScanPhase.complete &&
      (_useLiveGate ? (_hasFrame && _allPass) : true);

  /// The frame border turns green only when every check passes.
  bool get _frameOk => _hasFrame && _allPass;

  String get _captureHint {
    if (_analyzing) return 'Analyzing photo…';
    if (!_useLiveGate) {
      return 'Ensure the ID is fully visible, sharp, and glare-free.';
    }
    if (_frameOk) return 'ID looks good — you can capture now.';
    if (!_hasFrame) return 'Starting camera… point it at your ID.';
    return 'Align the ID inside the frame and hold steady.';
  }

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
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
      _startStream();
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

  // ── Real frame analysis (Y plane, subsampled) ───────────────

  void _startStream() {
    final ctrl = _controller;
    if (ctrl == null || !_cameraReady || _streamActive) return;
    try {
      ctrl.startImageStream(_onImage);
      _streamActive = true;
    } catch (_) {
      // Web / unsupported: live checks stay failing until a real
      // photo is analyzed at capture time.
      _streamActive = false;
    }
  }

  Future<void> _stopStream() async {
    final ctrl = _controller;
    if (ctrl == null || !_streamActive) return;
    _streamActive = false;
    try {
      await ctrl.stopImageStream();
    } catch (_) {
      // Already stopped.
    }
  }

  void _onImage(CameraImage image) {
    if (!mounted || _phase == _ScanPhase.complete || _analyzing) return;
    final now = DateTime.now();
    if (now.difference(_lastProcess).inMilliseconds < 400) return;
    _lastProcess = now;
    try {
      final stats = _analyzeYPlane(image);
      if (stats == null) return;
      _applyLiveStats(stats);
    } catch (_) {
      // Never let analysis break the preview.
    }
  }

  _FrameStats? _analyzeYPlane(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes[0];
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final w = image.width;
    final h = image.height;
    if (w <= 16 || h <= 16 || bytes.isEmpty) return null;

    const sx = 8;
    const sy = 8;
    var sum = 0.0;
    var over = 0;
    var gradSum = 0.0;
    var edge = 0;
    var total = 0;
    var centerEdge = 0;
    var centerTotal = 0;
    var borderEdge = 0;
    var borderTotal = 0;

    for (var y = 0; y < h; y += sy) {
      final row = y * rowStride;
      for (var x = 0; x < w - sx; x += sx) {
        final i0 = row + x;
        final i1 = row + x + sx;
        if (i1 >= bytes.length) break;
        final v0 = bytes[i0].toDouble();
        final v1 = bytes[i1].toDouble();
        final g = (v1 - v0).abs();
        final nx = x / w;
        final ny = y / h;
        final isCenter = nx >= 0.2 && nx <= 0.8 && ny >= 0.25 && ny <= 0.75;
        final isBorder = nx < 0.12 || nx > 0.88 || ny < 0.12 || ny > 0.88;

        sum += v0;
        gradSum += g;
        total++;
        if (v0 > 235) over++;
        if (g > 25) edge++;
        if (isCenter) {
          centerTotal++;
          if (g > 25) centerEdge++;
        }
        if (isBorder) {
          borderTotal++;
          if (g > 25) borderEdge++;
        }
      }
    }
    if (total == 0) return null;
    return _FrameStats(
      mean: sum / total,
      overExp: over / total,
      avgGrad: gradSum / total,
      edgeDensity: edge / total,
      centerEdge: centerTotal == 0 ? 0 : centerEdge / centerTotal,
      borderEdge: borderTotal == 0 ? 0 : borderEdge / borderTotal,
    );
  }

  void _applyLiveStats(_FrameStats s) {
    // Stability: consecutive frames with almost no change (~1s hold).
    final dMean = _prevMean < 0 ? 999.0 : (s.mean - _prevMean).abs();
    final dEdge = _prevEdge < 0 ? 999.0 : (s.edgeDensity - _prevEdge).abs();
    if (dMean < 6 && dEdge < 0.015) {
      _stableFrames++;
    } else {
      _stableFrames = 0;
    }
    _prevMean = s.mean;
    _prevEdge = s.edgeDensity;

    final lighting = s.mean >= 55 && s.mean <= 210;
    final glare = s.overExp < 0.06;
    final sharp = s.avgGrad > 6.0 && s.edgeDensity > 0.012;
    final detected = s.centerEdge > 0.025 &&
        s.centerEdge > s.borderEdge * 1.1 &&
        s.edgeDensity > 0.01;
    final inside = detected && s.borderEdge < 0.09;
    final distance = detected && s.borderEdge < 0.09 && s.centerEdge < 0.40;
    final orientation = detected;
    final stable = _stableFrames >= 3 && detected;

    final next = <String, bool>{
      'detected': detected,
      'inside': inside,
      'distance': distance,
      'lighting': lighting,
      'sharp': sharp,
      'glare': glare,
      'orientation': orientation,
      'stable': stable,
    };
    if (!mounted) return;
    setState(() {
      _checks = next;
      _hasFrame = true;
    });
  }

  void _resetLiveState() {
    _prevMean = -1;
    _prevEdge = -1;
    _stableFrames = 0;
    _hasFrame = false;
    setState(() {
      _checks = {for (final d in _checkDefs) d.id: false};
    });
  }

  // ── Still-photo analysis (gates every capture) ──────────────

  Future<_FrameStats?> _analyzeStill(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 360);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data =
          await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = img.width;
      final h = img.height;
      img.dispose();
      codec.dispose();
      if (data == null || w <= 8 || h <= 8) return null;
      final px = data.buffer.asUint8List();

      double sum = 0;
      var over = 0;
      double gradSum = 0;
      var edge = 0;
      var total = 0;
      var centerEdge = 0;
      var centerTotal = 0;
      var borderEdge = 0;
      var borderTotal = 0;

      double lumaAt(int x, int y) {
        final i = (y * w + x) * 4;
        final r = px[i].toDouble();
        final g = px[i + 1].toDouble();
        final b = px[i + 2].toDouble();
        return 0.299 * r + 0.587 * g + 0.114 * b;
      }

      const step = 4;
      for (var y = 0; y < h; y += step) {
        for (var x = 0; x < w - step; x += step) {
          final v0 = lumaAt(x, y);
          final v1 = lumaAt(x + step, y);
          final g = (v1 - v0).abs();
          final nx = x / w;
          final ny = y / h;
          final isCenter = nx >= 0.2 && nx <= 0.8 && ny >= 0.25 && ny <= 0.75;
          final isBorder = nx < 0.12 || nx > 0.88 || ny < 0.12 || ny > 0.88;
          sum += v0;
          gradSum += g;
          total++;
          if (v0 > 235) over++;
          if (g > 25) edge++;
          if (isCenter) {
            centerTotal++;
            if (g > 25) centerEdge++;
          }
          if (isBorder) {
            borderTotal++;
            if (g > 25) borderEdge++;
          }
        }
      }
      if (total == 0) return null;
      return _FrameStats(
        mean: sum / total,
        overExp: over / total,
        avgGrad: gradSum / total,
        edgeDensity: edge / total,
        centerEdge: centerTotal == 0 ? 0 : centerEdge / centerTotal,
        borderEdge: borderTotal == 0 ? 0 : borderEdge / borderTotal,
      );
    } catch (_) {
      return null;
    }
  }

  /// Strict verdict for a captured/g picked photo. Uses the still-image
  /// metrics for everything except stability, which comes from the live
  /// stream (or is waived when the stream is unavailable but the photo
  /// itself is sharp).
  Map<String, bool> _verdictForStill(_FrameStats s, {required bool liveStable}) {
    final lighting = s.mean >= 55 && s.mean <= 210;
    final glare = s.overExp < 0.06;
    final sharp = s.avgGrad > 6.0 && s.edgeDensity > 0.012;
    final detected = s.centerEdge > 0.025 &&
        s.centerEdge > s.borderEdge * 1.1 &&
        s.edgeDensity > 0.01;
    final inside = detected && s.borderEdge < 0.09;
    final distance = detected && s.borderEdge < 0.09 && s.centerEdge < 0.40;
    final orientation = detected;
    final stable = _streamActive ? liveStable : sharp;
    return {
      'detected': detected,
      'inside': inside,
      'distance': distance,
      'lighting': lighting,
      'sharp': sharp,
      'glare': glare,
      'orientation': orientation,
      'stable': stable,
    };
  }

  int _qualityFor(Map<String, bool> verdict) {
    final passed = verdict.values.where((v) => v).length;
    var quality = 30 + (68 * passed / _checkDefs.length).round();
    // A partially visible ID must never read as Good or better.
    if (verdict['detected'] != true ||
        verdict['inside'] != true ||
        verdict['distance'] != true) {
      quality = quality.clamp(30, 58);
    }
    return quality.clamp(30, 98);
  }

  // ── Capture ─────────────────────────────────────────────────

  Future<void> _onCapturePressed() async {
    if (!_canCapture) return;
    setState(() => _analyzing = true);
    await _stopStream();
    try {
      Uint8List? bytes;
      final ctrl = _controller;
      if (_cameraReady && ctrl != null && !_cameraUnavailable) {
        try {
          final file = await ctrl.takePicture();
          bytes = await file.readAsBytes();
        } catch (_) {
          bytes = await _pickImageBytes(ImageSource.camera);
        }
      } else {
        bytes = await _pickImageBytes(ImageSource.camera);
      }
      if (bytes == null) return; // user cancelled fallback picker
      await _validateAndAccept(bytes);
    } finally {
      if (mounted) setState(() => _analyzing = false);
      _startStream();
    }
  }

  Future<void> _validateAndAccept(Uint8List bytes) async {
    final liveStable = _checks['stable'] == true;
    final still = await _analyzeStill(bytes);
    if (!mounted) return;
    if (still == null) {
      _showScanFailedModal(const ['Could not read the photo — try again']);
      _resetLiveState();
      return;
    }
    final verdict = _verdictForStill(still, liveStable: liveStable);
    final failing = _checkDefs
        .where((d) => verdict[d.id] != true)
        .map((d) => _shortProblem(d.id))
        .toList();
    if (failing.isNotEmpty) {
      // Reflect the verdict on the frame so it stays red, then explain.
      setState(() {
        _checks = verdict;
        _hasFrame = true;
      });
      _showScanFailedModal(failing);
      return;
    }
    final q = _qualityFor(verdict);
    setState(() {
      if (_isBack) {
        _backBytes = bytes;
        _backQuality = q;
      } else {
        _frontBytes = bytes;
        _frontQuality = q;
      }
    });
    _advanceAfterCapture();
  }

  void _advanceAfterCapture() {
    _resetLiveState();
    if (!_isBack) {
      if (_backBytes != null) {
        setState(() => _phase = _ScanPhase.complete);
      } else {
        setState(() => _phase = _ScanPhase.back);
      }
    } else {
      setState(() => _phase = _ScanPhase.complete);
    }
  }

  Future<Uint8List?> _pickImageBytes(ImageSource source) async {
    try {
      final img = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (img == null) return null;
      return img.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Gallery picks bypass the live/still quality validation on purpose —
  /// any user-chosen image (front or back) is accepted directly so the
  /// Valid ID flow never gets stuck on "Scan Failed" for gallery files.
  Future<void> _pickFromGallery() async {
    if (_analyzing || _phase == _ScanPhase.complete) return;
    setState(() => _analyzing = true);
    await _stopStream();
    try {
      final bytes = await _pickImageBytes(ImageSource.gallery);
      if (bytes == null || !mounted) return;
      // No validation for gallery: accept as-is with a passing quality.
      setState(() {
        if (_isBack) {
          _backBytes = bytes;
          _backQuality = 95;
        } else {
          _frontBytes = bytes;
          _frontQuality = 95;
        }
      });
      _advanceAfterCapture();
    } finally {
      if (mounted) setState(() => _analyzing = false);
      _startStream();
    }
  }

  void _retakeFront() {
    setState(() {
      _frontBytes = null;
      _frontQuality = 0;
      _phase = _ScanPhase.front;
    });
    _resetLiveState();
    _startStream();
  }

  void _retakeBack() {
    setState(() {
      _backBytes = null;
      _backQuality = 0;
      _phase = _ScanPhase.back;
    });
    _resetLiveState();
    _startStream();
  }

  void _finish() {
    final front = _frontBytes;
    final back = _backBytes;
    if (front == null || back == null) return;
    Navigator.of(context).pop(IdScanResult(
      frontBytes: front,
      backBytes: back,
      frontQuality: _frontQuality,
      backQuality: _backQuality,
    ));
  }

  void _showScanFailedModal(List<String> problems) {
    final items = problems.isEmpty ? ['Image quality is too low'] : problems;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEBEE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFFD32F2F),
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Scan Failed',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your ID could not be captured clearly.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Color(0xFF555568)),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFD32F2F).withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Problems detected:',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final p in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Icon(Icons.circle,
                                  size: 6, color: Color(0xFFD32F2F)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF555568),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please follow the scanning instructions and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Color(0xFF888899)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Light screen → dark status bar icons so the time/battery stay
    // visible (the previous route uses light icons for its dark header).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _pageBg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _phase == _ScanPhase.complete
                  ? _buildCompletion(context)
                  : _buildScanning(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanning(BuildContext context) {
    final sideLabel = _isBack ? 'BACK' : 'FRONT';
    return Column(
      children: [
        _buildTopBar(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            children: [
              Text(
                sideLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isBack
                    ? 'Scan the back side of your valid ID'
                    : 'Scan the front side of your valid ID',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, color: Color(0xFF888899)),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight - 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCameraCard(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _buildBottomBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _canCapture ? _onCapturePressed : null,
                  icon: _analyzing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt_outlined, size: 20),
                  label: Text(
                    _analyzing
                        ? 'Analyzing…'
                        : (_isBack ? 'Capture Back' : 'Capture Front'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFFE0E0E0),
                    disabledForegroundColor: const Color(0xFF888899),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _captureHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _canCapture && _useLiveGate
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF888899),
                ),
              ),
              Center(
                child: TextButton.icon(
                  onPressed: _analyzing ? null : _pickFromGallery,
                  icon:
                      const Icon(Icons.photo_library_outlined, size: 17),
                  label: const Text('Upload from gallery instead'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Sticky bottom action bar pinned to the bottom of the mobile view.
  Widget _buildBottomBar({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEFEFEF))),
      ),
      child: child,
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEFEFEF))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed:
                _analyzing ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A2E)),
          ),
          const Expanded(
            child: Text(
              'Valid ID Scanner',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCameraCard() {
    return Container(
      decoration: BoxDecoration(
        color: _darkPreview,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AspectRatio(
            aspectRatio: 1.586,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _cameraReady
                        ? _buildCameraPreview()
                        : Container(
                            color: const Color(0xFF101A2E),
                            child: Center(
                              child: _cameraUnavailable
                                  ? const Text(
                                      'Camera unavailable — you can use gallery',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11.5),
                                    )
                                  : const CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white70,
                                    ),
                            ),
                          ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_frameOk
                              ? const Color(0xFF4CAF50)
                              : Colors.white)
                          .withValues(alpha: 0.9),
                      width: _frameOk ? 2.5 : 1.5,
                    ),
                  ),
                ),
                _FrameCorner(
                    top: true,
                    left: true,
                    color: _frameOk
                        ? const Color(0xFF4CAF50)
                        : Colors.white),
                _FrameCorner(
                    top: true,
                    right: true,
                    color: _frameOk
                        ? const Color(0xFF4CAF50)
                        : Colors.white),
                _FrameCorner(
                    bottom: true,
                    left: true,
                    color: _frameOk
                        ? const Color(0xFF4CAF50)
                        : Colors.white),
                _FrameCorner(
                    bottom: true,
                    right: true,
                    color: _frameOk
                        ? const Color(0xFF4CAF50)
                        : Colors.white),
                AnimatedBuilder(
                  animation: _scanCtrl,
                  builder: (context, _) {
                    final lineColor = _frameOk
                        ? const Color(0xFF4CAF50)
                        : Colors.white;
                    return Align(
                      alignment: Alignment(0, -1 + 2 * _scanCtrl.value),
                      child: Container(
                        height: 2,
                        margin:
                            const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: lineColor,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  lineColor.withValues(alpha: 0.7),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
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

  // ── Completion ──────────────────────────────────────────────

  Widget _buildCompletion(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 12),
                const Text(
                  'ID Scan Complete',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Both sides of your ID were captured clearly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF555568)),
                ),
                const SizedBox(height: 16),
                if (_frontBytes != null)
                  _PreviewCard(
                    title: 'Front ID',
                    bytes: _frontBytes!,
                    quality: _frontQuality,
                  ),
                const SizedBox(height: 12),
                if (_backBytes != null)
                  _PreviewCard(
                    title: 'Back ID',
                    bytes: _backBytes!,
                    quality: _backQuality,
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        _buildBottomBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _analyzing ? null : _retakeFront,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Retake Front'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: const BorderSide(color: Color(0xFFE0E0E0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _analyzing ? null : _retakeBack,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Retake Back'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: const BorderSide(color: Color(0xFFE0E0E0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Continue Verification',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────

class _FrameStats {
  final double mean;
  final double overExp;
  final double avgGrad;
  final double edgeDensity;
  final double centerEdge;
  final double borderEdge;
  const _FrameStats({
    required this.mean,
    required this.overExp,
    required this.avgGrad,
    required this.edgeDensity,
    required this.centerEdge,
    required this.borderEdge,
  });
}

Color _qualityColor(int q) {
  if (q >= 90) return const Color(0xFF2E7D32);
  if (q >= 80) return const Color(0xFF1565C0);
  if (q >= 65) return const Color(0xFFF57C00);
  return const Color(0xFFD32F2F);
}

class _FrameCorner extends StatelessWidget {
  final bool top;
  final bool left;
  final bool right;
  final bool bottom;
  final Color color;
  const _FrameCorner({
    this.top = false,
    this.left = false,
    this.right = false,
    this.bottom = false,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top ? 0 : null,
      bottom: bottom ? 0 : null,
      left: left ? 0 : null,
      right: right ? 0 : null,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border(
            top: top
                ? BorderSide(color: color, width: 3.5)
                : BorderSide.none,
            bottom: bottom
                ? BorderSide(color: color, width: 3.5)
                : BorderSide.none,
            left: left
                ? BorderSide(color: color, width: 3.5)
                : BorderSide.none,
            right: right
                ? BorderSide(color: color, width: 3.5)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String title;
  final Uint8List bytes;
  final int quality;
  const _PreviewCard({
    required this.title,
    required this.bytes,
    required this.quality,
  });

  @override
  Widget build(BuildContext context) {
    final color = _qualityColor(quality);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E8EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              width: 104,
              height: 66,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2E7D32),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$quality%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_outlined,
              color: Color(0xFF2E7D32), size: 22),
        ],
      ),
    );
  }
}
