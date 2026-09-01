import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GeneratePage extends ConsumerWidget {
  const GeneratePage({super.key});
  static const ratios = ['1:1', '16:9', '9:16', '4:3'];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(generateControllerProvider);
    final controller = ref.read(generateControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('文生图')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        TextField(
          minLines: 4,
          maxLines: 8,
          maxLength: 1500,
          onChanged: controller.setPrompt,
          decoration: const InputDecoration(
              labelText: '画面描述',
              hintText: '例如：一只坐在月球上的橘猫，电影感，柔和轮廓光',
              alignLabelWithHint: true,
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        Text('画面比例', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final ratio in ratios)
            ChoiceChip(
                label: Text(ratio),
                selected: state.aspectRatio == ratio,
                onSelected: (_) => controller.setAspectRatio(ratio))
        ]),
        const SizedBox(height: 20),
        Text('生成数量', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1 张')),
            ButtonSegment(value: 2, label: Text('2 张')),
            ButtonSegment(value: 4, label: Text('4 张'))
          ],
          selected: {state.count},
          onSelectionChanged: (value) => controller.setCount(value.first),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动优化 Prompt'),
            subtitle: const Text('由图片模型优化描述细节'),
            value: state.promptOptimizer,
            onChanged: controller.setPromptOptimizer),
        if (state.errorMessage != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(state.errorMessage!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        FilledButton.icon(
          onPressed: state.submitting ||
                  (state.task != null && !state.task!.isTerminal)
              ? null
              : controller.generate,
          icon: const Icon(Icons.auto_awesome),
          label:
              Text(state.submitting ? '正在提交…' : '开始生成（${state.count * 10} 积分）'),
        ),
        if (state.task != null) ...[
          const SizedBox(height: 24),
          _TaskResult(task: state.task!)
        ],
      ]),
    );
  }
}

class _TaskResult extends StatelessWidget {
  const _TaskResult({required this.task});
  final ImageTask task;
  @override
  Widget build(BuildContext context) {
    if (!task.isTerminal) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('正在生成 · ${task.progress}%'),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: task.progress / 100),
      ]);
    }
    if (task.status == 'FAILED') {
      return Card(
          child: ListTile(
        leading: Icon(Icons.error_outline,
            color: Theme.of(context).colorScheme.error),
        title: const Text('生成失败，积分已退回'),
        subtitle: Text(task.errorMessage ?? '请稍后重试'),
      ));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: task.images.length,
      itemBuilder: (context, index) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
            imageUrl: task.images[index].thumbnailUrl, fit: BoxFit.cover),
      ),
    );
  }
}
