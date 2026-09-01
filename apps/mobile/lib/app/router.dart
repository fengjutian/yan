import 'package:ai_image_studio/features/auth/presentation/auth_page.dart';
import 'package:ai_image_studio/features/auth/presentation/splash_page.dart';
import 'package:ai_image_studio/features/assets/presentation/asset_upload_page.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_page.dart';
import 'package:ai_image_studio/features/home/presentation/home_page.dart';
import 'package:ai_image_studio/features/reference/presentation/reference_page.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
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
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
        path: '/assets/upload',
        builder: (context, state) => const AssetUploadPage()),
    GoRoute(
      path: '/create/text-to-image',
      builder: (context, state) => const GeneratePage(),
    ),
    GoRoute(
      path: '/create/reference',
      builder: (context, state) => const ReferencePage(),
    ),
  ],
);
