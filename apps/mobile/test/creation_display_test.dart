import 'package:ai_image_studio/features/history/presentation/creation_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 26, 21, 15);

  test('作品类型显示为中文', () {
    expect(creationTypeLabel('STYLE_TRANSFER'), '风格迁移');
    expect(creationTypeLabel('TEXT_TO_IMAGE'), 'AI 创作');
    expect(creationTypeLabel('SOMETHING_NEW'), '作品');
  });

  test('今天和昨天带具体时间', () {
    expect(
      creationTimeLabel(DateTime(2026, 10, 26, 8, 5), now: now),
      '今天 08:05',
    );
    expect(
      creationTimeLabel(DateTime(2026, 10, 25, 19, 30), now: now),
      '昨天 19:30',
    );
  });

  test('今年更早的日期显示月日,跨年显示完整日期', () {
    expect(creationTimeLabel(DateTime(2026, 3, 2), now: now), '3 月 2 日');
    expect(creationTimeLabel(DateTime(2025, 12, 31), now: now), '2025.12.31');
  });

  test('时间缺失时返回空字符串', () {
    expect(creationTimeLabel(null), '');
  });
}
