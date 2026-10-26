import 'package:ai_image_studio/features/camera/data/camera_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('诊断报告包含初始化、分析、存储和降级信息', () {
    const diagnostics = CameraDiagnostics(
      platform: 'android',
      lensId: '0',
      lensType: 'wide',
      initializationMs: 820,
      initializationStage: '就绪',
      analysisFps: 3.8,
      analysisFormat: 'nv21',
      captureQuality: '1080p',
      activeAnalyzers: ['直方图', '稳定度'],
      degraded: ['独立测光点不可用'],
      freeStorageMb: 1536,
      totalStorageMb: 2048,
      availableMemoryMb: 512,
      totalMemoryMb: 4096,
      lowMemory: false,
      thermalStatus: 'light',
    );

    final report = diagnostics.buildReport(now: DateTime.utc(2026, 1, 1, 12));

    expect(report, contains('平台: android'));
    expect(report, contains('初始化: 820 ms'));
    expect(report, contains('分析帧率: 3.8 fps'));
    expect(report, contains('拍照分辨率: 1080p'));
    expect(report, contains('启用分析: 直方图、稳定度'));
    expect(report, contains('降级状态: 独立测光点不可用'));
    expect(report, contains('存储: 1.5 GB 可用 / 2.0 GB'));
    expect(report, contains('内存: 512 MB 可用 / 4.0 GB'));
    expect(report, contains('温度: light'));
  });

  test('诊断报告会移除路径、URL 和密钥片段', () {
    const diagnostics = CameraDiagnostics(
      platform: 'ios',
      initializationStage: '打开相机',
      lastError:
          r'failed C:\Users\me\photo.jpg https://example.com/a sk_1234567890',
    );

    final report = diagnostics.buildReport();

    expect(report, isNot(contains('C:\\Users')));
    expect(report, isNot(contains('https://')));
    expect(report, isNot(contains('sk_1234567890')));
    expect(report, contains('[path]'));
    expect(report, contains('[url]'));
    expect(report, contains('[key]'));
  });

  test('存储、内存和温度异常会产生预警', () {
    const diagnostics = CameraDiagnostics(
      platform: 'android',
      freeStorageMb: 120,
      availableMemoryMb: 120,
      lowMemory: true,
      thermalStatus: 'severe',
    );

    expect(
      diagnostics.warnings,
      containsAll(['存储空间不足 500 MB', '可用内存偏低', '设备温度偏高']),
    );
    expect(diagnostics.buildReport(), contains('预警:'));
  });

  test('系统诊断信息可读性', () {
    const diagnostics = DeviceDiagnostics(
      freeStorageMb: 100,
      availableMemoryMb: 200,
      lowMemory: true,
      thermalStatus: 'serious',
    );

    expect(diagnostics.hasData, isTrue);
    expect(diagnostics.thermalLabel, '高温');
    expect(const DeviceDiagnostics().hasData, isFalse);
    expect(const DeviceDiagnostics().thermalLabel, '未知');
  });
}
