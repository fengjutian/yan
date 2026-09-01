import 'package:ai_image_studio/features/auth/presentation/auth_page.dart';
import 'package:ai_image_studio/features/assets/presentation/asset_upload_page.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_page.dart';
import 'package:ai_image_studio/features/reference/presentation/reference_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows login form', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AuthPage(mode: AuthMode.login)),
      ),
    );

    expect(find.text('欢迎回来'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('没有账号？注册'), findsOneWidget);
  });

  testWidgets('shows reference image upload controls', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AssetUploadPage())),
    );

    expect(find.text('上传参考图片'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('从相册选择'), findsOneWidget);
    expect(find.text('上传图片'), findsOneWidget);
  });

  testWidgets('shows text to image form', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GeneratePage())),
    );

    expect(find.text('文生图'), findsOneWidget);
    expect(find.text('画面描述'), findsOneWidget);
    expect(find.text('自动优化 Prompt'), findsOneWidget);
  });

  testWidgets('shows character reference form', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ReferencePage(loadStylesOnStart: false)),
      ),
    );
    await tester.pump();

    expect(find.text('人物参考创作'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pump();
    expect(find.text('选择并上传参考图'), findsOneWidget);
    expect(find.text('场景描述'), findsOneWidget);
  });
}
