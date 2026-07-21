import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';
import '../models/crayfish_detection.dart';
import '../services/crayfish_detection_service.dart';

/// Gender identification scan screen for a specific crayfish batch.
///
/// Both Live and Upload modes share the same CrayfishDetectionService —
/// only the image source differs. Shows a friendly "model not ready" state
/// if assets/models/crayfish_gender.tflite hasn't been added yet, instead
/// of crashing.
class CrayfishScanScreen extends StatefulWidget {
  final String batchId;

  const CrayfishScanScreen({super.key, required this.batchId});

  @override
  State<CrayfishScanScreen> createState() => _CrayfishScanScreenState();
}

class _CrayfishScanScreenState extends State<CrayfishScanScreen> {
  // 0 = Live, 1 = Upload
  int _mode = 0;

  CameraController? _cameraController;
  bool _cameraInitializing = false;
  bool _isDetecting = false;

  // Real-time detections via ValueNotifier — only overlay/badge rebuild,
  // NOT the entire screen.
  final ValueNotifier<List<CrayfishDetection>> _liveDetections =
      ValueNotifier([]);

  // Throttle: skip frame if <100ms since last inference (~10 fps max).
  DateTime _lastInferenceStart = DateTime(0);
  static const Duration _inferenceInterval = Duration(milliseconds: 100);

