import 'package:ai_image_studio/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows login form', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiImageStudioApp()));

    expect(find.text('欢迎回来'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('没有账号？注册'), findsOneWidget);
  });
}
