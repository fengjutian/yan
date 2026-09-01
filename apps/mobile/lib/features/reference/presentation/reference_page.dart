import 'package:ai_image_studio/features/reference/presentation/reference_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReferencePage extends ConsumerStatefulWidget {
  const ReferencePage({this.loadStylesOnStart = true, super.key});
  final bool loadStylesOnStart;
  @override
  ConsumerState<ReferencePage> createState() => _ReferencePageState();
}

class _ReferencePageState extends ConsumerState<ReferencePage> {
  @override
  void initState() {
    super.initState();
    if (widget.loadStylesOnStart) {
      Future<void>.microtask(
        () => ref.read(referenceControllerProvider.notifier).loadStyles(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referenceControllerProvider);
    final controller = ref.read(referenceControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('人物参考创作')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        AspectRatio(
            aspectRatio: 4 / 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18)),
              child: state.previewBytes == null
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.person_add_alt_1, size: 52),
                      SizedBox(height: 8),
                      Text('上传清晰的人物参考图')
                    ]))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.memory(state.previewBytes!,
                          fit: BoxFit.contain)),
            )),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: state.busy ? null : controller.selectAndUpload,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(state.sourceAsset == null ? '选择并上传参考图' : '更换参考图')),
        if (state.busy && state.sourceAsset == null)
          LinearProgressIndicator(
              value: state.uploadProgress == 0 ? null : state.uploadProgress),
        const SizedBox(height: 20),
        Text('选择风格', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final style in state.styles)
            ChoiceChip(
                label: Text(style.name),
                selected: state.styleId == style.id,
                onSelected: (_) => controller.setStyle(style.id))
        ]),
        const SizedBox(height: 20),
        TextField(
            minLines: 3,
            maxLines: 6,
            onChanged: controller.setPrompt,
            decoration: const InputDecoration(
                labelText: '场景描述',
                hintText: '例如：保持人物特征，走在雨夜霓虹街道中',
                border: OutlineInputBorder(),
                alignLabelWithHint: true)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [
          for (final ratio in ['1:1', '16:9', '9:16'])
            ChoiceChip(
                label: Text(ratio),
                selected: state.aspectRatio == ratio,
                onSelected: (_) => controller.setAspectRatio(ratio))
        ]),
        if (state.errorMessage != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(state.errorMessage!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed:
                state.busy || (state.task != null && !state.task!.isTerminal)
                    ? null
                    : controller.generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('开始生成（10 积分）')),
        if (state.task != null) ...[
          const SizedBox(height: 20),
          if (!state.task!.isTerminal)
            LinearProgressIndicator(value: state.task!.progress / 100)
          else if (state.task!.status == 'FAILED')
            Card(
                child: ListTile(
                    title: const Text('生成失败，积分已退回'),
                    subtitle: Text(state.task!.errorMessage ?? '请稍后重试')))
          else
            for (final image in state.task!.images)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: CachedNetworkImage(
                          imageUrl: image.url, fit: BoxFit.contain))),
        ],
      ]),
    );
  }
}
