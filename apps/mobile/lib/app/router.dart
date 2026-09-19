import 'package:ai_image_studio/features/auth/presentation/auth_page.dart';
import 'package:ai_image_studio/features/auth/presentation/splash_page.dart';
import 'package:ai_image_studio/features/assets/presentation/asset_upload_page.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_page.dart';
import 'package:ai_image_studio/features/home/presentation/home_page.dart';
import 'package:ai_image_studio/features/history/presentation/history_page.dart';
import 'package:ai_image_studio/features/history/presentation/task_detail_page.dart';
import 'package:ai_image_studio/features/reference/presentation/reference_page.dart';
import 'package:ai_image_studio/features/profile/presentation/profile_page.dart';
import 'package:ai_image_studio/features/camera/presentation/camera_page.dart';
import 'package:ai_image_studio/features/studio/presentation/studio_page.dart';
import 'package:ai_image_studio/app/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:typed_data';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline, size: 56),
              const SizedBox(height: 12),
              Text('找不到 ${state.uri}'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('回到首页'),
              ),
            ],
          ),
        ),
      ),
    ),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const AuthPage(mode: AuthMode.login),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const AuthPage(mode: AuthMode.register),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainShell(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/camera', builder: (_, __) => const CameraPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/studio', builder: (_, __) => const StudioPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
          ]),
        ],
      ),
      GoRoute(
          path: '/assets/upload',
          builder: (context, state) => const AssetUploadPage()),
      GoRoute(
        path: '/create/text-to-image',
        builder: (_, __) => const GeneratePage(),
      ),
      GoRoute(path: '/history', builder: (_, __) => const HistoryPage()),
      GoRoute(
        path: '/create/reference',
        builder: (context, state) =>
            ReferencePage(initialBytes: state.extra as Uint8List?),
      ),
      GoRoute(
        path: '/task/:taskId',
        builder: (context, state) =>
            TaskDetailPage(taskId: state.pathParameters['taskId']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
