import 'dart:typed_data';

import 'package:ai_image_studio/features/camera/data/camera_session.dart';
import 'package:ai_image_studio/features/camera/data/photo_metrics.dart';
import 'package:ai_image_studio/features/camera/data/photo_quality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _testPhoto() {
  final image = img.Image(width: 48, height: 36);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final value = (x * 5 + y * 3).clamp(0, 255);
      image.setPixelRgb(x, y, value, (value + 40).clamp(0, 255), 120);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

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

  test('复用预计算指标时不再解码照片', () async {
    final controller = CameraSessionController();
    // 无效 JPEG：如果仍走解码评分，分数会是 0。
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    await controller.setPhotos(
      [bytes],
      precomputedMetrics: const [
        PhotoAnalysisMetrics(
          score: 88,
          sharpness: 90,
          exposure: 80,
          contrast: 70,
          clippingPenalty: 2,
          averageLuminance: 128,
          hash: 42,
        ),
      ],
    );

    final photo = controller.state.photos.single;
    expect(photo.score, closeTo(88, .001));
    expect(photo.sharpness, 90);
    expect(photo.bytes, bytes);
    expect(photo.reasons, isNotEmpty);
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

  test('快门稳定度写入上下文并参与评分', () async {
    final bytes = _testPhoto();
    final baseline = CameraSessionController();
    await baseline.setPhotos([bytes]);
    final baseScore = baseline.state.photos.single.score;
    final capturedAt = DateTime(2026, 1, 1, 12);

    final controller = CameraSessionController();
    await controller.setPhotos(
      [bytes],
      contexts: [
        CaptureContext(
          cameraId: '0',
          lensType: 'wide',
          zoom: 1,
          exposureOffset: 0,
          stabilityScore: 40,
          capturedAt: capturedAt,
        ),
      ],
    );

    final photo = controller.state.photos.single;
    expect(photo.stability, 40);
    expect(photo.context?.capturedAt, capturedAt);
    expect(
      photo.score,
      closeTo(PhotoQualityEvaluator.applyStability(baseScore, 40), .001),
    );
    expect(photo.reasons, contains('手抖偏多'));
    expect(photo.metrics.stability, 40);
  });

  test('没有稳定度数据时评分保持原样', () async {
    final bytes = _testPhoto();
    final withContext = CameraSessionController();
    await withContext.setPhotos(
      [bytes],
      contexts: [
        CaptureContext(
          cameraId: '0',
          lensType: 'wide',
          zoom: 1,
          exposureOffset: 0,
          capturedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final withoutContext = CameraSessionController();
    await withoutContext.setPhotos([bytes]);

    expect(withContext.state.photos.single.stability, isNull);
    expect(
      withContext.state.photos.single.score,
      closeTo(withoutContext.state.photos.single.score, .001),
    );
  });

  test('人像分析结果参与评分并解释推荐原因', () async {
    final bytes = _testPhoto();
    final controller = CameraSessionController();
    final progress = <double>[];

    await controller.setPhotos(
      [bytes],
      portraitAnalyzer: (input) async => const PortraitQualityMetrics(
        faceCount: 2,
        faceSharpness: 82,
        eyesOpenScore: 96,
        smileScore: 70,
        occlusionRisk: 8,
      ),
      onPortraitProgress: progress.add,
    );

    final photo = controller.state.photos.single;
    expect(photo.portrait, isNotNull);
    expect(photo.portrait!.faceCount, 2);
    expect(photo.reasons, contains('全员睁眼'));
    expect(photo.reasons, contains('人物清晰'));
    expect(progress, [1]);
  });

  test('人像检测失败时保留通用评分', () async {
    final bytes = _testPhoto();
    final controller = CameraSessionController();

    await controller.setPhotos(
      [bytes],
      portraitAnalyzer: (input) async => throw StateError('face model missing'),
    );

    final photo = controller.state.photos.single;
    expect(photo.portrait, isNull);
    expect(photo.score, greaterThan(0));
    expect(photo.qualityLabel, isNotEmpty);
  });

  test('没有人物时人像分析不会改变评分', () async {
    final bytes = _testPhoto();
    final baseline = CameraSessionController();
    await baseline.setPhotos([bytes]);
    final controller = CameraSessionController();

    await controller.setPhotos(
      [bytes],
      portraitAnalyzer: (input) async => const PortraitQualityMetrics(
        faceCount: 0,
        faceSharpness: 0,
        eyesOpenScore: 0,
        smileScore: 0,
        occlusionRisk: 0,
      ),
    );

    expect(controller.state.photos.single.portrait, isNull);
    expect(
      controller.state.photos.single.score,
      closeTo(baseline.state.photos.single.score, .001),
    );
  });
}
