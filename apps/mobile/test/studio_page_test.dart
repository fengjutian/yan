import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/history/presentation/recent_creations_controller.dart';
import 'package:ai_image_studio/features/studio/presentation/studio_page.dart';
import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:ai_image_studio/features/templates/presentation/templates_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpStudio(
  WidgetTester tester, {
  List<ImageTask> recent = const [],
  List<InspirationTemplate> templates = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recentCreationsProvider.overrideWith((ref) async => recent),
        featuredTemplatesProvider.overrideWith((ref) async => templates),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const StudioPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空工作室给出导入和拍摄入口', (tester) async {
    await _pumpStudio(tester);

    expect(find.text('让照片成为作品'), findsOneWidget);
    expect(find.text('先放一张照片进来'), findsOneWidget);
    expect(find.text('从相册导入'), findsOneWidget);
    expect(find.text('去拍一张'), findsOneWidget);
    expect(find.text('快捷工具'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('最近作品'), findsOneWidget);
    expect(find.text('还没有作品'), findsOneWidget);
  });

  testWidgets('最近作品展示类型与时间', (tester) async {
    final now = DateTime.now();
    final task = ImageTask(
      id: 'local-1',
      status: 'SUCCEEDED',
      progress: 100,
      prompt: '测试作品',
      images: const [],
      type: 'STYLE_TRANSFER',
      createdAt: DateTime(now.year, now.month, now.day, 8, 5),
      local: true,
    );

    await _pumpStudio(tester, recent: [task]);

    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('最近作品'), findsOneWidget);
    expect(find.text('风格迁移'), findsOneWidget);
    expect(find.text('今天 08:05'), findsOneWidget);
    expect(find.text('还没有作品'), findsNothing);
  });
}
