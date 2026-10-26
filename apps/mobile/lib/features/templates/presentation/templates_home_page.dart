import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/templates/data/template_models.dart';
import 'package:ai_image_studio/features/templates/presentation/template_filters.dart';
import 'package:ai_image_studio/features/templates/presentation/templates_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 灵感模板页:搜索 + 分类 + 排序 + 收藏,全部在本地即时完成。
class TemplatesHomePage extends ConsumerStatefulWidget {
  const TemplatesHomePage({this.focusSearch = false, super.key});

  /// 从首页搜索入口进入时直接聚焦搜索框。
  final bool focusSearch;

  @override
  ConsumerState<TemplatesHomePage> createState() => _TemplatesHomePageState();
}

class _TemplatesHomePageState extends ConsumerState<TemplatesHomePage> {
  final _searchController = TextEditingController();
  TemplateCategory? _category;
  TemplateSort _sort = TemplateSort.recommended;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(allTemplatesProvider);
    ref.invalidate(featuredTemplatesProvider);
    try {
      await ref.read(allTemplatesProvider.future);
    } catch (_) {
      // 错误由页面状态展示，下拉动作本身不再向上抛出。
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _showFavoritesSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: .72,
        child: _FavoritesSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allTemplatesProvider);
    final featured = ref.watch(featuredTemplatesProvider);
    final favorites = ref.watch(templateFavoritesProvider);
    final templates = all.valueOrNull ?? const <InspirationTemplate>[];
    final filtered = filterTemplates(
      templates,
      category: _category,
      query: _query,
      sort: _sort,
      favorites: favorites,
    );
    final searching = _query.trim().isNotEmpty;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('灵感模板'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          Badge.count(
            count: favorites.length,
            isLabelVisible: favorites.isNotEmpty,
            child: IconButton(
              tooltip: '我的收藏',
              icon: const Icon(Icons.bookmark_border),
              onPressed: _showFavoritesSheet,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: TextField(
                controller: _searchController,
                autofocus: widget.focusSearch,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '搜场景、风格或模板',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ),
            if (!searching)
              featured.when(
                data: (items) => _FeaturedBanner(
                  items: items,
                  onOpen: (item) => context.push('/templates/${item.id}'),
                ),
                loading: () => const _BannerSkeleton(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            const SizedBox(height: 14),
            _CategoryChips(
              current: _category,
              onChanged: (category) => setState(() => _category = category),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    searching
                        ? '找到 ${filtered.length} 个模板'
                        : '共 ${filtered.length} 个模板',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  _SortMenu(
                    sort: _sort,
                    onSelected: (sort) => setState(() => _sort = sort),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (all.isLoading && templates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (all.hasError && templates.isEmpty)
              _LoadError(onRetry: _refresh)
            else if (filtered.isEmpty)
              _EmptyResults(searching: searching, onClear: _clearSearch)
            else
              _TemplateGrid(
                items: filtered,
                favorites: favorites,
                onToggleFavorite: (id) async {
                  await ref.read(templateFavoritesProvider.notifier).toggle(id);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedBanner extends StatelessWidget {
  const _FeaturedBanner({required this.items, required this.onOpen});

  final List<InspirationTemplate> items;
  final ValueChanged<InspirationTemplate> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text('本周精选', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              const Text(
                '按热度排序',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _FeaturedCard(
              item: items[index],
              onTap: () => onOpen(items[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.item, required this.onTap});

  final InspirationTemplate item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: 272,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [item.coverColor, _mix(item.coverColor, Colors.white, .32)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                item.category.label,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xCC292725),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 14,
                  color: Colors.deepOrange,
                ),
                const SizedBox(width: 4),
                Text(
                  '${item.popularity}',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.ink,
                  size: 18,
                ),
              ],
            ),
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
    height: 210,
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
      height: 46,
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
          for (final category in TemplateCategory.values) ...[
            ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(category.icon, size: 14),
                  const SizedBox(width: 4),
                  Text(category.label),
                ],
              ),
              selected: current == category,
              onSelected: (_) => onChanged(category),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onSelected});

  final TemplateSort sort;
  final ValueChanged<TemplateSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<TemplateSort>(
      initialValue: sort,
      onSelected: onSelected,
      tooltip: '排序方式',
      itemBuilder: (context) => [
        for (final option in TemplateSort.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(
                  option == sort ? Icons.check_rounded : Icons.circle_outlined,
                  size: 16,
                  color: option == sort
                      ? AppColors.rose
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(option.label),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 15, color: scheme.onSurface),
            const SizedBox(width: 4),
            Text(
              sort.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
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
          childAspectRatio: 0.78,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => _TemplateCard(
          item: items[index],
          isFavorite: favorites.contains(items[index].id),
          onToggleFavorite: () => onToggleFavorite(items[index].id),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/templates/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 112,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    item.coverColor,
                    _mix(item.coverColor, Colors.white, .5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      item.category.icon,
                      size: 36,
                      color: Colors.black54,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.white.withValues(alpha: .72),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: isFavorite ? '取消收藏' : '收藏模板',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border,
                          color: isFavorite ? Colors.redAccent : AppColors.ink,
                        ),
                        onPressed: onToggleFavorite,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .42),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            size: 11,
                            color: Colors.orangeAccent,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${item.popularity}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.searching, required this.onClear});

  final bool searching;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 44, 20, 44),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.photo_library_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            searching ? '没有找到匹配的模板' : '该分类暂无模板',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            searching ? '换个关键词，或清空搜索看看全部模板。' : '试试其他分类吧。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (searching) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onClear, child: const Text('清空搜索')),
          ],
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 10),
          const Text('模板加载失败'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}

class _FavoritesSheet extends ConsumerWidget {
  const _FavoritesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allTemplatesProvider);
    final favorites = ref.watch(templateFavoritesProvider);
    final templates = (all.valueOrNull ?? const <InspirationTemplate>[])
        .where((template) => favorites.contains(template.id))
        .toList();
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('我的收藏', style: theme.textTheme.titleLarge),
                const SizedBox(width: 8),
                Text(
                  '${favorites.length}',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (all.isLoading && templates.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (templates.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bookmark_border_rounded,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      const Text('还没有收藏的模板'),
                      const SizedBox(height: 4),
                      Text(
                        '看到喜欢的模板，点 ♡ 收藏到这里。',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('去逛逛'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: templates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    return Material(
                      color: theme.colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          final router = GoRouter.of(context);
                          Navigator.pop(context);
                          router.push('/templates/${template.id}');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: LinearGradient(
                                    colors: [
                                      template.coverColor,
                                      _mix(
                                        template.coverColor,
                                        Colors.white,
                                        .5,
                                      ),
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  template.category.icon,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      template.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      template.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '取消收藏',
                                icon: const Icon(
                                  Icons.favorite_rounded,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => ref
                                    .read(templateFavoritesProvider.notifier)
                                    .toggle(template.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;
