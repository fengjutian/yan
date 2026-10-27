import 'package:ai_image_studio/features/camera/data/camera_capabilities.dart';
import 'package:ai_image_studio/features/camera/data/capture_preset.dart';
import 'package:ai_image_studio/features/camera/data/manual_camera_controls.dart';
import 'package:ai_image_studio/features/camera/presentation/camera_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('功能分类标签可切换并高亮当前分类', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CameraCategoryChip(
                label: '拍摄',
                selected: true,
                onTap: () => tapped = '拍摄',
              ),
              CameraCategoryChip(
                label: '构图',
                selected: false,
                onTap: () => tapped = '构图',
              ),
            ],
          ),
        ),
      ),
    );

    final selected = tester.widget<Text>(find.text('拍摄'));
    expect(selected.style?.color, Colors.black);
    final unselected = tester.widget<Text>(find.text('构图'));
    expect(unselected.style?.color, Colors.white70);

    await tester.tap(find.text('构图'));
    expect(tapped, '构图');
  });

  testWidgets('设置行展示当前值并可点击选择新值', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraSettingRow(
            label: '画面比例',
            value: '3:4',
            onTap: () => tapped++,
          ),
        ),
      ),
    );

    expect(find.text('画面比例'), findsOneWidget);
    expect(find.text('3:4'), findsOneWidget);
    await tester.tap(find.byType(CameraSettingRow));
    expect(tapped, 1);
  });

  testWidgets('开关行展示当前状态并在点击后回调', (tester) async {
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraSwitchRow(
            label: '镜像自拍',
            value: true,
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );

    expect(find.text('镜像自拍'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    expect(changed, isFalse);
  });

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
      supportsManualControls: true,
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

  testWidgets('权限被永久拒绝时提供系统设置入口', (tester) async {
    var retried = false;
    var openedSettings = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraErrorView(
            message: '需要相机权限才能拍摄，请在系统设置中允许访问',
            permissionPermanentlyDenied: true,
            onRetry: () => retried = true,
            onOpenSettings: () => openedSettings = true,
          ),
        ),
      ),
    );

    expect(find.text('前往系统设置'), findsOneWidget);
    expect(find.text('重试'), findsNothing);

    await tester.tap(find.text('前往系统设置'));
    expect(openedSettings, isTrue);
    expect(retried, isFalse);
  });

  testWidgets('普通相机错误提供重试入口', (tester) async {
    var retried = false;
    var openedSettings = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraErrorView(
            message: '相机暂时不可用',
            permissionPermanentlyDenied: false,
            onRetry: () => retried = true,
            onOpenSettings: () => openedSettings = true,
          ),
        ),
      ),
    );

    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
    expect(openedSettings, isFalse);
  });

  testWidgets('手动参数按模式展示对应滑杆', (tester) async {
    var settings = ManualCameraSettings.auto;
    const range = ManualCameraRange(
      minIso: 50,
      maxIso: 3200,
      minShutterSeconds: .000125,
      maxShutterSeconds: .5,
      minKelvin: 2000,
      maxKelvin: 8000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CameraManualControls(
              supported: true,
              range: range,
              settings: settings,
              unavailableReason: null,
              onChanged: (next) => setState(() => settings = next),
              onReset: () =>
                  setState(() => settings = ManualCameraSettings.auto),
            ),
          ),
        ),
      ),
    );

    expect(find.text('自动'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('半自动'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(2));

    await tester.tap(find.text('全手动'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(4));
  });

  testWidgets('不支持手动参数的设备显示原因而不是滑杆', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraManualControls(
            supported: false,
            range: const ManualCameraRange(
              minIso: 50,
              maxIso: 3200,
              minShutterSeconds: .000125,
              maxShutterSeconds: .5,
              minKelvin: 2000,
              maxKelvin: 8000,
            ),
            settings: ManualCameraSettings.auto,
            unavailableReason: '当前 Android 相机实现未开放 ISO/快门手动控制',
            onChanged: (_) {},
            onReset: () {},
          ),
        ),
      ),
    );

    expect(find.text('当前 Android 相机实现未开放 ISO/快门手动控制'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('全手动'), findsNothing);
  });
}
