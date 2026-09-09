import 'package:ai_image_studio/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
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
        tween: Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 24,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 48),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeInCubic),
        ),
        weight: 28,
      ),
    ]).animate(_controller);
    _scale = Tween<double>(begin: .94, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _controller.forward().whenComplete(() {
      if (mounted) context.go('/home');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: const Text(
              '颜',
              semanticsLabel: '颜',
              style: TextStyle(
                color: AppColors.ink,
                fontFamily: 'Source Han Serif SC',
                fontFamilyFallback: [
                  'Source Han Serif CN',
                  'Noto Serif CJK SC',
                  'Noto Serif SC',
                  'STSong',
                  'SimSun',
                  'serif',
                ],
                fontSize: 92,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
