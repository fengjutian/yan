import 'package:ai_image_studio/features/camera/data/camera_capabilities.dart';
import 'package:ai_image_studio/features/camera/data/capture_preset.dart';
import 'package:ai_image_studio/features/camera/presentation/camera_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AE/AF 锁定标签在不同状态下清晰可辨', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CameraFocusRing(locked: true, exposureLocked: true),
        ),
      ),
    );
    expect(find.text('AE/AF 锁定'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CameraFocusRing(locked: false, exposureLocked: false),
        ),
      ),
    );
    expect(find.text('AF'), findsOneWidget);
    expect(find.text('AE/AF 锁定'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CameraMeteringRing(locked: true))),
    );
    expect(find.text('AE 锁定'), findsOneWidget);
  });

  testWidgets('场景预设面板可应用、复制、删除和保存当前设置', (tester) async {
    const custom = CapturePreset(
      id: 'custom.1',
      name: '我的美食',
      aspectRatio: 1,
      guide: 'center',
      burstCount: 1,
      enhancement: 'multiFrameHdr',
      style: 'warm',
    );
    CapturePreset? applied;
    CapturePreset? copied;
    CapturePreset? deleted;
    var savedCurrent = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraPresetSheet(
            builtIn: CapturePresetRepository.builtInPresets
                .take(2)
                .toList(growable: false),
            custom: const [custom],
            activeId: 'builtin.portrait',
            onApply: (preset) => applied = preset,
            onCopy: (preset) => copied = preset,
            onDelete: (preset) => deleted = preset,
            onSaveCurrent: () => savedCurrent = true,
          ),
        ),
      ),
    );

    expect(find.text('场景拍摄预设'), findsOneWidget);
    expect(find.text('人像'), findsOneWidget);
    expect(find.text('我的预设'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.text('美食'));
    expect(applied?.name, '美食');

    await tester.tap(find.byTooltip('复制为自定义预设').first);
    expect(copied?.name, '人像');

    await tester.tap(find.byTooltip('删除自定义预设'));
    expect(deleted?.id, 'custom.1');

    await tester.tap(find.text('保存当前'));
    expect(savedCurrent, isTrue);
  });

  testWidgets('专业参数只展示当前镜头支持项，其余置灰', (tester) async {
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
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraProfessionalPanel(
            lens: lens,
            exposure: 0,
            minExposure: -2,
            maxExposure: 2,
            onExposureChanged: (_) {},
          ),
        ),
      ),
    );

    final iso = tester.widget<CameraParameterChip>(
      find.widgetWithText(CameraParameterChip, 'ISO 50–3200'),
    );
    expect(iso.enabled, isTrue);
    final focus = tester.widget<CameraParameterChip>(
      find.widgetWithText(CameraParameterChip, '手动对焦'),
    );
    expect(focus.enabled, isFalse);
    final raw = tester.widget<CameraParameterChip>(
      find.widgetWithText(CameraParameterChip, 'RAW/DNG'),
    );
    expect(raw.enabled, isFalse);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('没有镜头能力时不显示曝光滑杆', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraProfessionalPanel(
            lens: null,
            exposure: 0,
            minExposure: 0,
            maxExposure: 0,
            onExposureChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('当前镜头未报告专业参数'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    final iso = tester.widget<CameraParameterChip>(
      find.widgetWithText(CameraParameterChip, 'ISO'),
    );
    expect(iso.enabled, isFalse);
  });
}
