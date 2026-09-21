import 'package:ai_image_studio/features/camera/data/camera_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class StudioPage extends ConsumerWidget {
  const StudioPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captured = ref.watch(cameraSessionProvider).selected;
    return Scaffold(
      appBar: AppBar(title: const Text('工作室')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('让照片成为作品', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('导入照片，选择适合它的创作方式。', style: Theme.of(context).textTheme.bodyLarge),
        if (captured != null) ...[
          const SizedBox(height: 20),
          ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(alignment: Alignment.bottomLeft, children: [
                Image.memory(captured.bytes,
                    height: 220, width: double.infinity, fit: BoxFit.cover),
                Container(
                    margin: const EdgeInsets.all(12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(99)),
                    child: Text('相机成片 · 质量 ${captured.score.round()} 分',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12))),
              ])),
        ],
        const SizedBox(height: 26),
        _StudioCard(
            icon: Icons.auto_fix_high,
            title: 'AI 风格迁移',
            subtitle: '保留人物特征，重塑画面氛围',
            onTap: () =>
                context.push('/style-transfer', extra: captured?.bytes)),
        const SizedBox(height: 12),
        _StudioCard(
            icon: Icons.tune,
            title: '图片编辑器',
            subtitle: '裁剪/旋转/调色，本地即时处理',
            onTap: () => context.push('/editor', extra: captured?.bytes)),
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
        const SizedBox(height: 12),
        _StudioCard(
            icon: Icons.share_outlined,
            title: '分享工作台',
            subtitle: '平台裁剪 / AI 文案 / 一键分享',
            onTap: () => context.push('/share')),
      ]),
    );
  }
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
