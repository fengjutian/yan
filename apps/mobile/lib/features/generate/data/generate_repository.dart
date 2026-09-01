import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/network/api_exception.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class GenerateRepository {
  GenerateRepository(this._apiClient);
  final ApiClient _apiClient;
  static const _uuid = Uuid();

  Future<ImageTask> create(
      {required String prompt,
      required String aspectRatio,
      required int count,
      required bool promptOptimizer}) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/image-tasks',
        options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
        data: {
          'type': 'TEXT_TO_IMAGE',
          'prompt': prompt,
          'aspect_ratio': aspectRatio,
          'count': count,
          'prompt_optimizer': promptOptimizer
        },
      );
      return ImageTask.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ImageTask> createCharacterReference({
    required String prompt,
    required String sourceAssetId,
    required String styleId,
    required String aspectRatio,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/image-tasks',
        options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
        data: {
          'type': 'CHARACTER_REFERENCE',
          'prompt': prompt,
          'source_asset_id': sourceAssetId,
          'style_id': styleId,
          'aspect_ratio': aspectRatio,
          'count': 1,
          'prompt_optimizer': true,
        },
      );
      return ImageTask.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ImageTask> get(String taskId) async {
    try {
      final response = await _apiClient.dio
          .get<Map<String, dynamic>>('/image-tasks/$taskId');
      return ImageTask.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ImageTaskPage> list({String cursor = '', int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/image-tasks',
        queryParameters: {
          'status': 'SUCCEEDED',
          'limit': limit,
          if (cursor.isNotEmpty) 'cursor': cursor,
        },
      );
      final body = response.data!;
      return ImageTaskPage(
        tasks: (body['tasks'] as List<dynamic>)
            .map((item) => ImageTask.fromJson(item as Map<String, dynamic>))
            .toList(),
        nextCursor: body['next_cursor'] as String? ?? '',
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
