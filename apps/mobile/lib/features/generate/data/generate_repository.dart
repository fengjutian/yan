import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/network/api_exception.dart';
import 'package:ai_image_studio/features/ai_settings/data/local_ai_client.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/generate/data/local_creation_store.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class GenerateRepository {
  GenerateRepository(
    this._apiClient,
    this._localAIClient, {
    this.localOnly = true,
    LocalCreationStore? localStore,
  }) : _localStore = localStore ?? LocalCreationStore();

  final ApiClient _apiClient;
  final LocalAIClient _localAIClient;
  final LocalCreationStore _localStore;
  final bool localOnly;
  static const _uuid = Uuid();

  Future<String> enhancePrompt(String prompt) async {
    try {
      return await _localAIClient.complete(prompt);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    } catch (error) {
      throw StateError(_friendlyError(error));
    }
  }

  Future<ImageTask> create({
    required String prompt,
    required String aspectRatio,
    required int count,
    required bool promptOptimizer,
  }) async {
    if (localOnly) {
      return _createLocal(
        prompt: prompt,
        aspectRatio: aspectRatio,
        count: count,
        promptOptimizer: promptOptimizer,
      );
    }
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

  Future<ImageTask> _createLocal({
    required String prompt,
    required String aspectRatio,
    required int count,
    required bool promptOptimizer,
  }) async {
    try {
      final images = await _localAIClient.textToImage(
        prompt: prompt,
        aspectRatio: aspectRatio,
        count: count,
        promptOptimizer: promptOptimizer,
      );
      return await _localStore.saveSuccess(
        prompt: prompt,
        aspectRatio: aspectRatio,
        count: count,
        type: 'TEXT_TO_IMAGE',
        images: images,
      );
    } on StateError {
      // 配置/内容策略错误不属于“已提交但失败”的任务，不写入历史。
      rethrow;
    } catch (error) {
      final message = _friendlyError(error);
      try {
        await _localStore.saveFailure(
          prompt: prompt,
          aspectRatio: aspectRatio,
          count: count,
          type: 'TEXT_TO_IMAGE',
          errorMessage: message,
        );
      } catch (_) {
        // 历史写入失败不应覆盖真正的生成错误。
      }
      throw StateError(message);
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
    if (localOnly) {
      try {
        return await _localStore.require(taskId);
      } catch (error) {
        throw StateError(_friendlyError(error));
      }
    }
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
      final tasks = await _localStore.list(limit: limit);
      return ImageTaskPage(tasks: tasks, nextCursor: '');
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
    if (localOnly) {
      throw StateError('本地生成任务完成后无法取消');
    }
    try {
      await _apiClient.dio.post<void>('/image-tasks/$taskId/cancel');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ImageTask> retry(String taskId) async {
    if (localOnly) {
      final previous = await _localStore.require(taskId);
      if (previous.status != 'FAILED' && previous.status != 'CANCELED') {
        throw StateError('当前作品不需要重试');
      }
      return create(
        prompt: previous.prompt,
        aspectRatio: previous.aspectRatio,
        count: previous.count,
        promptOptimizer: true,
      );
    }
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
      throw StateError(
        '$feature需要后端服务；独立模式暂未支持，请先在“AI 设置”中关闭本地直连',
      );
    }
  }

  String _friendlyError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return error.message;
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401) return 'API Key 无效，请检查 AI 设置';
      if (status == 429) return '请求过于频繁，请稍后重试';
      if (status == 402) return 'MiniMax 账户额度不足';
      final body = error.response?.data;
      if (body is Map) {
        final base = body['base_resp'];
        if (base is Map && base['status_msg'] != null) {
          return base['status_msg'].toString();
        }
        final apiError = body['error'];
        if (apiError is Map && apiError['message'] != null) {
          return apiError['message'].toString();
        }
      }
      return '连接 MiniMax 失败，请检查网络和 AI 设置';
    }
    final detail = error.toString().trim();
    return detail.isEmpty ? '生成失败，请稍后重试' : detail;
  }
}
