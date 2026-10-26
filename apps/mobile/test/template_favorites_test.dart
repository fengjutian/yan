import 'package:ai_image_studio/features/templates/presentation/templates_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('收藏在 preferences 就绪后自动恢复', () async {
    SharedPreferences.setMockInitialValues({
      'template_favorites': ['portrait_window'],
    });
    final notifier = TemplateFavoritesNotifier(
      TemplateFavoritesService(SharedPreferences.getInstance()),
    );
    addTearDown(notifier.dispose);

    await pumpEventQueue();
    expect(notifier.state, {'portrait_window'});
  });

  test('切换收藏后状态与磁盘保持一致', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = TemplateFavoritesNotifier(
      TemplateFavoritesService(SharedPreferences.getInstance()),
    );
    addTearDown(notifier.dispose);
    await pumpEventQueue();

    await notifier.toggle('travel_skyline');
    expect(notifier.state, contains('travel_skyline'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('template_favorites'), ['travel_skyline']);

    await notifier.toggle('travel_skyline');
    expect(notifier.state, isNot(contains('travel_skyline')));
  });
}
