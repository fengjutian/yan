import 'package:ai_image_studio/core/network/api_exception.dart';
import 'package:ai_image_studio/features/ai_settings/data/local_ai_client.dart';
import 'package:ai_image_studio/features/ai_settings/presentation/ai_settings_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 复用 /prompts/enhance 生成分享文案(title + body + tags)。
/// 后端会基于图片 prompt + 风格上下文产出更贴切的文案。
class ShareController extends StateNotifier<ShareState> {
  ShareController(this._localAIClient) : super(const ShareState());

  final LocalAIClient _localAIClient;

  /// [imagePrompt] 是图片生成时的原始 prompt,作为文案的上下文。
  /// [styleName] 可选,加上能产出更准的风格调性。
  Future<void> generateCaption({
    required String imagePrompt,
    String? styleName,
  }) async {
    if (state.generating) return;
    final trimmed = imagePrompt.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(generating: true, clearError: true);
    try {
      final enhanced = await _localAIClient.complete(
        _composeShareSeed(trimmed, styleName),
        systemMessage: '你是中文社交媒体文案助手。严格按用户要求生成标题、正文和标签，不要解释。',
      );
      final caption = _splitCaption(enhanced);
      state = state.copyWith(
        generating: false,
        caption: caption.body,
        title: caption.title,
        tags: caption.tags,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        generating: false,
        errorMessage: ApiException.fromDio(e).message,
      );
    } catch (e) {
      state = state.copyWith(generating: false, errorMessage: e.toString());
    }
  }

  void setCaption(String text) =>
      state = state.copyWith(caption: text, clearError: true);

  void setTitle(String text) =>
      state = state.copyWith(title: text, clearError: true);

  void setTags(List<String> tags) => state = state.copyWith(tags: tags);

  /// 复制到剪贴板由 UI 层做(避免 share_plus 依赖剪贴板),controller 仅暴露文本。
  String exportText() {
    final tagsLine =
        state.tags.isEmpty ? '' : '\n${state.tags.map((t) => '#$t').join(' ')}';
    return '${state.title}\n${state.caption}$tagsLine';
  }

  String _composeShareSeed(String prompt, String? style) {
    final stylePrefix = style == null || style.isEmpty ? '' : '风格：$style。';
    return '$stylePrefix请基于以下画面描述,生成一段 30 字以内的标题、一段不超过 80 字的'
        '小红书/朋友圈风格分享文案,以及 3~5 个简短中文标签(用空格分隔):\n画面:$prompt';
  }

  ({String title, String body, List<String> tags}) _splitCaption(
      String enhanced) {
    // 服务端返回的 enhanced prompt 是一段连续文本,我们按行/句拆分。
    // 格式约定:\n第一行 = 标题,后面段落 = 正文,最后 #tag1 #tag2 行 = 标签。
    final lines = enhanced
        .split(RegExp(r'[\n]'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    String title = lines.isNotEmpty ? lines.first.trim() : '';
    String body = lines.length > 1 ? lines.sublist(1).join('\n').trim() : title;
    final tags = <String>[];
    final tagRegex = RegExp(r'#([\u4e00-\u9fa5A-Za-z0-9_]+)');
    for (final m in tagRegex.allMatches(body)) {
      tags.add(m.group(1)!);
      body = body.replaceFirst(m.group(0)!, '').trim();
    }
    // 容错:如果全是一段,标题取前 14 个字。
    if (title.isEmpty) {
      title = body.length > 14 ? body.substring(0, 14) : body;
      body = '';
    }
    return (title: title, body: body, tags: tags);
  }
}

@immutable
class ShareState {
  const ShareState({
    this.generating = false,
    this.title = '',
    this.caption = '',
    this.tags = const [],
    this.errorMessage,
  });

  final bool generating;
  final String title;
  final String caption;
  final List<String> tags;
  final String? errorMessage;

  ShareState copyWith({
    bool? generating,
    String? title,
    String? caption,
    List<String>? tags,
    String? errorMessage,
    bool clearError = false,
  }) =>
      ShareState(
        generating: generating ?? this.generating,
        title: title ?? this.title,
        caption: caption ?? this.caption,
        tags: tags ?? this.tags,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      );
}

final shareControllerProvider =
    StateNotifierProvider.autoDispose<ShareController, ShareState>((ref) {
  return ShareController(ref.watch(localAIClientProvider));
});

/// 收藏 + 草稿用本地 SharedPreferences 持久化,MVP 不上后端。
/// 后续可替换成 `/me/favorites` / `/me/drafts` 接口。
class LocalCollectionService {
  LocalCollectionService(this._prefs);
  final SharedPreferences _prefs;

  static const _favKey = 'favorites';
  static const _draftKey = 'drafts';

  Future<Set<String>> favorites() async =>
      (_prefs.getStringList(_favKey) ?? const <String>[]).toSet();

  Future<Set<String>> drafts() async =>
      (_prefs.getStringList(_draftKey) ?? const <String>[]).toSet();

  Future<void> toggleFavorite(String taskId) async {
    final cur = await favorites();
    if (cur.contains(taskId)) {
      cur.remove(taskId);
    } else {
      cur.add(taskId);
    }
    await _prefs.setStringList(_favKey, cur.toList());
  }

  Future<void> addDraft(String taskId) async {
    final cur = await drafts();
    cur.add(taskId);
    await _prefs.setStringList(_draftKey, cur.toList());
  }

  Future<void> removeDraft(String taskId) async {
    final cur = await drafts();
    cur.remove(taskId);
    await _prefs.setStringList(_draftKey, cur.toList());
  }
}

/// 异步初始化 SharedPreferences,挂到 provider 上。
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final localCollectionServiceProvider = Provider<LocalCollectionService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (v) => v,
        orElse: () => throw StateError(
            'sharedPreferencesProvider 还未就绪,请先 await SharedPreferences.getInstance()'),
      );
  return LocalCollectionService(prefs);
});

final favoritesProvider = FutureProvider<Set<String>>((ref) async {
  final svc = ref.watch(localCollectionServiceProvider);
  return svc.favorites();
});

final draftsProvider = FutureProvider<Set<String>>((ref) async {
  final svc = ref.watch(localCollectionServiceProvider);
  return svc.drafts();
});

/// UI helper:在用户未登录时也能用本地收藏(游客模式),登录后留接口做后端同步。
final toggleFavoriteProvider = Provider<Future<void> Function(String)>((ref) {
  return (taskId) async {
    final svc = ref.read(localCollectionServiceProvider);
    await svc.toggleFavorite(taskId);
    ref.invalidate(favoritesProvider);
  };
});

final toggleDraftProvider =
    Provider<Future<void> Function(String, bool)>((ref) {
  return (taskId, add) async {
    final svc = ref.read(localCollectionServiceProvider);
    if (add) {
      await svc.addDraft(taskId);
    } else {
      await svc.removeDraft(taskId);
    }
    ref.invalidate(draftsProvider);
  };
});

/// 占位导出,避免 IDE 提示 Uint8List 未使用。后续真要做字节级渲染时会用到。
@visibleForTesting
Object placeholderBytes() => Object();
