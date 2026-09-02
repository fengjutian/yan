import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(authControllerProvider.notifier).refreshProfile(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Image Studio'),
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
          if (user != null) ...[
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(user.nickname),
                subtitle: Text(user.email),
                trailing: Chip(label: Text('${user.creditsBalance} 积分')),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _CreateCard(
            icon: Icons.auto_awesome,
            title: '文生图',
            description: '输入画面描述，生成你的作品。',
            onTap: () => context.push('/create/text-to-image'),
          ),
          const SizedBox(height: 16),
          _CreateCard(
            icon: Icons.person_outline,
            title: '人物参考创作',
            description: '上传人物参考图，在新场景中保持主体特征。',
            onTap: () => context.push('/create/reference'),
          ),
          const SizedBox(height: 16),
          _CreateCard(
            icon: Icons.photo_library_outlined,
            title: '我的作品',
            description: '查看已经完成的 AI 图片作品。',
            onTap: () => context.push('/history'),
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
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
