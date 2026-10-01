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
      if (settings.canCallLocally) {
        return _callProvider(settings, prompt, systemMessage);
      }
      return _localFallback(prompt, systemMessage);
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

  String _localFallback(String prompt, String systemMessage) {
    final value = prompt.trim();
    if (systemMessage.contains('社交媒体')) {
      final subject = value.length > 18 ? value.substring(0, 18) : value;
      return '记录此刻\n$subject，光影和情绪都刚刚好。\n#随手拍 #生活记录 #今日份美好';
    }
    return '$value，主体细节清晰，自然光影，层次丰富，构图平衡，'
        '色彩协调，真实细腻质感，高质量摄影画面';
  }

  Future<String> test(AISettings settings) => _callProvider(
        settings,
        '一只在窗边晒太阳的猫',
        '请简短优化用户的图片生成提示词，只返回优化结果。',
      );

  Future<String> _callProvider(
    AISettings settings,
    String prompt,
    String systemMessage,
  ) async {
    final baseUrl = settings.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final versionPath = settings.provider == AIProvider.miniMax &&
            !baseUrl.endsWith('/v1')
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
