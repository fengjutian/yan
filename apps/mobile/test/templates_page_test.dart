import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/templates/presentation/templates_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('模板页支持关键词搜索并隐藏精选区', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const TemplatesHomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('共 8 个模板'), findsOneWidget);
    expect(find.text('本周精选'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '咖啡');
    await tester.pumpAndSettle();

    expect(find.text('找到 1 个模板'), findsOneWidget);
    expect(find.text('咖啡馆随拍'), findsOneWidget);
    expect(find.text('窗边柔光人像'), findsNothing);
    expect(find.text('本周精选'), findsNothing);
  });

  testWidgets('空搜索结果提供清空入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const TemplatesHomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '不存在的场景');
    await tester.pumpAndSettle();

    expect(find.text('没有找到匹配的模板'), findsOneWidget);
    expect(find.text('清空搜索'), findsOneWidget);
  });
}
