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
  });
}
