import 'package:ai_image_studio/app/route_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _pushedNext = false;
bool _poppedNext = false;

class _RouteProbe extends StatefulWidget {
  const _RouteProbe();

  @override
  State<_RouteProbe> createState() => _RouteProbeState();
}

class _RouteProbeState extends State<_RouteProbe> with RouteAware {
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || route == _route) return;
    if (_route != null) appRouteObserver.unsubscribe(this);
    _route = route;
    appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _pushedNext = true;

  @override
  void didPopNext() => _poppedNext = true;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('camera-page'));
}

void main() {
  testWidgets('页面被覆盖和重新露出时会收到路由通知', (tester) async {
    _pushedNext = false;
    _poppedNext = false;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: const _RouteProbe(),
      ),
    );

    // GoRouter 使用 MaterialPage<void>，这里用同样的路由类型验证泛型匹配。
    Navigator.of(tester.element(find.text('camera-page'))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('next-page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('next-page'), findsOneWidget);
    expect(_pushedNext, isTrue);

    Navigator.of(tester.element(find.text('next-page'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('camera-page'), findsOneWidget);
    expect(_poppedNext, isTrue);
  });
}
