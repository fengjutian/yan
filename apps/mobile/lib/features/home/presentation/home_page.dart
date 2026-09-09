import 'package:ai_image_studio/app/theme.dart';
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
    Future<void>.microtask(() => ref.read(authControllerProvider.notifier).refreshProfile());
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final name = user?.nickname.trim();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(children: [
              const _BrandMark(),
              const SizedBox(width: 10),
              const Expanded(child: Text('YAN STUDIO', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.8))),
              _CreditsPill(credits: user?.creditsBalance ?? 0),
            ]),
            const SizedBox(height: 36),
            Text(name == null || name.isEmpty ? '今天，想创造什么？' : '嗨，$name\n今天想创造什么？', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 10),
            Text('把灵感变成独一无二的画面。', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 28),
            _HeroCreateCard(onTap: () => context.push('/create/text-to-image')),
            const SizedBox(height: 28),
            Row(children: [
              Text('更多灵感', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              const Text('找到你的创作方式', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _InspirationCard(icon: Icons.face_retouching_natural, color: AppColors.lavender, iconColor: const Color(0xFF765AA7), title: '人物写真', description: '保留你的独特气质', onTap: () => context.push('/create/reference'))),
              const SizedBox(width: 12),
              Expanded(child: _InspirationCard(icon: Icons.collections_outlined, color: const Color(0xFFFFEEDB), iconColor: const Color(0xFFC7793B), title: '作品画廊', description: '收藏每一次心动', onTap: () => context.push('/history'))),
            ]),
            const SizedBox(height: 22),
            const _DailyTip(),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Container(
    width: 34, height: 34,
    decoration: BoxDecoration(
      color: AppColors.rose,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(color: Color(0x33D95F87), blurRadius: 14, offset: Offset(0, 6))],
    ),
    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
  );
}

class _CreditsPill extends StatelessWidget {
  const _CreditsPill({required this.credits});
  final int credits;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.line)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.brightness_5_rounded, color: Color(0xFFE6A33A), size: 16),
      const SizedBox(width: 6),
      Text('$credits', style: const TextStyle(fontWeight: FontWeight.w800)),
    ]),
  );
}

class _HeroCreateCard extends StatelessWidget {
  const _HeroCreateCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Ink(
        height: 226,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F3B2730),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(children: [
          Positioned(
            right: -24,
            top: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                color: AppColors.blush,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: 18,
            child: Transform.rotate(
              angle: -.10,
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 32,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.blush,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'AI 灵感画布',
                style: TextStyle(
                  color: AppColors.rose,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            const Text('一句话，生成\n你的想象', style: TextStyle(fontSize: 25, height: 1.2, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.rose,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('开始创作', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                SizedBox(width: 8), Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ]),
            ),
          ]),
        ]),
      ),
    ),
  );
}

class _InspirationCard extends StatelessWidget {
  const _InspirationCard({required this.icon, required this.color, required this.iconColor, required this.title, required this.description, required this.onTap});
  final IconData icon; final Color color; final Color iconColor; final String title; final String description; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: AppColors.line)),
    child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(22),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: iconColor, size: 23)),
        const SizedBox(height: 22),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text(description, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
      ])),
    ),
  );
}

class _DailyTip extends StatelessWidget {
  const _DailyTip();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
    child: const Row(children: [
      Icon(Icons.lightbulb_outline_rounded, color: AppColors.rose, size: 21),
      SizedBox(width: 12),
      Expanded(child: Text('今日灵感：试试加入「柔和光影」和「胶片质感」', style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4))),
    ]),
  );
}
