import 'package:ai_image_studio/features/templates/data/template_models.dart';

/// 模板列表排序方式。
enum TemplateSort {
  recommended('推荐'),
  popular('最热'),
  name('名称'),
  favorites('收藏优先');

  const TemplateSort(this.label);
  final String label;
}

/// 灵感模板的本地筛选与排序。
///
/// 保持纯函数,方便在页面和测试里复用。
List<InspirationTemplate> filterTemplates(
  List<InspirationTemplate> source, {
  TemplateCategory? category,
  String query = '',
  TemplateSort sort = TemplateSort.recommended,
  Set<String> favorites = const {},
}) {
  final keyword = query.trim().toLowerCase();
  final filtered = source.where((template) {
    if (category != null && template.category != category) return false;
    if (keyword.isEmpty) return true;
    return templateSearchText(template).contains(keyword);
  }).toList();

  switch (sort) {
    case TemplateSort.recommended:
      break;
    case TemplateSort.popular:
      filtered.sort((a, b) {
        final byPopularity = b.popularity.compareTo(a.popularity);
        return byPopularity != 0 ? byPopularity : a.title.compareTo(b.title);
      });
      break;
    case TemplateSort.name:
      filtered.sort((a, b) => a.title.compareTo(b.title));
      break;
    case TemplateSort.favorites:
      filtered.sort((a, b) {
        final aFavorite = favorites.contains(a.id) ? 1 : 0;
        final bFavorite = favorites.contains(b.id) ? 1 : 0;
        if (aFavorite != bFavorite) return bFavorite.compareTo(aFavorite);
        return b.popularity.compareTo(a.popularity);
      });
      break;
  }
  return filtered;
}

/// 模板可被搜索的文本:标题、副标题、分类、标签和推荐风格。
String templateSearchText(InspirationTemplate template) => [
  template.title,
  template.subtitle,
  template.category.label,
  ...template.tags,
  ...template.recommendedStyles,
].join(' ').toLowerCase();
