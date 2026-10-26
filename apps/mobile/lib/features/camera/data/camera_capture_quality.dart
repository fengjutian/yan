/// 相机的拍照分辨率档位。
///
/// camera 插件把预览、拍照和图像分析绑定在同一个分辨率上，升到 1080p
/// 会让每帧分析数据变成原来的 2.25 倍，因此低端设备必须保留 720p。
enum CameraCaptureQuality {
  standard('720p'),
  high('1080p');

  const CameraCaptureQuality(this.label);

  /// 诊断报告和设置界面使用的短标签。
  final String label;
}

/// 根据设备能力选择拍照分辨率。
///
/// 判断顺序：
/// 1. iOS 设备统一使用 1080p；
/// 2. Android 物理内存 >= 5 GB 使用 1080p；
/// 3. 其余情况（低内存或读不到内存）回退 720p，保证不劣化现有体验。
class CameraCaptureQualityPolicy {
  const CameraCaptureQualityPolicy._();

  /// 4 GB 设备实际可用内存通常低于 4 GB，6 GB 设备通常高于 5 GB，
  /// 用这个阈值可以把两档设备稳定分开。
  static const int highMemoryThresholdMb = 5000;

  static CameraCaptureQuality decide({
    required bool isIOS,
    int? totalMemoryMb,
  }) {
    if (isIOS) return CameraCaptureQuality.high;
    if (totalMemoryMb == null) return CameraCaptureQuality.standard;
    return totalMemoryMb >= highMemoryThresholdMb
        ? CameraCaptureQuality.high
        : CameraCaptureQuality.standard;
  }
}
