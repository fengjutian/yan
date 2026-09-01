import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Image Studio'),
        actions: [
          IconButton(
            tooltip: '退出登录',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '开始创作',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '用文字描述画面，或使用人物参考图开启创作。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          const _CreateCard(
            icon: Icons.auto_awesome,
            title: '文生图',
            description: '输入画面描述，生成你的作品。',
          ),
          const SizedBox(height: 16),
          const _CreateCard(
            icon: Icons.person_outline,
            title: '人物参考创作',
            description: '上传人物参考图，在新场景中保持主体特征。',
          ),
        ],
      ),
    );
  }
}

class _CreateCard extends StatelessWidget {
  const _CreateCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(description),
        ),
        trailing: const Icon(Icons.arrow_forward),
      ),
    );
  }
}
