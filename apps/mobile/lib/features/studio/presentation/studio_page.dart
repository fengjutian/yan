import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StudioPage extends StatelessWidget {
  const StudioPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('工作室')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text('让照片成为作品', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('导入照片，选择适合它的创作方式。',
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 26),
          _StudioCard(
              icon: Icons.auto_fix_high,
              title: 'AI 风格迁移',
              subtitle: '保留人物特征，重塑画面氛围',
              onTap: () => context.push('/create/reference')),
          const SizedBox(height: 12),
          _StudioCard(
              icon: Icons.add_photo_alternate_outlined,
              title: '导入照片',
              subtitle: '上传原图并开始编辑',
              onTap: () => context.push('/assets/upload')),
          const SizedBox(height: 12),
          _StudioCard(
              icon: Icons.draw_outlined,
              title: 'AI 图像创作',
              subtitle: '用一句话创造全新画面',
              onTap: () => context.push('/create/text-to-image')),
          const SizedBox(height: 12),
          _StudioCard(
              icon: Icons.collections_outlined,
              title: '我的作品',
              subtitle: '查看成片与历史版本',
              onTap: () => context.push('/history')),
        ]),
      );
}

class _StudioCard extends StatelessWidget {
  const _StudioCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                        color: const Color(0xFFF1E8E1),
                        borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, color: const Color(0xFF7B5152))),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodyMedium)
                    ])),
                const Icon(Icons.arrow_forward_rounded)
              ]))));
}
