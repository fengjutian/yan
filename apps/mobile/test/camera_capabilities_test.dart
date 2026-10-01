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
          };
        });

    final value = await CameraCapabilitiesService().load();

    expect(value.platform, 'android');
    expect(value.lensTypes, ['front', 'back']);
    expect(value.extensionModes, ['hdr', 'night']);
    expect(value.hasFlash, isTrue);
    expect(value.supportsMultiCamera, isTrue);
    expect(value.hasAdvancedExtensions, isTrue);
  });

  test('原生桥接不可用时安全回退', () async {
    final value = await CameraCapabilitiesService().load();

    expect(value.platform, 'unknown');
    expect(value.lensTypes, isEmpty);
    expect(value.extensionModes, isEmpty);
  });
}
