import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_page.dart';
import 'package:ai_image_studio/features/auth/presentation/splash_page.dart';
import 'package:ai_image_studio/features/assets/presentation/asset_upload_page.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_page.dart';
import 'package:ai_image_studio/features/home/presentation/home_page.dart';
import 'package:ai_image_studio/features/history/presentation/history_page.dart';
import 'package:ai_image_studio/features/history/presentation/task_detail_page.dart';
import 'package:ai_image_studio/features/reference/presentation/reference_page.dart';
import 'package:ai_image_studio/features/profile/presentation/profile_page.dart';
import 'package:ai_image_studio/app/main_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(
    authControllerProvider.select(
      (state) => (initialized: state.initialized, userId: state.user?.id),
    ),
  );

  final router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isAuthRoute = location == '/login' || location == '/register';

      if (!session.initialized) {
        return location == '/splash' ? null : '/splash';
      }
      if (session.userId == null) {
        return isAuthRoute ? null : '/login';
      }
      if (isAuthRoute || location == '/splash') return '/home';
      return null;
    },
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
            GoRoute(
              path: '/create/text-to-image',
              builder: (_, __) => const GeneratePage(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/history', builder: (_, __) => const HistoryPage()),
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
        path: '/create/reference',
        builder: (context, state) => const ReferencePage(),
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
