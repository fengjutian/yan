import 'dart:async';

import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 24,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 48),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 28,
      ),
    ]).animate(_controller);
    _scale = Tween<double>(begin: .94, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    // GoRouter 用 SynchronousFuture + ChangeNotifier 同步派发,
    // 在 initState/build phase 期间调 context.go 会撞上 "setState during build"。
    // 延后到首帧渲染之后再启动 _start,后续 context.go 也在帧外执行。
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    // Session restoration/guest creation may be delayed by a slow or unreachable
    // network. It must not keep the splash visible after its animation.
    unawaited(ref.read(authControllerProvider.notifier).initialize());
    try {
      await _controller.forward();
    } catch (_) {
      // 即使动画抛错,也要把用户带离 splash,避免永久卡住。
    }
    if (!mounted) return;
    context.go('/home');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandBackground,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Image.asset(
              'assets/branding/yan-logo.png',
              width: 148,
              height: 148,
              fit: BoxFit.contain,
              semanticLabel: '颜 Studio Logo',
            ),
          ),
        ),
      ),
    );
  }
}
