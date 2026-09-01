import 'package:ai_image_studio/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows creation entry points', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiImageStudioApp()));

    expect(find.text('文生图'), findsOneWidget);
    expect(find.text('人物参考创作'), findsOneWidget);
  });
}
