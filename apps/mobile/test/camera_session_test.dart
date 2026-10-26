import 'dart:typed_data';

import 'package:ai_image_studio/features/camera/data/camera_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('连拍评分分批执行并报告进度', () async {
    Uint8List photo(int luminance) {
      final image = img.Image(width: 24, height: 24);
      img.fill(image, color: img.ColorRgb8(luminance, luminance, luminance));
      return Uint8List.fromList(img.encodeJpg(image));
    }

    final controller = CameraSessionController();
    final progress = <double>[];

    await controller.setPhotos([
      photo(40),
      photo(120),
      photo(220),
    ], onProgress: progress.add);

    expect(controller.state.photos, hasLength(3));
    expect(progress, [closeTo(2 / 3, .001), 1]);
    expect(
      controller.state.photos.map((item) => item.score),
      orderedEquals(
        controller.state.photos.map((item) => item.score).toList()
          ..sort((a, b) => b.compareTo(a)),
      ),
    );
    for (final item in controller.state.photos) {
      expect(item.sharpness, inInclusiveRange(0, 100));
      expect(item.exposure, inInclusiveRange(0, 100));
      expect(item.contrast, inInclusiveRange(0, 100));
      expect(item.clippingPenalty, inInclusiveRange(0, 100));
      expect(item.qualityLabel, isNotEmpty);
    }
  });

  test('感知哈希会移除完全相同的连拍照片', () async {
    final image = img.Image(width: 32, height: 32);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final value = (x * 7 + y * 3).clamp(0, 255);
        image.setPixelRgb(x, y, value, 160, 110);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    final controller = CameraSessionController();

    await controller.setPhotos([bytes, bytes, bytes]);

    expect(controller.state.photos, hasLength(1));
    expect(controller.state.selected, isNotNull);
  });
}
