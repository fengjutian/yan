import 'package:ai_image_studio/app/router.dart';
import 'package:ai_image_studio/app/theme.dart';
import 'package:flutter/material.dart';

class AiImageStudioApp extends StatelessWidget {
  const AiImageStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AI Image Studio',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
    );
  }
}

