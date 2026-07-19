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
  bool _isDetecting = false; // guards against overlapping frame inference
  List<CrayfishDetection> _liveDetections = [];

  File? _uploadedImage;
  double? _imageAspectRatio;
  List<CrayfishDetection> _uploadDetections = [];
  bool _uploadLoading = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    CrayfishDetectionService.instance.addListener(_onServiceChange);
    if (!CrayfishDetectionService.instance.isReady) {
      CrayfishDetectionService.instance.init();
    }
  }

  void _onServiceChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CrayfishDetectionService.instance.removeListener(_onServiceChange);
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _startLiveCamera() async {
    if (_cameraController != null || _cameraInitializing) return;
    setState(() => _cameraInitializing = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        // Force YUV420 on both Android and iOS (iOS defaults to BGRA8888
        // otherwise) so _convertYUV420ToImage always gets the format it
        // expects.
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
    _liveDetections = [];
  }

  Future<void> _onCameraFrame(CameraImage frame) async {
    if (_isDetecting || !CrayfishDetectionService.instance.isReady) return;
    _isDetecting = true;
    try {
      final results = await CrayfishDetectionService.instance.detectFromCameraImage(frame);
      if (mounted) setState(() => _liveDetections = results);
    } catch (e, stack) {
      debugPrintError('Error in live detection frame', e);
      debugPrintError('Stacktrace', stack);
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _pickAndDetect(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, maxWidth: 1280);
    if (picked == null) return;
    final file = File(picked.path);
    setState(() {
      _uploadedImage = file;
      _uploadLoading = true;
      _uploadDetections = [];
      _imageAspectRatio = null; // reset
    });

    double? aspect;
    try {
      final bytes = await file.readAsBytes();
      final decodedImage = await decodeImageFromList(bytes);
      if (decodedImage.width > 0 && decodedImage.height > 0) {
        aspect = decodedImage.width / decodedImage.height;
      }
    } catch (e) {
      debugPrintError('Error decoding image size', e);
    }

    try {
      final results = await CrayfishDetectionService.instance.detectFromFile(file);
      debugPrintError('Detection results', '${results.length} crayfish found');
      for (final r in results) {
        debugPrintError('  Detection', r.toString());
      }
      if (mounted) {
        setState(() {
          _imageAspectRatio = aspect;
          _uploadDetections = results;
          _uploadLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrintError('Detection failed', e);
      debugPrintError('Stacktrace', stack);
      if (mounted) {
        setState(() {
          _imageAspectRatio = aspect;
          _uploadDetections = [];
          _uploadLoading = false;
        });
      }
    }
  }

  void debugPrintError(String context, Object e) {
    // ignore: avoid_print
    print('$context: $e');
  }

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

  Widget _buildLiveView() {
    if (_cameraInitializing) {
      return const Center(child: CircularProgressIndicator());
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      // Camera hasn't started yet (e.g. user switched to this tab before
      // permission resolved) — trigger start.
      WidgetsBinding.instance.addPostFrameCallback((_) => _startLiveCamera());
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        CustomPaint(
          painter: _DetectionOverlayPainter(_liveDetections),
        ),
        if (_liveDetections.isNotEmpty) _buildLiveResultBadge(),
      ],
    );
  }

  Widget _buildLiveResultBadge() {
    final best = _liveDetections.reduce((a, b) => a.confidence > b.confidence ? a : b);
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: _buildResultCard(best),
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

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _imageAspectRatio == null
                  ? const CircularProgressIndicator()
                  : AspectRatio(
                      aspectRatio: _imageAspectRatio!,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(_uploadedImage!, fit: BoxFit.fill),
                            CustomPaint(painter: _DetectionOverlayPainter(_uploadDetections)),
                            if (_uploadLoading)
                              Container(
                                color: Colors.black.withValues(alpha: 0.3),
                                child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (!_uploadLoading && _uploadDetections.isNotEmpty)
                _buildResultCard(_uploadDetections.reduce((a, b) => a.confidence > b.confidence ? a : b))
              else if (!_uploadLoading && _uploadDetections.isEmpty)
                Text('No crayfish detected — try a clearer, closer shot.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4))),
              const SizedBox(height: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Icon(isMale ? Icons.male_rounded : Icons.female_rounded, color: color, size: 22),
          const SizedBox(width: 8),
          Text(
            detection.label[0].toUpperCase() + detection.label.substring(1),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.dark),
          ),
          const Spacer(),
          Text(
            '${(detection.confidence * 100).toStringAsFixed(0)}% confidence',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4)),
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
    for (final d in detections) {
      final color = d.isMale ? const Color(0xFF3B82F6) : const Color(0xFFEC4899);
      final rect = Rect.fromLTRB(
        d.left * size.width,
        d.top * size.height,
        d.right * size.width,
        d.bottom * size.height,
      );
      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), boxPaint);

      final labelText = '${d.label} ${(d.confidence * 100).toStringAsFixed(0)}%';
      final painter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelRect = Rect.fromLTWH(rect.left, rect.top - 18, painter.width + 8, 18);
      canvas.drawRect(labelRect, Paint()..color = color);
      painter.paint(canvas, Offset(rect.left + 4, rect.top - 17));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter oldDelegate) => true;
}
