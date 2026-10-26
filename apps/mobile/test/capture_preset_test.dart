import 'dart:convert';

import 'package:ai_image_studio/features/camera/data/capture_preset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('内置预设覆盖首期场景表', () {
    final presets = {
      for (final preset in CapturePresetRepository.builtInPresets)
        preset.name: preset,
    };

    expect(presets.keys, containsAll(['人像', '美食', '夜景', '宠物', '探店', '风景']));
    expect(presets['人像']!.aspectRatio, .75);
    expect(presets['人像']!.guide, 'thirds');
    expect(presets['人像']!.burstCount, 5);
    expect(presets['人像']!.style, 'soft');
    expect(presets['美食']!.aspectRatio, 1);
    expect(presets['美食']!.enhancement, 'multiFrameHdr');
    expect(presets['美食']!.style, 'warm');
    expect(presets['夜景']!.aspectRatio, .5625);
    expect(presets['夜景']!.enhancement, 'nightDenoise');
    expect(presets['夜景']!.style, 'cool');
    expect(presets['宠物']!.burstCount, 5);
    expect(presets['宠物']!.style, 'vivid');
    expect(presets['探店']!.guide, 'frame');
    expect(presets['探店']!.enhancement, 'multiFrameHdr');
    expect(presets['风景']!.aspectRatio, closeTo(16 / 9, .001));
    expect(presets['风景']!.style, 'vivid');
  });

  test('自定义预设重启后仍然存在', () async {
    final repository = CapturePresetRepository();
    const custom = CapturePreset(
      id: 'custom.1',
      name: '我的探店',
      aspectRatio: .75,
      guide: 'frame',
      burstCount: 1,
      enhancement: 'multiFrameHdr',
      style: 'warm',
    );

    await repository.saveCustom([custom]);
    final loaded = await CapturePresetRepository().load();

    expect(loaded.builtIn, hasLength(6));
    expect(loaded.custom, hasLength(1));
    expect(loaded.custom.single.name, '我的探店');
    expect(loaded.custom.single.guide, 'frame');
    expect(loaded.custom.single.style, 'warm');
  });

  test('旧数据中的非法参数会降级而不是导致失败', () async {
    SharedPreferences.setMockInitialValues({
      CapturePresetRepository.storageKey: jsonEncode({
        'custom': [
          {
            'id': 'legacy',
            'name': '旧预设',
            'aspectRatio': 9.9,
            'guide': 'unknown',
            'burstCount': 9,
            'enhancement': 'raw',
            'style': 'sepia',
          },
        ],
      }),
    });

    final catalog = await CapturePresetRepository().load();
    final preset = catalog.custom.single;

    expect(preset.name, '旧预设');
    expect(preset.aspectRatio, .75);
    expect(preset.guide, 'thirds');
    expect(preset.burstCount, 1);
    expect(preset.enhancement, 'standard');
    expect(preset.style, 'standard');
  });

  test('损坏的 JSON 回退到内置预设', () async {
    SharedPreferences.setMockInitialValues({
      CapturePresetRepository.storageKey: 'not-json',
    });

    final catalog = await CapturePresetRepository().load();

    expect(catalog.builtIn, hasLength(6));
    expect(catalog.custom, isEmpty);
  });

  test('自定义数据不能覆盖内置预设 ID', () async {
    SharedPreferences.setMockInitialValues({
      CapturePresetRepository.storageKey: jsonEncode({
        'schemaVersion': 1,
        'custom': [
          {
            'id': 'builtin.portrait',
            'name': '假人像',
            'aspectRatio': .75,
            'guide': 'thirds',
            'burstCount': 5,
            'enhancement': 'standard',
            'style': 'soft',
          },
        ],
      }),
    });

    final catalog = await CapturePresetRepository().load();

    expect(catalog.custom.single.id, startsWith('custom.'));
    expect(catalog.byId('builtin.portrait')!.name, '人像');
  });
}
