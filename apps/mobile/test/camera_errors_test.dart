import 'package:ai_image_studio/features/camera/data/camera_errors.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('权限拒绝错误会引导用户去系统设置', () {
    final error = CameraException('CameraAccessDenied', 'denied');

    expect(isCameraPermissionError(error), isTrue);
    expect(cameraErrorMessage(error), contains('系统设置'));
  });

  test('永久拒绝和受限也归类为权限错误', () {
    expect(
      isCameraPermissionError(
        CameraException('CameraAccessDeniedWithoutPrompt', 'denied'),
      ),
      isTrue,
    );
    expect(
      isCameraPermissionError(CameraException('CameraAccessRestricted', 'x')),
      isTrue,
    );
    expect(
      isCameraPermissionError(PlatformException(code: 'camera_permission')),
      isTrue,
    );
  });

  test('UseCase 绑定失败给出兼容模式提示', () {
    final error = CameraException(
      'unknown',
      'No supported surface combination',
    );

    expect(cameraErrorMessage(error), contains('兼容模式'));
  });

  test('普通相机错误保留原始描述', () {
    final error = CameraException('init', '相机初始化失败');

    expect(cameraErrorMessage(error), '相机初始化失败');
    expect(isCameraPermissionError(error), isFalse);
  });

  test('非相机错误回退到 toString', () {
    expect(cameraErrorMessage(StateError('boom')), contains('boom'));
  });
}
