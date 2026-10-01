import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/network/api_exception.dart';
import 'package:ai_image_studio/features/styles/data/style_model.dart';
import 'package:dio/dio.dart';

class StyleRepository {
  StyleRepository(this._apiClient, {this.localOnly = true});
  final ApiClient _apiClient;
  final bool localOnly;

  static const localPresets = <StylePreset>[
    StylePreset(
      id: 'local-natural',
      slug: 'natural',
      name: '自然人像',
      description: '保留真实肤色与自然光影',
    ),
    StylePreset(
      id: 'local-film',
      slug: 'film',
      name: '柔和胶片',
      description: '低饱和暖调与细腻颗粒',
    ),
    StylePreset(
      id: 'local-cinematic',
      slug: 'cinematic',
      name: '电影质感',
      description: '增强明暗层次与氛围色彩',
    ),
    StylePreset(
      id: 'local-clean',
      slug: 'clean',
      name: '清透日系',
      description: '明亮干净的轻盈色调',
    ),
  ];

  Future<List<StylePreset>> list() async {
    if (localOnly) return localPresets;
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/styles',
      );
      return ((response.data!['styles'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StylePreset.fromJson)
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
