/// 相机诊断快照。只包含设备与状态信息，不包含照片、路径、密钥或位置。
class CameraDiagnostics {
  const CameraDiagnostics({
    required this.platform,
    this.lensId,
    this.lensType,
    this.initializationMs,
    this.initializationStage,
    this.lastError,
    this.analysisFps = 0,
    this.analysisFormat,
    this.activeAnalyzers = const [],
    this.degraded = const [],
    this.freeStorageMb,
    this.totalStorageMb,
    this.availableMemoryMb,
    this.totalMemoryMb,
    this.lowMemory = false,
    this.thermalStatus,
  });

  final String platform;
  final String? lensId;
  final String? lensType;
  final int? initializationMs;
  final String? initializationStage;
  final String? lastError;
  final double analysisFps;
  final String? analysisFormat;
  final List<String> activeAnalyzers;
  final List<String> degraded;
  final int? freeStorageMb;
  final int? totalStorageMb;
  final int? availableMemoryMb;
  final int? totalMemoryMb;
  final bool lowMemory;
  final String? thermalStatus;

  /// 面向用户的预警，避免在拍摄时弹出阻塞对话框。
  List<String> get warnings => [
    if (freeStorageMb != null && freeStorageMb! < 500) '存储空间不足 500 MB',
    if (lowMemory || (availableMemoryMb != null && availableMemoryMb! < 300))
      '可用内存偏低',
    if (thermalStatus == 'severe' ||
        thermalStatus == 'serious' ||
        thermalStatus == 'critical' ||
        thermalStatus == 'emergency' ||
        thermalStatus == 'shutdown')
      '设备温度偏高',
  ];

  /// 生成可复制的纯文本报告，字段经过裁剪，避免泄露图片内容或路径。
  String buildReport({DateTime? now}) {
    final time = (now ?? DateTime.now()).toUtc();
    final lines = <String>[
      'Yan 相机诊断报告',
      '时间: ${time.toIso8601String()}',
      '平台: ${_sanitize(platform)}',
      '相机: ${_sanitize(lensId ?? 'unknown')}'
          '${lensType == null ? '' : ' (${_sanitize(lensType!)})'}',
      initializationMs == null
          ? '初始化: 未完成${initializationStage == null ? '' : ' · 阶段 ${_sanitize(initializationStage!)}'}'
          : '初始化: $initializationMs ms · ${_sanitize(initializationStage ?? 'ready')}',
      '分析帧率: ${analysisFps.toStringAsFixed(1)} fps'
          '${analysisFormat == null ? '' : ' · ${_sanitize(analysisFormat!)}'}',
      '启用分析: ${activeAnalyzers.isEmpty ? '无' : activeAnalyzers.map(_sanitize).join('、')}',
      '降级状态: ${degraded.isEmpty ? '无' : degraded.map(_sanitize).join('、')}',
      if (warnings.isNotEmpty) '预警: ${warnings.map(_sanitize).join('、')}',
      '存储: ${_megabytes(freeStorageMb)} 可用'
          '${totalStorageMb == null ? '' : ' / ${_megabytes(totalStorageMb)}'}',
      '内存: ${_megabytes(availableMemoryMb)} 可用'
          '${totalMemoryMb == null ? '' : ' / ${_megabytes(totalMemoryMb)}'}'
          '${lowMemory ? ' · 系统低内存' : ''}',
      '温度: ${_sanitize(thermalStatus ?? 'unknown')}',
      if (lastError != null && lastError!.isNotEmpty)
        '最近错误: ${_sanitize(lastError!)}',
    ];
    return lines.join('\n');
  }

  static String _megabytes(int? value) {
    if (value == null) return '未知';
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} GB';
    return '$value MB';
  }

  /// 去掉 URL、绝对路径和常见密钥片段，保证报告可安全分享。
  static String _sanitize(String value) {
    var text = value
        .replaceAll(RegExp(r'https?://\S+'), '[url]')
        .replaceAll(RegExp(r'[A-Za-z]:\\[^\s]*'), '[path]')
        .replaceAll(RegExp(r'(?<!\w)/[\w./-]{3,}'), '[path]')
        .replaceAll(RegExp(r'\b(sk|pk)_[A-Za-z0-9]{8,}'), '[key]');
    if (text.length > 180) text = '${text.substring(0, 180)}…';
    return text.replaceAll('\n', ' ');
  }
}

/// 系统级诊断信息，由原生通道提供；不可用时全部为 null。
class DeviceDiagnostics {
  const DeviceDiagnostics({
    this.freeStorageMb,
    this.totalStorageMb,
    this.availableMemoryMb,
    this.totalMemoryMb,
    this.lowMemory = false,
    this.thermalStatus,
  });

  final int? freeStorageMb;
  final int? totalStorageMb;
  final int? availableMemoryMb;
  final int? totalMemoryMb;
  final bool lowMemory;
  final String? thermalStatus;

  bool get hasData =>
      freeStorageMb != null ||
      availableMemoryMb != null ||
      thermalStatus != null;

  String get thermalLabel => switch (thermalStatus) {
    'none' || 'nominal' => '正常',
    'light' => '轻微升温',
    'moderate' => '中度升温',
    'severe' || 'serious' => '高温',
    'critical' || 'emergency' || 'shutdown' => '过热',
    _ => '未知',
  };
}
