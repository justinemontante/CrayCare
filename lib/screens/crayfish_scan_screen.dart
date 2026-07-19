import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Gender identification scan screen for a specific crayfish batch.
///
/// TODO(model): once the trained YOLOv11 model is exported to TFLite
/// (assets/models/crayfish_gender.tflite + labels.txt), wire this screen
/// up to CrayfishDetectionService for real inference. For now this is a
/// placeholder shell with the Live / Upload toggle UI so navigation and
/// layout can be reviewed before the model is ready.
class CrayfishScanScreen extends StatefulWidget {
  final String batchId;

  const CrayfishScanScreen({super.key, required this.batchId});

  @override
  State<CrayfishScanScreen> createState() => _CrayfishScanScreenState();
}

class _CrayfishScanScreenState extends State<CrayfishScanScreen> {
  // 0 = Live, 1 = Upload
  int _mode = 0;

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
              child: _mode == 0 ? _buildLivePlaceholder() : _buildUploadPlaceholder(),
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
            onPressed: () => Navigator.of(context).pop(),
          ),
          Text(
            'Gender Scan',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
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
      onTap: () => setState(() => _mode = index),
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

  Widget _buildLivePlaceholder() {
    // TODO(model): replace with CameraPreview + per-frame TFLite inference
    // once CrayfishDetectionService is wired up.
    return _buildPlaceholderBody(
      icon: Icons.videocam_rounded,
      title: 'Live camera preview',
      subtitle: 'Camera stream + real-time detection\nwill render here once the model is ready.',
    );
  }

  Widget _buildUploadPlaceholder() {
    // TODO(model): replace with image_picker capture/gallery pick +
    // single-shot TFLite inference once CrayfishDetectionService is wired up.
    return _buildPlaceholderBody(
      icon: Icons.add_a_photo_rounded,
      title: 'Upload a photo',
      subtitle: 'Pick a photo from camera or gallery\nto detect gender once the model is ready.',
    );
  }

  Widget _buildPlaceholderBody({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryWith(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.4), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
