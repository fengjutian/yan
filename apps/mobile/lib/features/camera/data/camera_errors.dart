import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// 相机初始化/拍摄失败时给用户看的文案。
///
/// 单独放在数据层，方便对权限、UseCase 绑定失败等分支做单元测试。
String cameraErrorMessage(Object error) {
  final details = error.toString();
  if (details.contains('No supported surface combination') ||
      details.contains('UseCaseAdapter') ||
      details.contains('bind too many use cases')) {
    return '当前设备无法同时启用实时分析与拍照，请重试；应用会自动使用兼容模式。';
  }
  if (error is CameraException) {
    if (error.code == 'CameraAccessDenied' ||
        error.code == 'CameraAccessDeniedWithoutPrompt') {
      return '需要相机权限才能拍摄，请在系统设置中允许访问';
    }
    return error.description ?? '相机暂时不可用';
  }
  if (error is PlatformException) {
    if (error.code == 'CameraAccessDenied' ||
        error.code == 'camera_permission' ||
        error.code == 'MissingPluginException') {
      return '需要相机权限才能拍摄，请在系统设置中允许访问';
    }
    return error.message ?? '相机暂时不可用';
  }
  return error.toString();
}

/// 是否为相机权限类错误。永久拒绝时需要引导用户去系统设置。
bool isCameraPermissionError(Object error) {
  if (error is CameraException) {
    return error.code == 'CameraAccessDenied' ||
        error.code == 'CameraAccessDeniedWithoutPrompt' ||
        error.code == 'CameraAccessRestricted';
  }
  if (error is PlatformException) {
    return error.code == 'CameraAccessDenied' ||
        error.code == 'camera_permission';
  }
  return false;
}