  File? _uploadedImage;
  double? _imageAspectRatio;
  List<CrayfishDetection> _uploadDetections = [];
  bool _uploadLoading = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (!CrayfishDetectionService.instance.isReady) {
      CrayfishDetectionService.instance.init();
    }
  }

  @override
  void dispose() {
    _liveDetections.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ── Live camera ───────────────────────────────────────────────────────────

  Future<void> _startLiveCamera() async {
    if (_cameraController != null || _cameraInitializing) return;
    setState(() => _cameraInitializing = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) return;
      _cameraController = controller;
      await controller.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrintError('Camera init failed', e);
    } finally {
      if (mounted) setState(() => _cameraInitializing = false);
    }
  }

  void _stopLiveCamera() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _cameraController = null;
    _liveDetections.value = [];
    _captured = false;
    _capturedDetection = null;
  }

  Future<void> _onCameraFrame(CameraImage frame) async {
    if (_captured || _isDetecting || !CrayfishDetectionService.instance.isReady) return;
    final now = DateTime.now();
    if (now.difference(_lastInferenceStart) < _inferenceInterval) return;

    _isDetecting = true;
    _lastInferenceStart = now;
    try {
      final results =
          await CrayfishDetectionService.instance.detectFromCameraImage(frame);
      _liveDetections.value = results;
    } catch (e, stack) {
      debugPrintError('Live detection error', e);
      debugPrintError('Stacktrace', stack);
    } finally {
      _isDetecting = false;
    }
  }

  bool _captured = false;
  CrayfishDetection? _capturedDetection;

  void _onCapturePressed() {
    final current = _liveDetections.value;
    if (current.isEmpty) return;
    setState(() {
      _captured = true;
      _capturedDetection =
          current.reduce((a, b) => a.confidence > b.confidence ? a : b);
    });
  }

  void _rescan() {
    setState(() {
      _captured = false;
      _capturedDetection = null;
    });
  }

  // Placeholder — will be wired up later.
  void _saveResult() {
    debugPrintError('Save tapped', 'Not implemented yet');
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  Future<void> _pickAndDetect(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, maxWidth: 1280);
    if (picked == null) return;
    final file = File(picked.path);

    setState(() {
      _uploadedImage = file;
      _uploadLoading = true;
      _uploadDetections = [];
      _imageAspectRatio = null;
    });

    double? aspect;
    List<CrayfishDetection> results = [];
    try {
      final imageFuture = file.readAsBytes().then((bytes) async {
        final decodedImage = await decodeImageFromList(bytes);
        if (decodedImage.width > 0 && decodedImage.height > 0) {
          aspect = decodedImage.width / decodedImage.height;
          if (mounted) setState(() {});
        }
      });
      final detectionFuture =
          CrayfishDetectionService.instance.detectFromFile(file).then((r) {
        results = r;
      });
      await Future.wait([imageFuture, detectionFuture]);
    } catch (e, stack) {
      debugPrintError('Pick/detect failed', e);
      debugPrintError('Stacktrace', stack);
    }

    if (mounted) {
      setState(() {
        _imageAspectRatio = aspect;
        _uploadDetections = results;
        _uploadLoading = false;
      });
    }
  }

  void debugPrintError(String context, Object e) {
    // ignore: avoid_print
    print('$context: $e');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildModeToggle(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: !CrayfishDetectionService.instance.isReady
                  ? _buildModelNotReady()
                  : (_mode == 0 ? _buildLiveView() : _buildUploadView()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.faintBorder, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: AppColors.dark,
            onPressed: () {
              _stopLiveCamera();
              Navigator.of(context).pop();
            },
          ),
          Text(
            'Gender Scan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dark),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryWith(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Batch ${widget.batchId}',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.dark.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _buildToggleButton('Live', Icons.videocam_rounded, 0)),
          Expanded(child: _buildToggleButton('Upload', Icons.upload_rounded, 1)),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, IconData icon, int index) {
    final isActive = _mode == index;
    return GestureDetector(
      onTap: () {
        if (_mode == index) return;
        setState(() => _mode = index);
        if (index == 0) {
          _startLiveCamera();
        } else {
          _stopLiveCamera();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.white : AppColors.darkWith(0.4)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : AppColors.darkWith(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelNotReady() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.primaryWith(0.08), shape: BoxShape.circle),
              child: Icon(Icons.hourglass_empty_rounded, size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text('Model not added yet',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark)),
            const SizedBox(height: 6),
            Text(
              'Add crayfish_gender.tflite to\nassets/models/ to enable scanning.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.4), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  // ── Live view ─────────────────────────────────────────────────────────────

  Widget _buildLiveView() {
    if (_cameraInitializing) {
      return const Center(child: CircularProgressIndicator());
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startLiveCamera());
      return const Center(child: CircularProgressIndicator());
    }

    return ValueListenableBuilder<List<CrayfishDetection>>(
      valueListenable: _liveDetections,
      builder: (context, detections, _) {
        final hasDetections = detections.isNotEmpty;
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(controller),

            // Position guide — visible only when no detections.
            AnimatedOpacity(
              opacity: hasDetections ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: hasDetections,
                child: _buildPositionGuide(),
              ),
            ),

            // Real-time bounding box overlay.
            RepaintBoundary(
              child: CustomPaint(
                painter: _DetectionOverlayPainter(detections),
              ),
            ),

            // Result card at top — shows when detection is present.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              top: hasDetections ? 16 : -120,
              left: 16,
              right: 16,
              child: hasDetections
                  ? _buildResultCardWithSave(
                      detections.reduce(
                          (a, b) => a.confidence > b.confidence ? a : b),
                    )
                  : const SizedBox.shrink(),
            ),

            // Captured confirmation — shown after tapping Capture, replaces
            // the live feed with the frozen result until the user rescans.
            if (_captured && _capturedDetection != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: Colors.white, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'Captured: ${_capturedDetection!.label}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(_capturedDetection!.confidence * 100).toStringAsFixed(0)}% confidence',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: _rescan,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('Scan Again',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Manual Capture button — only shown while live-scanning and a
            // crayfish is currently detected. Nothing auto-captures; this is
            // the only way a result gets locked in.
            if (!_captured && hasDetections)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _onCapturePressed,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 4),
                        boxShadow: const [
                          BoxShadow(color: Color(0x33000000), blurRadius: 10),
                        ],
                      ),
                      child: Icon(Icons.camera_alt_rounded,
                          color: AppColors.primary, size: 28),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPositionGuide() {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded, size: 20, color: Colors.white70),
            SizedBox(height: 6),
            Text(
              'Position crayfish underside facing camera',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 2),
            Text(
              'Ensure good lighting and clear view of abdomen',
              style: TextStyle(color: Colors.white70, fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Result card with a save button — used in live mode.
  Widget _buildResultCardWithSave(CrayfishDetection detection) {
    final isMale = detection.isMale;
    final color = isMale ? const Color(0xFF3B82F6) : const Color(0xFFEC4899);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(isMale ? Icons.male_rounded : Icons.female_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Gender Detected',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4)),
                ),
                const SizedBox(height: 2),
                Text(
                  detection.label[0].toUpperCase() + detection.label.substring(1),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Confidence',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4)),
              ),
              const SizedBox(height: 2),
              Text(
                '${(detection.confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
              ),
            ],
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _saveResult,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryWith(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.bookmark_border_rounded, size: 18, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadView() {
    if (_uploadedImage == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: AppColors.primaryWith(0.08), shape: BoxShape.circle),
                child: Icon(Icons.add_a_photo_rounded, size: 32, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text('Upload a photo',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark)),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSourceButton('Camera', Icons.camera_alt_rounded, ImageSource.camera),
                  const SizedBox(width: 10),
                  _buildSourceButton('Gallery', Icons.photo_library_rounded, ImageSource.gallery),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Determine the best detection to show in the result card.
    CrayfishDetection? bestDetection;
    if (!_uploadLoading && _uploadDetections.isNotEmpty) {
      bestDetection = _uploadDetections.reduce((a, b) => a.confidence > b.confidence ? a : b);
    } else if (!_uploadLoading &&
        _uploadDetections.isEmpty &&
        CrayfishDetectionService.instance.lastBestScore > 0) {
      bestDetection = CrayfishDetection(
        label: CrayfishDetectionService.instance.labels.isNotEmpty
            ? CrayfishDetectionService.instance.labels[0]
            : 'female',
        confidence: CrayfishDetectionService.instance.lastBestScore,
        left: 0.0, top: 0.0, right: 1.0, bottom: 1.0,
      );
    }

    return Column(
      children: [
        // Result card — fades in when detection is ready.
        if (bestDetection != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildResultCard(bestDetection),
          ),

        // Loading card — only visible while inference is running.
        if (_uploadLoading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Analyzing photo...',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.darkWith(0.6)),
                  ),
                ],
              ),
            ),
          ),

        // Image area — shows the photo as soon as it's available.
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _imageAspectRatio != null
                    ? AspectRatio(
                        aspectRatio: _imageAspectRatio!,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(_uploadedImage!, fit: BoxFit.fill),
                            CustomPaint(painter: _DetectionOverlayPainter(_uploadDetections)),
                            if (_uploadLoading)
                              Container(
                                color: Colors.black.withValues(alpha: 0.3),
                                child: const Center(
                                  child: CircularProgressIndicator(color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      )
                    // Aspect ratio not yet known — show image with a fixed
                    // ratio so the user sees their photo immediately.
                    : AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(_uploadedImage!, fit: BoxFit.fill),
                            if (_uploadLoading)
                              Container(
                                color: Colors.black.withValues(alpha: 0.3),
                                child: const Center(
                                  child: CircularProgressIndicator(color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),

        // Footer — hint / scan-another button.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              if (!_uploadLoading && _uploadDetections.isEmpty)
                Text(
                  'No crayfish detected — try a clearer, closer shot.',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4)),
                ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() {
                  _uploadedImage = null;
                  _uploadDetections = [];
                  _imageAspectRatio = null;
                }),
                child: Text('Scan another photo',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourceButton(String label, IconData icon, ImageSource source) {
    return GestureDetector(
      onTap: () => _pickAndDetect(source),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(CrayfishDetection detection) {
    final isMale = detection.isMale;
    final color = isMale ? const Color(0xFF3B82F6) : const Color(0xFFEC4899);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(isMale ? Icons.male_rounded : Icons.female_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Gender Detected',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4)),
                ),
                const SizedBox(height: 2),
                Text(
                  detection.label[0].toUpperCase() + detection.label.substring(1),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Confidence',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4)),
              ),
              const SizedBox(height: 2),
              Text(
                '${(detection.confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Draws bounding boxes + labels over the camera preview / uploaded image.
/// Detection coordinates are normalized (0.0-1.0), so this scales to
/// whatever size is painted.
class _DetectionOverlayPainter extends CustomPainter {
  final List<CrayfishDetection> detections;
  _DetectionOverlayPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    for (final d in detections) {
      final color = d.isMale ? const Color(0xFF3B82F6) : const Color(0xFFEC4899);

      final isFullScreen = d.left == 0.0 && d.top == 0.0 && d.right == 1.0 && d.bottom == 1.0;
      final Rect rect;
      if (isFullScreen) {
        final double w = size.width * 0.6;
        final double h = size.height * 0.6;
        rect = Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: w,
          height: h,
        );
      } else {
        rect = Rect.fromLTRB(
          d.left * size.width,
          d.top * size.height,
          d.right * size.width,
          d.bottom * size.height,
        );
      }

      final overlayPaint = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)), overlayPaint);

      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)), boxPaint);

      final cornerLen = rect.shortestSide * 0.15;
      final cornerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round;

      final tl = rect.topLeft;
      canvas.drawLine(tl, Offset(tl.dx + cornerLen, tl.dy), cornerPaint);
      canvas.drawLine(tl, Offset(tl.dx, tl.dy + cornerLen), cornerPaint);

      final tr = rect.topRight;
      canvas.drawLine(tr, Offset(tr.dx - cornerLen, tr.dy), cornerPaint);
      canvas.drawLine(tr, Offset(tr.dx, tr.dy + cornerLen), cornerPaint);

      final bl = rect.bottomLeft;
      canvas.drawLine(bl, Offset(bl.dx + cornerLen, bl.dy), cornerPaint);
      canvas.drawLine(bl, Offset(bl.dx, bl.dy - cornerLen), cornerPaint);

      final br = rect.bottomRight;
      canvas.drawLine(br, Offset(br.dx - cornerLen, br.dy), cornerPaint);
      canvas.drawLine(br, Offset(br.dx, br.dy - cornerLen), cornerPaint);

      final labelText = '${d.label[0].toUpperCase()}${d.label.substring(1)} ${(d.confidence * 100).toStringAsFixed(0)}%';
      final painter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelRect = Rect.fromLTWH(rect.left, rect.top - 24, painter.width + 12, 22);
      final labelBg = Paint()..color = color;
      canvas.drawRRect(RRect.fromRectAndRadius(labelRect, const Radius.circular(6)), labelBg);
      painter.paint(canvas, Offset(rect.left + 6, rect.top - 22));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter oldDelegate) => true;
}
