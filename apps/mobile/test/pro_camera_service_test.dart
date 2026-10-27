import 'package:ai_image_studio/features/camera/data/pro_camera_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析原生专业模式会话信息', () {
    final info = ProCameraSessionInfo.fromMap({
      'textureId': 7,
      'width': 1280,
      'height': 960,
      'sensorOrientation': 90,
      'minZoom': 1.0,
      'maxZoom': 8.0,
    });

    expect(info.textureId, 7);
    expect(info.width, 1280);
    expect(info.height, 960);
    expect(info.sensorOrientation, 90);
    expect(info.minZoom, 1.0);
    expect(info.maxZoom, 8.0);
    expect(info.aspectRatio, closeTo(4 / 3, .0001));
  });

  test('缺失会话信息时使用安全默认值', () {
    final info = ProCameraSessionInfo.fromMap(const {});

    expect(info.textureId, 0);
    expect(info.aspectRatio, closeTo(4 / 3, .0001));
    expect(info.minZoom, 1.0);
    expect(info.maxZoom, 1.0);
  });
}
