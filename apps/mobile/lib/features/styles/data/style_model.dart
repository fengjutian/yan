class StylePreset {
  const StylePreset(
      {required this.id,
      required this.slug,
      required this.name,
      required this.description});
  final String id;
  final String slug;
  final String name;
  final String description;
  factory StylePreset.fromJson(Map<String, dynamic> json) => StylePreset(
        id: json['id'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
      );
}
