import 'package:ai_image_studio/features/camera/data/camera_capture_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS 统一使用 1080p', () {
    expect(
      CameraCaptureQualityPolicy.decide(isIOS: true, totalMemoryMb: 2048),
      CameraCaptureQuality.high,
    );
    expect(
      CameraCaptureQualityPolicy.decide(isIOS: true),
      CameraCaptureQuality.high,
    );
  });

  test('Android 大内存设备使用 1080p', () {
    expect(
      CameraCaptureQualityPolicy.decide(isIOS: false, totalMemoryMb: 5800),
      CameraCaptureQuality.high,
    );
  });

  test('Android 小内存设备回退 720p', () {
    expect(
      CameraCaptureQualityPolicy.decide(isIOS: false, totalMemoryMb: 3800),
      CameraCaptureQuality.standard,
    );
  });

  test('读不到内存时使用保守的 720p', () {
    expect(
      CameraCaptureQualityPolicy.decide(isIOS: false),
      CameraCaptureQuality.standard,
    );
  });

  test('阈值边界按 1080p 处理', () {
    expect(
      CameraCaptureQualityPolicy.decide(
        isIOS: false,
        totalMemoryMb: CameraCaptureQualityPolicy.highMemoryThresholdMb,
      ),
      CameraCaptureQuality.high,
    );
  });

  test('分辨率标签可直接用于诊断', () {
    expect(CameraCaptureQuality.standard.label, '720p');
    expect(CameraCaptureQuality.high.label, '1080p');
  });
}
