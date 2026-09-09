import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GeneratePage extends ConsumerStatefulWidget {
  const GeneratePage({super.key});
  static const ratios = ['1:1', '16:9', '9:16', '4:3'];

  @override
  ConsumerState<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends ConsumerState<GeneratePage> {
  final _promptController = TextEditingController();

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _openAiAssistant(GenerateController controller) async {
    final prompt = _promptController.text.trim();
    if (prompt.isNotEmpty) {
      final result = await controller.enhancePrompt();
      if (result == null || !mounted) return;
      _applyPrompt(result, controller);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('已依据你的描述补充画面细节'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      return;
    }
    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AiPromptSheet(currentPrompt: prompt),
    );
    if (result == null || !mounted) return;
    _applyPrompt(result, controller);
  }

  void _applyPrompt(String result, GenerateController controller) {
    _promptController.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
    controller.setPrompt(result);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(generateControllerProvider);
    final controller = ref.read(generateControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('文生图')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        TextField(
          controller: _promptController,
          minLines: 4,
          maxLines: 8,
          maxLength: 1500,
          onChanged: controller.setPrompt,
          decoration: InputDecoration(
              labelText: '画面描述',
              hintText: '例如：一只坐在月球上的橘猫，电影感，柔和轮廓光',
              alignLabelWithHint: true,
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 78),
                child: TextButton.icon(
                  onPressed: state.enhancing ? null : () => _openAiAssistant(controller),
                  icon: state.enhancing
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 19),
                  label: Text(state.enhancing ? '生成中' : 'AI 帮写'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7B5152),
                    backgroundColor: const Color(0xFFF1E8E1),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 104,
                minHeight: 48,
              ),
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        Text('画面比例', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final ratio in GeneratePage.ratios)
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
          _TaskResult(
            task: state.task!,
            onCancel: controller.cancel,
            onRetry: controller.retry,
          )
        ],
      ]),
    );
  }
}

class _AiPromptSheet extends StatelessWidget {
  const _AiPromptSheet({required this.currentPrompt});

  final String currentPrompt;

  static const _ideas = [
    (
      '氛围感人像',
      Icons.face_retouching_natural,
      '一位气质自然的年轻女性，松弛的姿态，干净妆容，柔和侧光，暖灰色背景，细腻胶片质感，时尚杂志摄影，克制而高级',
    ),
    (
      '电影场景',
      Icons.movie_filter_outlined,
      '雨后的城市街道，人物撑伞缓慢走过，橱窗暖光映在湿润路面，低饱和色彩，电影宽银幕构图，真实光影，安静而有故事感',
    ),
    (
      '高级产品',
      Icons.diamond_outlined,
      '极简香水产品静物，天然石材台面，清晨斜射光，柔和阴影，米白与深棕配色，大面积留白，高端品牌广告摄影，细节清晰',
    ),
    (
      '治愈插画',
      Icons.brush_outlined,
      '春日午后的安静房间，窗边花瓶与摊开的书，奶油色阳光，手绘肌理，低饱和自然色，轻盈留白，温柔治愈的编辑插画',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F6F1),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD4CEC7),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 22),
              const SizedBox(width: 10),
              Text('AI 辅助生成', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            currentPrompt.isEmpty ? '选择一个方向，快速获得完整画面描述。' : '完善当前描述，或换一个创作方向。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _ideas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final idea = _ideas[index];
                return ListTile(
                  onTap: () => Navigator.pop(context, idea.$3),
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFE5DED6)),
                  ),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1E8E1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(idea.$2, color: const Color(0xFF7B5152)),
                  ),
                  title: Text(idea.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.north_west_rounded, size: 18),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskResult extends StatelessWidget {
  const _TaskResult(
      {required this.task, required this.onCancel, required this.onRetry});
  final ImageTask task;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    if (!task.isTerminal) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('正在生成 · ${task.progress}%'),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: task.progress / 100),
        const SizedBox(height: 8),
        TextButton(onPressed: onCancel, child: const Text('取消任务')),
      ]);
    }
    if (task.status == 'FAILED') {
      return Card(
          child: ListTile(
        leading: Icon(Icons.error_outline,
            color: Theme.of(context).colorScheme.error),
        title: const Text('生成失败，积分已退回'),
        subtitle: Text(task.errorMessage ?? '请稍后重试'),
        trailing: TextButton(onPressed: onRetry, child: const Text('重试')),
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
