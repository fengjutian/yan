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
  });

  test('原生桥接不可用时安全回退', () async {
    final value = await CameraCapabilitiesService().load();

    expect(value.platform, 'unknown');
    expect(value.lensTypes, isEmpty);
    expect(value.extensionModes, isEmpty);
  });
}
