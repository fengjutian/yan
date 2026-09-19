import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:ai_image_studio/features/templates/presentation/templates_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 灵感模板首页:顶部 banner + 分类 tab + 横滑卡片 + 收藏分组。
class TemplatesHomePage extends ConsumerStatefulWidget {
  const TemplatesHomePage({super.key});
  @override
  ConsumerState<TemplatesHomePage> createState() => _TemplatesHomePageState();
}

class _TemplatesHomePageState extends ConsumerState<TemplatesHomePage> {
  TemplateCategory? _category;

  @override
  Widget build(BuildContext context) {
    final featured = ref.watch(featuredTemplatesProvider);
    final list = ref.watch(templateByCategoryProvider(_category));
    final favorites = ref.watch(templateFavoritesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('灵感模板'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            tooltip: '我的收藏',
            icon: const Icon(Icons.bookmark_border),
            onPressed: () => _showFavoritesSheet(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(featuredTemplatesProvider);
          ref.invalidate(templateByCategoryProvider(_category));
          await ref.read(featuredTemplatesProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            featured.when(
              data: (items) => _FeaturedBanner(items: items),
              loading: () => const _BannerSkeleton(),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text('加载失败:$e'),
              ),
            ),
            const SizedBox(height: 16),
            _CategoryChips(
              current: _category,
              onChanged: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: 12),
            list.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('该分类暂无模板')),
                  );
                }
                return _TemplateGrid(
                  items: items,
                  favorites: favorites,
                  onToggleFavorite: (id) async {
                    await ref
                        .read(templateFavoritesProvider.notifier)
                        .toggle(id);
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text('加载失败:$e'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showFavoritesSheet(BuildContext context) {
    final favorites = ref.watch(templateFavoritesProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _FavoritesSheet(favorites: favorites),
    );
  }
}

class _FeaturedBanner extends StatelessWidget {
  const _FeaturedBanner({required this.items});
  final List<InspirationTemplate> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            Text('本周精选', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            const Text('按热度排序',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _FeaturedCard(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.item});
  final InspirationTemplate item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => context.push('/templates/${item.id}'),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [item.coverColor, _mix(item.coverColor, Colors.white, .3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(item.category.label,
                  style: const TextStyle(fontSize: 11)),
            ),
            const Spacer(),
            Text(item.title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.local_fire_department,
                  size: 14, color: Colors.deepOrange),
              const SizedBox(width: 4),
              Text('${item.popularity}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
              const Spacer(),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ]),
          ],
        ),
      ),
    );
  }
}

class _BannerSkeleton extends StatelessWidget {
  const _BannerSkeleton();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.current, required this.onChanged});
  final TemplateCategory? current;
  final ValueChanged<TemplateCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          ChoiceChip(
            label: const Text('全部'),
            selected: current == null,
            onSelected: (_) => onChanged(null),
          ),
          const SizedBox(width: 8),
          for (final c in TemplateCategory.values) ...[
            ChoiceChip(
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(c.icon, size: 14),
                const SizedBox(width: 4),
                Text(c.label),
              ]),
              selected: current == c,
              onSelected: (_) => onChanged(c),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({
    required this.items,
    required this.favorites,
    required this.onToggleFavorite,
  });
  final List<InspirationTemplate> items;
  final Set<String> favorites;
  final Future<void> Function(String) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _TemplateCard(
          item: items[i],
          isFavorite: favorites.contains(items[i].id),
          onToggleFavorite: () => onToggleFavorite(items[i].id),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.item,
    required this.isFavorite,
    required this.onToggleFavorite,
  });
  final InspirationTemplate item;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/templates/${item.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模拟封面:渐变 + icon
            Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    item.coverColor,
                    _mix(item.coverColor, Colors.white, .5)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20)),
              ),
              child: Stack(children: [
                Center(child: Icon(item.category.icon, size: 36, color: Colors.black54)),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.redAccent : Colors.black54,
                    ),
                    onPressed: onToggleFavorite,
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesSheet extends ConsumerWidget {
  const _FavoritesSheet({required this.favorites});
  final Set<String> favorites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('我的收藏 (${favorites.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (favorites.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('还没有收藏的模板')),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in favorites)
                    FutureBuilder<InspirationTemplate?>(
                      future: ref.read(templateByIdProvider(id).future),
                      builder: (context, snap) {
                        final t = snap.data;
                        if (t == null) return const SizedBox.shrink();
                        return InputChip(
                          avatar: Icon(t.category.icon, size: 14),
                          label: Text(t.title),
                          onPressed: () {
                            Navigator.pop(context);
                            context.push('/templates/${t.id}');
                          },
                          onDeleted: () async {
                            await ref
                                .read(templateFavoritesProvider.notifier)
                                .toggle(id);
                          },
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;