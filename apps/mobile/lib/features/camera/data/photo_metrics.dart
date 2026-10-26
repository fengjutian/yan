import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// 一张照片用于选片的质量指标。
///
/// 指标直接基于解码后的像素计算；拍摄流程在裁剪和风格处理完成后顺带
/// 计算，避免选片阶段再把同一张 JPEG 解码一次。
class PhotoAnalysisMetrics {
  const PhotoAnalysisMetrics({
    required this.score,
    required this.sharpness,
    required this.exposure,
    required this.contrast,
    required this.clippingPenalty,
    required this.averageLuminance,
    required this.hash,
  });

  /// 解码失败或数据不可用时的兜底值。
  static const unavailable = PhotoAnalysisMetrics(
    score: 0,
    sharpness: 0,
    exposure: 0,
    contrast: 0,
    clippingPenalty: 100,
    averageLuminance: 0,
    hash: 0,
  );

  final double score;
  final double sharpness;
  final double exposure;
  final double contrast;
  final double clippingPenalty;
  final double averageLuminance;

  /// 64 位感知哈希，用于连拍去重。
  final int hash;
}

/// 在已经解码的照片上计算质量指标。
///
/// 采样时缩到 120px 宽，指标只用于相对排序，不需要原图精度。
PhotoAnalysisMetrics analyzePhotoMetrics(img.Image decoded) {
  final image = img.copyResize(decoded, width: 120);
  var luminance = 0.0;
  var squaredLuminance = 0.0;
  var edges = 0.0;
  var clippedHighlights = 0;
  var clippedShadows = 0;
  var count = 0;
  for (var y = 1; y < image.height - 1; y += 2) {
    for (var x = 1; x < image.width - 1; x += 2) {
      double gray(img.Pixel p) => .299 * p.r + .587 * p.g + .114 * p.b;
      final center = gray(image.getPixel(x, y));
      luminance += center;
      squaredLuminance += center * center;
      edges += (center - gray(image.getPixel(x + 1, y))).abs();
      edges += (center - gray(image.getPixel(x, y + 1))).abs();
      if (center >= 248) clippedHighlights++;
      if (center <= 7) clippedShadows++;
      count++;
    }
  }
  if (count == 0) return PhotoAnalysisMetrics.unavailable;
  final light = luminance / count;
  final variance = math.max(0, squaredLuminance / count - light * light);
  final sharpness = (edges / count * 2.2).clamp(0, 100).toDouble();
  final exposure = ((1 - (light - 135).abs() / 135) * 100)
      .clamp(0, 100)
      .toDouble();
  final contrast = (math.sqrt(variance) * 2.4).clamp(0, 100).toDouble();
  final clippingPenalty = ((clippedHighlights + clippedShadows) / count * 100)
      .clamp(0, 100)
      .toDouble();
  final score =
      (sharpness * .48 +
              exposure * .30 +
              contrast * .22 -
              clippingPenalty * .35)
          .clamp(0, 100)
          .toDouble();
  return PhotoAnalysisMetrics(
    score: score,
    sharpness: sharpness,
    exposure: exposure,
    contrast: contrast,
    clippingPenalty: clippingPenalty,
    averageLuminance: light,
    hash: _averageHash(decoded),
  );
}

int _averageHash(img.Image source) {
  final tiny = img.copyResize(source, width: 8, height: 8);
  final values = <double>[];
  for (final pixel in tiny) {
    values.add(.299 * pixel.r + .587 * pixel.g + .114 * pixel.b);
  }
  final average = values.fold<double>(0, (sum, value) => sum + value) / 64;
  var hash = 0;
  for (var index = 0; index < values.length; index++) {
    if (values[index] >= average) hash |= 1 << index;
  }
  return hash;
}
