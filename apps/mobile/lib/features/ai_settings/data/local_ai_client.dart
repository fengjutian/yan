import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_image_studio/features/ai_settings/data/ai_settings_repository.dart';
import 'package:dio/dio.dart';

class LocalAIClient {
  LocalAIClient(this._settings, this._backend, {Dio? directClient})
    : _direct = directClient ?? Dio();

  static const promptSystemMessage =
      '你是专业的 AI 绘画提示词编辑。依据用户原意补充主体细节、环境、光线、构图、色彩和材质。'
      '不要改变主体，不要解释，不要使用标题或 Markdown，只输出一段可直接用于图片生成的中文提示词，控制在 80 到 120 字。';

  final AISettingsStore _settings;
  final Dio _backend;
  final Dio _direct;

  Future<String> complete(
    String prompt, {
    String systemMessage = promptSystemMessage,
  }) async {
    final settings = await _settings.load();
    if (settings.preferLocal) {
      if (!settings.canCallLocally) {
        throw StateError('请先在 AI 设置中配置并启用 MiniMax/DeepSeek API Key');
      }
      return _callProvider(settings, prompt, systemMessage);
    }
    final response = await _backend.post<Map<String, dynamic>>(
      '/prompts/enhance',
      data: {'prompt': prompt},
    );
    final result = response.data?['prompt'];
    if (result is! String || result.trim().isEmpty) {
      throw const FormatException('AI 返回内容为空');
    }
    return result.trim();
  }

  Future<String> test(AISettings settings) =>
      _callProvider(settings, '一只在窗边晒太阳的猫', '请简短优化用户的图片生成提示词，只返回优化结果。');

  /// 独立 App 的文生图入口：用户自带 MiniMax Key，客户端直连。
  Future<List<Uint8List>> textToImage({
    required String prompt,
    required String aspectRatio,
    required int count,
    bool promptOptimizer = true,
  }) async {
    if (prompt.trim().isEmpty) {
      throw const FormatException('请输入画面描述');
    }
    if (count < 1 || count > 4) {
      throw const FormatException('生成数量需在 1 到 4 之间');
    }
    final settings = await _settings.load();
    return _generateImages(
      settings: settings,
      prompt: prompt.trim(),
      aspectRatio: aspectRatio,
      count: count,
      promptOptimizer: promptOptimizer,
    );
  }

  Future<Uint8List> styleTransfer({
    required Uint8List sourceBytes,
    required String prompt,
    required String aspectRatio,
  }) async {
    final settings = await _settings.load();
    final images = await _generateImages(
      settings: settings,
      prompt: prompt,
      aspectRatio: aspectRatio,
      count: 1,
      promptOptimizer: true,
      sourceBytes: sourceBytes,
    );
    if (images.isEmpty) {
      throw const FormatException('MiniMax 未返回生成图片');
    }
    return images.first;
  }

  Future<List<Uint8List>> _generateImages({
    required AISettings settings,
    required String prompt,
    required String aspectRatio,
    required int count,
    required bool promptOptimizer,
    Uint8List? sourceBytes,
  }) async {
    _requireMiniMax(settings);
    final baseUrl = settings.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final versionPath = baseUrl.endsWith('/v1') ? '' : '/v1';
    final payload = <String, dynamic>{
      'model': 'image-01',
      'prompt': prompt,
      'response_format': 'base64',
      'n': count,
      'prompt_optimizer': promptOptimizer,
      'aspect_ratio': aspectRatio,
      // AI 生成内容标识不可关闭；商店合规要求见 profile 隐私说明。
      'aigc_watermark': true,
    };
    if (sourceBytes != null) {
      payload['subject_reference'] = [
        {
          'type': 'character',
          'image_file':
              'data:${_mimeType(sourceBytes)};base64,${base64Encode(sourceBytes)}',
        },
      ];
    }

    final response = await _direct.post<Map<String, dynamic>>(
      '$baseUrl$versionPath/image_generation',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${settings.apiKey.trim()}',
          'Content-Type': 'application/json',
        },
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 3),
      ),
      data: payload,
    );
    final baseResponse = response.data?['base_resp'];
    if (baseResponse is Map && baseResponse['status_code'] != 0) {
      throw StateError(baseResponse['status_msg']?.toString() ?? '图片生成失败');
    }
    final data = response.data?['data'];
    final images = data is Map ? data['image_base64'] : null;
    if (images is! List || images.isEmpty) {
      throw const FormatException('MiniMax 未返回生成图片');
    }
    final result = <Uint8List>[];
    for (final item in images) {
      if (item is! String || item.isEmpty) continue;
      var encoded = item;
      if (encoded.startsWith('data:')) {
        final comma = encoded.indexOf(',');
        if (comma < 0) continue;
        encoded = encoded.substring(comma + 1);
      }
      result.add(base64Decode(encoded));
    }
    if (result.isEmpty) {
      throw const FormatException('MiniMax 未返回有效图片');
    }
    return result;
  }

  void _requireMiniMax(AISettings settings) {
    if (!settings.enabled || settings.apiKey.trim().isEmpty) {
      throw StateError('请先在 AI 设置中启用 MiniMax 并填写 API Key');
    }
    if (settings.provider != AIProvider.miniMax) {
      throw StateError('DeepSeek 暂不支持图片生成，请切换到 MiniMax');
    }
  }

  String _mimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  Future<String> _callProvider(
    AISettings settings,
    String prompt,
    String systemMessage,
  ) async {
    final baseUrl = settings.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final versionPath =
        settings.provider == AIProvider.miniMax && !baseUrl.endsWith('/v1')
        ? '/v1'
        : '';
    final response = await _direct.post<Map<String, dynamic>>(
      '$baseUrl$versionPath/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${settings.apiKey.trim()}',
          'Content-Type': 'application/json',
        },
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
      data: {
        'model': settings.model.trim(),
        'messages': [
          {'role': 'system', 'content': systemMessage},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.7,
        'max_completion_tokens': 500,
      },
    );
    final choices = response.data?['choices'];
    if (choices is! List || choices.isEmpty) {
      throw FormatException('${settings.provider.label} 返回格式无效');
    }
    final message = choices.first['message'];
    var content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw FormatException('${settings.provider.label} 返回内容为空');
    }
    content = content.trim();
    final thinkEnd = content.lastIndexOf('</think>');
    return thinkEnd >= 0
        ? content.substring(thinkEnd + '</think>'.length).trim()
        : content;
  }
}
