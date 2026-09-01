import 'package:ai_image_studio/features/home/presentation/home_page.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomePage(),
    ),
  ],
);

