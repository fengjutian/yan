import 'package:ai_image_studio/app/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('主题模式保存后可以恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ThemeModeController();

    await controller.setThemeMode(ThemeMode.dark);
    final restored = ThemeModeController();
    await restored.load();

    expect(restored.state, ThemeMode.dark);
  });

  test('未知主题配置回退为跟随系统', () async {
    SharedPreferences.setMockInitialValues({
      'appearance.theme_mode': 'unknown',
    });
    final controller = ThemeModeController();

    await controller.load();

    expect(controller.state, ThemeMode.system);
  });
}
