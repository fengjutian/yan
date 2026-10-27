import 'package:ai_image_studio/features/camera/data/camera_capabilities.dart';
import 'package:ai_image_studio/features/camera/data/manual_camera_controls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lens = NativeCameraLens(
    id: '0',
    facing: 'back',
    type: 'wide',
    focalLengths: [6.8],
    minIso: 50,
    maxIso: 3200,
    minExposureSeconds: .000125,
    maxExposureSeconds: .5,
    minimumFocusDistance: 0,
    nominalZoom: 1,
    supportsRaw: false,
    supportsManualControls: true,
    minKelvin: 2000,
    maxKelvin: 8000,
  );

  test('手动范围来自镜头能力', () {
    final range = ManualCameraRange.fromLens(lens);

    expect(range.minIso, 50);
    expect(range.maxIso, 3200);
    expect(range.minShutterSeconds, .000125);
    expect(range.maxShutterSeconds, .5);
    expect(range.isUsable, isTrue);
  });

  test('非法能力值会退化为可用范围', () {
    final range = ManualCameraRange.fromLens(
      const NativeCameraLens(
        id: '1',
        facing: 'back',
        type: 'wide',
        focalLengths: [],
        minIso: 0,
        maxIso: 0,
        minExposureSeconds: 0,
        maxExposureSeconds: 0,
        minimumFocusDistance: 0,
        nominalZoom: 1,
        supportsRaw: false,
      ),
    );

    expect(range.minIso, greaterThan(0));
    expect(range.maxIso, greaterThan(range.minIso));
    expect(range.maxShutterSeconds, greaterThan(range.minShutterSeconds));
    expect(range.isUsable, isTrue);
  });

  test('设置值会被夹紧到硬件范围', () {
    final range = ManualCameraRange.fromLens(lens);
    final settings = const ManualCameraSettings(
      mode: ManualCameraMode.manual,
      iso: 99999,
      shutterSeconds: 10,
      kelvin: 200,
      focus: 2,
    ).clamped(range);

    expect(settings.iso, 3200);
    expect(settings.shutterSeconds, .5);
    expect(settings.kelvin, 2000);
    expect(settings.focus, 1);
  });

  test('auto 模式序列化后不携带手动参数语义', () {
    final map = ManualCameraSettings.auto.toMap();

    expect(map['mode'], 'auto');
    expect(map['iso'], 100);
    expect(map['shutterSeconds'], closeTo(1 / 60, .0001));
  });
}
