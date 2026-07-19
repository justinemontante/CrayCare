/// A single detection result from the crayfish gender model.
///
/// [left], [top], [right], [bottom] are normalized (0.0-1.0) relative to
/// the image the detection was run on, so callers can scale them to
/// whatever widget size is displaying the image/camera preview.
class CrayfishDetection {
  final String label;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const CrayfishDetection({
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;

  bool get isMale => label.toLowerCase() == 'male';
  bool get isFemale => label.toLowerCase() == 'female';

  @override
  String toString() =>
      'CrayfishDetection($label, ${(confidence * 100).toStringAsFixed(1)}%, '
      'box: [$left, $top, $right, $bottom])';
}
