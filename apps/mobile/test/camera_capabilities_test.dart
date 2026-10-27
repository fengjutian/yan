import 'package:ai_image_studio/features/camera/data/camera_capabilities.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yan.camera/capabilities');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('解析原生相机能力', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getCapabilities');
          return <String, Object>{
            'platform': 'android',
            'lensTypes': <String>['front', 'back'],
            'extensionModes': <String>['hdr', 'night'],
            'hasFlash': true,
            'supportsMultiCamera': true,
            'lenses': <Map<String, Object>>[
              <String, Object>{
                'id': '0',
                'facing': 'back',
                'type': 'wide',
                'focalLengths': <double>[6.8],
                'minIso': 50,
                'maxIso': 6400,
                'minExposureSeconds': 0.000125,
                'maxExposureSeconds': 30,
                'minimumFocusDistance': 10,
                'nominalZoom': 1,
                'supportsRaw': true,
                'supportsManualControls': true,
                'minKelvin': 2000,
                'maxKelvin': 8000,
                'manualUnavailableReason': '',
              },
            ],
          };
        });

    final value = await CameraCapabilitiesService().load();

    expect(value.platform, 'android');
    expect(value.lensTypes, ['front', 'back']);
    expect(value.extensionModes, ['hdr', 'night']);
    expect(value.hasFlash, isTrue);
    expect(value.supportsMultiCamera, isTrue);
    expect(value.hasAdvancedExtensions, isTrue);
    expect(value.lenses, hasLength(1));
    expect(value.lenses.single.type, 'wide');
    expect(value.lenses.single.focalLengths, [6.8]);
    expect(value.lenses.single.supportsManualFocus, isTrue);
    expect(value.lenses.single.supportsRaw, isTrue);
    expect(value.lenses.single.supportsManualControls, isTrue);
    expect(value.lenses.single.minKelvin, 2000);
    expect(value.lenses.single.maxKelvin, 8000);
  });

  test('原生桥接不可用时安全回退', () async {
    final value = await CameraCapabilitiesService().load();

    expect(value.platform, 'unknown');
    expect(value.lensTypes, isEmpty);
    expect(value.extensionModes, isEmpty);
  });

  test('解析剩余存储、内存和温度诊断', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getDiagnostics');
          return <String, Object>{
            'freeStorageMb': 2048,
            'totalStorageMb': 8192,
            'availableMemoryMb': 512,
            'totalMemoryMb': 4096,
            'lowMemory': true,
            'thermalStatus': 'moderate',
          };
        });

    final value = await CameraCapabilitiesService().loadDiagnostics();

    expect(value.freeStorageMb, 2048);
    expect(value.totalStorageMb, 8192);
    expect(value.availableMemoryMb, 512);
    expect(value.lowMemory, isTrue);
    expect(value.thermalLabel, '中度升温');
  });

  test('诊断桥接缺失时返回空数据', () async {
    final value = await CameraCapabilitiesService().loadDiagnostics();

    expect(value.hasData, isFalse);
    expect(value.freeStorageMb, isNull);
  });
}
