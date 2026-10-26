import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/core/widgets/creation_image.dart';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/history/presentation/creation_display.dart';
import 'package:ai_image_studio/features/history/presentation/recent_creations_controller.dart';
import 'package:ai_image_studio/features/styles/presentation/styles_controller.dart';
import 'package:ai_image_studio/features/templates/presentation/templates_controller.dart';
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
    final name = user?.nickname.trim();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              children: [
                const _BrandMark(),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'YAN STUDIO',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                    ),
                  ),
                ),
                _CreditsPill(credits: user?.creditsBalance ?? 0),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              name == null || name.isEmpty ? '今天，想创造什么？' : '嗨，$name\n今天想创造什么？',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            Text('把灵感变成独一无二的画面。', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 20),
            _SearchEntry(onTap: () => context.push('/templates?focus=search')),
            const SizedBox(height: 24),
            _HeroCreateCard(onTap: () => context.go('/camera')),
            const SizedBox(height: 26),
            const _RecentCreationsSection(),
            const _PopularStylesSection(),
            Row(
              children: [
                Text('更多灵感', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push('/templates'),
                  child: const Text('查看全部 →'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FeaturedPreviewStrip(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _InspirationCard(
                    icon: Icons.face_retouching_natural,
                    color: AppColors.lavender,
                    iconColor: const Color(0xFF667065),
                    title: '人物写真',
                    description: '保留你的独特气质',
                    onTap: () => context.push('/create/reference'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InspirationCard(
                    icon: Icons.collections_outlined,
                    color: const Color(0xFFFFEEDB),
                    iconColor: const Color(0xFFC7793B),
                    title: '作品画廊',
                    description: '收藏每一次心动',
                    onTap: () => context.push('/history'),
                  ),
                ),
              ],
            ),
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
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x247B5152),
          blurRadius: 14,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: ClipOval(
      child: Image.asset(
        'assets/branding/yan-logo.png',
        fit: BoxFit.cover,
        semanticLabel: '颜 Studio Logo',
      ),
    ),
  );
}

class _CreditsPill extends StatelessWidget {
  const _CreditsPill({required this.credits});
  final int credits;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.brightness_5_rounded,
          color: Color(0xFFE6A33A),
          size: 16,
        ),
        const SizedBox(width: 6),
        Text('$credits', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
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
        child: Stack(
          children: [
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.blush,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    '今日拍摄灵感',
                    style: TextStyle(
                      color: AppColors.rose,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  '今天，也值得\n被好好记录',
                  style: TextStyle(
                    fontSize: 25,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '开始拍摄',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _InspirationCard extends StatelessWidget {
  const _InspirationCard({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: AppColors.line),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: iconColor, size: 23),
            ),
            const SizedBox(height: 22),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 21,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '搜场景、风格或模板',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.blush,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '搜索',
                  style: TextStyle(
                    color: AppColors.rose,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 最近创作:只在本机有作品时出现,避免新用户首页首屏过空或过长。
class _RecentCreationsSection extends ConsumerWidget {
  const _RecentCreationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentCreationsProvider);
    return recent.maybeWhen(
      data: (tasks) {
        if (tasks.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('最近创作', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.push('/history'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('全部作品 →'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 142,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) =>
                      _RecentCreationCard(task: tasks[index]),
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _RecentCreationCard extends StatelessWidget {
  const _RecentCreationCard({required this.task});
  final ImageTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = task.images.isEmpty ? null : task.images.first;
    return SizedBox(
      width: 108,
      child: InkWell(
        onTap: () => context.push('/task/${task.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 104,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: image == null
                  ? const Center(
                      child: Icon(Icons.image_not_supported_outlined),
                    )
                  : CreationImage(image: image, preferThumbnail: true),
            ),
            const SizedBox(height: 6),
            Text(
              creationTypeLabel(task.type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              creationTimeLabel(task.createdAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 热门风格:点一下直接带着风格进入迁移页,再由迁移页选照片。
class _PopularStylesSection extends ConsumerWidget {
  const _PopularStylesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final styles = ref.watch(stylesProvider);
    return styles.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('热门风格', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  const Text(
                    '点一下直接试',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final style = items[index];
                    return _StyleCard(
                      index: index,
                      name: style.name,
                      description: style.description,
                      onTap: () => context.push(
                        '/style-transfer?style=${Uri.encodeQueryComponent(style.id)}',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.index,
    required this.name,
    required this.description,
    required this.onTap,
  });

  final int index;
  final String name;
  final String description;
  final VoidCallback onTap;

  static const _gradients = <List<Color>>[
    [Color(0xFFDCE9E2), Color(0xFFA8C7BA)],
    [Color(0xFFF3E0CE), Color(0xFFD8B08C)],
    [Color(0xFFD9DEEA), Color(0xFFA7B6CE)],
    [Color(0xFFEADFE6), Color(0xFFC9AFC0)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[index % _gradients.length];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 172,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 17,
                  color: Color(0xAA292725),
                ),
                const Spacer(),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xCC292725),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyTip extends ConsumerWidget {
  const _DailyTip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(featuredTemplatesProvider).valueOrNull;
    String tip = '试试加入「柔和光影」和「胶片质感」';
    if (featured != null && featured.isNotEmpty) {
      final day = DateTime.now().difference(DateTime(2024)).inDays;
      tip = featured[day % featured.length].standingTip;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white70,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            color: AppColors.rose,
            size: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '今日灵感：$tip',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// HomePage 内嵌的"精选模板"横滑条(用 featured 仓储,空时占位)。
class _FeaturedPreviewStrip extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(featuredTemplatesProvider);
    return SizedBox(
      height: 140,
      child: featured.when(
        data: (items) => ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final t = items[i];
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => context.push('/templates/${t.id}'),
              child: Container(
                width: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      t.coverColor,
                      Color.lerp(t.coverColor, Colors.white, .5)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(t.category.icon, size: 22, color: Colors.black54),
                    const Spacer(),
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      t.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }
}
