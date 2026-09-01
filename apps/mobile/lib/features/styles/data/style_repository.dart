import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/network/api_exception.dart';
import 'package:ai_image_studio/features/styles/data/style_model.dart';
import 'package:dio/dio.dart';

class StyleRepository {
  StyleRepository(this._apiClient);
  final ApiClient _apiClient;
  Future<List<StylePreset>> list() async {
    try {
      final response =
          await _apiClient.dio.get<Map<String, dynamic>>('/styles');
      return (response.data!['styles'] as List<dynamic>)
          .map((item) => StylePreset.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
