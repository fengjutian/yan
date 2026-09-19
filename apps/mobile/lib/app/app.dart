import 'package:ai_image_studio/app/router.dart';
import 'package:ai_image_studio/app/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiImageStudioApp extends ConsumerWidget {
  const AiImageStudioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'AI Image Studio',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        // 兜底:即使 build 抛错,也不要让整屏变红/白屏。
        ErrorWidget.builder = (FlutterErrorDetails details) {
          if (kDebugMode) {
            return ErrorWidget(details.exception);
          }
          return const _FallbackErrorWidget();
        };
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

class _FallbackErrorWidget extends StatelessWidget {
  const _FallbackErrorWidget();
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFFAF6F0),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 48, color: Color(0xFFB7791F)),
                const SizedBox(height: 12),
                Text('页面出了一点小问题',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      );
}
