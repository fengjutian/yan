import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/network/api_exception.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/ai_settings/data/local_ai_client.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class GenerateRepository {
  GenerateRepository(
    this._apiClient,
    this._localAIClient, {
    this.localOnly = true,
  });
  final ApiClient _apiClient;
  final LocalAIClient _localAIClient;
  final bool localOnly;
  static const _uuid = Uuid();

  Future<String> enhancePrompt(String prompt) async {
    try {
      return await _localAIClient.complete(prompt);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ImageTask> create({
    required String prompt,
    required String aspectRatio,
    required int count,
    required bool promptOptimizer,
  }) async {
    _requireBackend('AI 图像生成');
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/image-tasks',
        options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
        data: {
          'type': 'TEXT_TO_IMAGE',
          'prompt': prompt,
          'aspect_ratio': aspectRatio,
          'count': count,
          'prompt_optimizer': promptOptimizer,
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
    _requireBackend('人物参考生成');
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
    _requireBackend('任务查询');
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/image-tasks/$taskId',
      );
      return ImageTask.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ImageTaskPage> list({String cursor = '', int limit = 20}) async {
    if (localOnly) {
      return const ImageTaskPage(tasks: [], nextCursor: '');
    }
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
        tasks: ((body['tasks'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImageTask.fromJson)
            .toList(),
        nextCursor: (body['next_cursor'] as String?) ?? '',
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> cancel(String taskId) async {
    _requireBackend('取消任务');
    try {
      await _apiClient.dio.post<void>('/image-tasks/$taskId/cancel');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ImageTask> retry(String taskId) async {
    _requireBackend('重试任务');
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/image-tasks/$taskId/retry',
        options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
      );
      return ImageTask.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  void _requireBackend(String feature) {
    if (localOnly) {
      throw StateError('$feature需要后端服务，请在「我的」中关闭“优先本地运行”');
    }
  }
}
