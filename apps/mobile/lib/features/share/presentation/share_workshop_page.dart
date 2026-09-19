import 'dart:io';
import 'dart:typed_data';

import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/history/presentation/history_controller.dart';
import 'package:ai_image_studio/features/share/data/share_models.dart';
import 'package:ai_image_studio/features/share/presentation/share_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

/// 分享工作台:
/// 1. 加载作品图片(从 /task/:taskId 走 FutureProvider,或从参数直接传入)
/// 2. 选择平台尺寸(原始 / 1:1 / 3:4 / 4:5 / 9:16)
/// 3. 选择水印位置 + 元数据开关
/// 4. AI 生成标题/正文/标签(走 /prompts/enhance)
/// 5. 保存到相册 + 系统分享
class ShareWorkshopPage extends ConsumerStatefulWidget {
  const ShareWorkshopPage({this.taskId, super.key});
  final String? taskId;

  @override
  ConsumerState<ShareWorkshopPage> createState() => _ShareWorkshopPageState();
}

class _ShareWorkshopPageState extends ConsumerState<ShareWorkshopPage> {
  String? _imageUrl;
  String? _imagePrompt;
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFromTask();
  }

  Future<void> _loadFromTask() async {
    final id = widget.taskId;
    if (id == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final task = await ref.read(taskDetailProvider(id).future);
      if (!mounted) return;
      final url = task.images.isNotEmpty ? task.images.first.url : null;
      setState(() {
        _imageUrl = url;
        _imagePrompt = task.prompt;
        _loaded = true;
      });
      // 进入页面时自动起一份 AI 文案。
      if (url != null && task.prompt.isNotEmpty) {
        ref.read(shareControllerProvider.notifier).generateCaption(
              imagePrompt: task.prompt,
            );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载作品失败：${e.toString()}';
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final url = _imageUrl;
    if (url == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('分享')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_not_supported_outlined, size: 56),
                const SizedBox(height: 12),
                Text(_error ?? '当前没有可分享的图片'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final shareState = ref.watch(shareControllerProvider);
    final controller = ref.read(shareControllerProvider.notifier);
    final config = ref.watch(shareConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('分享工作台'),
        actions: [
          IconButton(
            tooltip: '重新生成文案',
            onPressed: _imagePrompt == null || shareState.generating
                ? null
                : () => controller.generateCaption(imagePrompt: _imagePrompt!),
            icon: shareState.generating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PreviewCanvas(imageUrl: url, config: config),
          const SizedBox(height: 16),
          _PlatformPicker(
            current: config.platform,
            onChanged: (p) => ref.read(shareConfigProvider.notifier).state =
                config.copyWith(platform: p),
          ),
          const SizedBox(height: 12),
          _WatermarkPicker(
            current: config.watermark,
            onChanged: (w) => ref.read(shareConfigProvider.notifier).state =
                config.copyWith(watermark: w),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('保留位置/设备信息'),
            subtitle: const Text('关闭后将剥离 EXIF 中的敏感元数据'),
            value: config.showMetadata,
            onChanged: (v) => ref.read(shareConfigProvider.notifier).state =
                config.copyWith(showMetadata: v),
          ),
          const Divider(height: 32),
          Text('AI 文案', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (shareState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(shareState.errorMessage!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
          TextField(
            controller: TextEditingController(text: shareState.title)
              ..selection = TextSelection.collapsed(offset: shareState.title.length),
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => state_set_title(ref, v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: shareState.caption)
              ..selection = TextSelection.collapsed(offset: shareState.caption.length),
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '正文',
              border: OutlineInputBorder(),
            ),
            onChanged: controller.setCaption,
          ),
          const SizedBox(height: 8),
          _TagsEditor(
            tags: shareState.tags,
            onChanged: controller.setTags,
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _copyText(context),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制文案'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _saveToGallery(context),
                icon: const Icon(Icons.download_outlined),
                label: const Text('保存到相册'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _systemShare(context),
            icon: const Icon(Icons.share),
            label: const Text('调起系统分享'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void state_set_title(WidgetRef ref, String v) {
    final cur = ref.read(shareControllerProvider);
    ref.read(shareControllerProvider.notifier).state =
        cur.copyWith(title: v, clearError: true);
  }

  Future<void> _copyText(BuildContext context) async {
    final text = ref.read(shareControllerProvider.notifier).exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('文案已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _saveToGallery(BuildContext context) async {
    final url = _imageUrl;
    if (url == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _downloadImage(url);
      final result = await SaverGallery.saveImage(
        bytes: bytes,
        fileName: 'yan-${DateTime.now().millisecondsSinceEpoch}',
        androidRelativePath: 'Pictures/Yan',
        skipIfExists: false,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册')),
        );
      } else {
        throw Exception(result.errorMessage ?? '保存失败');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _systemShare(BuildContext context) async {
    final url = _imageUrl;
    if (url == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _downloadImage(url);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/yan-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(bytes, flush: true);
      final text = ref.read(shareControllerProvider.notifier).exportText();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/jpeg')],
        text: text,
        subject: ref.read(shareControllerProvider).title,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

Future<Uint8List> _downloadImage(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw Exception('下载图片失败：HTTP ${response.statusCode}');
  }
  return response.bodyBytes;
}

class _PreviewCanvas extends StatelessWidget {
  const _PreviewCanvas({required this.imageUrl, required this.config});
  final String imageUrl;
  final ShareConfig config;

  @override
  Widget build(BuildContext context) {
    final aspect = switch (config.platform) {
      SharePlatform.original => null,
      SharePlatform.square => 1.0,
      SharePlatform.portrait3x4 => 3 / 4,
      SharePlatform.portrait4x5 => 4 / 5,
      SharePlatform.story9x16 => 9 / 16,
    };
    final ratioLabel = switch (config.platform) {
      SharePlatform.original => '原图',
      SharePlatform.square => '1:1',
      SharePlatform.portrait3x4 => '3:4',
      SharePlatform.portrait4x5 => '4:5',
      SharePlatform.story9x16 => '9:16',
    };
    Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: aspect == null ? BoxFit.contain : BoxFit.cover,
      ),
    );
    if (aspect != null) {
      image = AspectRatio(aspectRatio: aspect, child: image);
    }
    if (config.watermark != WatermarkPosition.hidden) {
      image = Stack(children: [
        image,
        Positioned(
          left: config.watermark == WatermarkPosition.bottomLeft ? 12 : null,
          right: config.watermark == WatermarkPosition.bottomRight ? 12 : null,
          top: config.watermark == WatermarkPosition.center ? null : null,
          bottom: 12,
          child: _Watermark(),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('预览', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(ratioLabel, style: const TextStyle(fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(20),
          ),
          child: image,
        ),
      ],
    );
  }
}

class _Watermark extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('颜 · AI 生成',
            style: TextStyle(color: Colors.white, fontSize: 11)),
      );
}

class _PlatformPicker extends StatelessWidget {
  const _PlatformPicker({required this.current, required this.onChanged});
  final SharePlatform current;
  final ValueChanged<SharePlatform> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('分享尺寸', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in SharePlatform.values)
              ChoiceChip(
                label: Text(p.label),
                selected: current == p,
                onSelected: (_) => onChanged(p),
              ),
          ]),
        ],
      );
}

class _WatermarkPicker extends StatelessWidget {
  const _WatermarkPicker({required this.current, required this.onChanged});
  final WatermarkPosition current;
  final ValueChanged<WatermarkPosition> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('水印', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final w in WatermarkPosition.values)
              ChoiceChip(
                label: Text(switch (w) {
                  WatermarkPosition.hidden => '不添加',
                  WatermarkPosition.bottomLeft => '左下',
                  WatermarkPosition.bottomRight => '右下',
                  WatermarkPosition.center => '居中',
                }),
                selected: current == w,
                onSelected: (_) => onChanged(w),
              ),
          ]),
        ],
      );
}

class _TagsEditor extends StatefulWidget {
  const _TagsEditor({required this.tags, required this.onChanged});
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_TagsEditor> createState() => _TagsEditorState();
}

class _TagsEditorState extends State<_TagsEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in widget.tags)
              InputChip(
                label: Text('#$t'),
                onDeleted: () {
                  final next = [...widget.tags]..remove(t);
                  widget.onChanged(next);
                },
              ),
            for (int i = 0; i < 3 - widget.tags.length && widget.tags.length < 3; i++)
              const SizedBox.shrink(),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '添加标签',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _add,
            icon: const Icon(Icons.add),
          ),
        ]),
      ],
    );
  }

  void _add() {
    final t = _controller.text.trim().replaceAll(RegExp(r'^#+'), '');
    if (t.isEmpty) return;
    if (widget.tags.contains(t)) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.tags, t]);
    _controller.clear();
  }
}

extension ImageTaskShare on ImageTask {
  // 留个扩展点,后续可直接传 ImageTask 进来。
}