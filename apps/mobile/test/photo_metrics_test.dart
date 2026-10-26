import 'package:ai_image_studio/features/camera/data/photo_metrics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _gradientImage() {
  final image = img.Image(width: 32, height: 24);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final value = (x * 255 ~/ (image.width - 1)).clamp(0, 255);
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

(Uint8List, PhotoAnalysisMetrics) _analyzeInIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes)!;
  return (bytes, analyzePhotoMetrics(decoded));
}

void main() {
  test('解码后的图像能算出可排序的质量指标', () {
    final metrics = analyzePhotoMetrics(_gradientImage());

    expect(metrics.score, inInclusiveRange(0, 100));
    expect(metrics.sharpness, inInclusiveRange(0, 100));
    expect(metrics.exposure, inInclusiveRange(0, 100));
    expect(metrics.contrast, inInclusiveRange(0, 100));
    expect(metrics.clippingPenalty, inInclusiveRange(0, 100));
    expect(metrics.hash, isNot(0));
  });

  test('指标可以跨 isolate 返回，供选片阶段直接复用', () async {
    final bytes = Uint8List.fromList(img.encodeJpg(_gradientImage()));

    final result = await compute(_analyzeInIsolate, bytes);

    expect(result.$1, bytes);
    expect(result.$2.score, inInclusiveRange(0, 100));
  });
}
