import 'dart:typed_data';

import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/editor/presentation/editor_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 图片编辑器:裁剪 / 旋转 / 翻转 / 亮度 / 对比度 / 饱和度。
/// 后端不做图像处理,本地 image 包完成。完成后 bytes 走"分享工作台"链路。
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({this.sourceBytes, super.key});
  final Uint8List? sourceBytes;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  Uint8List? _fallback;
  Uint8List? _exportPreview;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    if (widget.sourceBytes == null) {
      // 用一张占位 bytes,避免空指针。后端资源接入时直接传真实字节。
      _fallback = _placeholder();
    }
  }

  Uint8List _placeholder() {
    final cm = Uint8List(64 * 64 * 4);
    for (var i = 0; i < cm.length; i += 4) {
      cm[i] = 230;
      cm[i + 1] = 211;
      cm[i + 2] = 184;
      cm[i + 3] = 255;
    }
    return cm;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.sourceBytes ?? _fallback;
    if (bytes == null) {
      return const Scaffold(body: Center(child: Text('没有可编辑的图片')));
    }
    final state = ref.watch(editorControllerProvider(bytes));
    final controller = ref.read(editorControllerProvider(bytes).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('图片编辑器'),
        actions: [
          if (state.isDirty)
            TextButton(
              onPressed: controller.reset,
              child: const Text('重置'),
            ),
          TextButton(
            onPressed: _exporting ? null : () => _export(bytes, state),
            child: const Text('完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _exportPreview == null
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..scale(state.flipHorizontal ? -1.0 : 1.0,
                              state.flipVertical ? -1.0 : 1.0),
                        child: RotatedBox(
                          quarterTurns: state.rotationQuarterTurns,
                          child: InteractiveViewer(
                            child: Image.memory(bytes, fit: BoxFit.contain),
                          ),
                        ),
                      )
                    : Image.memory(_exportPreview!, fit: BoxFit.contain),
              ),
            ),
          ),
          if (_exporting) const LinearProgressIndicator(),
          _AdjustPanel(
            state: state,
            controller: controller,
          ),
        ],
      ),
    );
  }

  Future<void> _export(Uint8List bytes, EditorState s) async {
    setState(() => _exporting = true);
    try {
      final result = await compute(applyAdjustments, s);
      if (!mounted) return;
      setState(() => _exportPreview = result);
      // 跳到分享工作台,带上编辑后的图(后续可改成内存缓存 + 路由 extra)。
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导出完成,可前往分享')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败:$e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _AdjustPanel extends StatelessWidget {
  const _AdjustPanel({required this.state, required this.controller});
  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolbarRow(controller: controller),
          const SizedBox(height: 12),
          _SliderRow(
            label: '亮度',
            value: state.brightness.toDouble(),
            min: -100,
            max: 100,
            onChanged: (v) => controller.setBrightness(v.round()),
          ),
          _SliderRow(
            label: '对比',
            value: state.contrast.toDouble(),
            min: -100,
            max: 100,
            onChanged: (v) => controller.setContrast(v.round()),
          ),
          _SliderRow(
            label: '饱和',
            value: state.saturation.toDouble(),
            min: -100,
            max: 100,
            onChanged: (v) => controller.setSaturation(v.round()),
          ),
        ],
      ),
    );
  }
}

class _ToolbarRow extends StatelessWidget {
  const _ToolbarRow({required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _ToolButton(icon: Icons.rotate_right, label: '旋转', onTap: controller.rotateClockwise),
      _ToolButton(
          icon: Icons.flip,
          label: '水平翻转',
          onTap: controller.flipHorizontal),
      _ToolButton(
          icon: Icons.flip_camera_android,
          label: '垂直翻转',
          onTap: controller.flipVertical),
      _ToolButton(
        icon: Icons.crop_rotate,
        label: '自由裁剪',
        onTap: () => _showCropDialog(context, controller),
      ),
      _ToolButton(
        icon: Icons.crop_landscape,
        label: '平台预设',
        onTap: () => _showPresetSheet(context, controller),
      ),
    ]);
  }

  void _showCropDialog(BuildContext context, EditorController controller) {
    showDialog<void>(
      context: context,
      builder: (_) => _CropPresetDialog(
        onSelected: (rect) {
          controller.setCrop(rect);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _showPresetSheet(BuildContext context, EditorController controller) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            for (final preset in [
              _Preset('1:1 朋友圈', 1.0, 1.0),
              _Preset('3:4 朋友圈', 3.0, 4.0),
              _Preset('4:5 小红书', 4.0, 5.0),
              _Preset('9:16 抖音', 9.0, 16.0),
              _Preset('16:9 视频封面', 16.0, 9.0),
            ])
              ListTile(
                title: Text(preset.label),
                onTap: () {
                  controller.setCrop(preset.toRect());
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 10)),
            ]),
          ),
        ),
      );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
            width: 36,
            child: Text(label, style: const TextStyle(fontSize: 11))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11)),
        ),
      ]);
}

class _Preset {
  const _Preset(this.label, this.w, this.h);
  final String label;
  final double w;
  final double h;

  CropRectNormalized toRect() {
    // 默认从画面中心按比例裁,长边填满
    if (w >= h) {
      final h2 = h / w;
      return CropRectNormalized(0, (1 - h2) / 2, 1, (1 + h2) / 2);
    }
    final w2 = w / h;
    return CropRectNormalized((1 - w2) / 2, 0, (1 + w2) / 2, 1);
  }
}

class _CropPresetDialog extends StatelessWidget {
  const _CropPresetDialog({required this.onSelected});
  final ValueChanged<CropRectNormalized> onSelected;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('自由比例'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: const Text('原始'),
            onTap: () => onSelected(CropRectNormalized(0, 0, 1, 1)),
          ),
          ListTile(
            title: const Text('1:1'),
            onTap: () => onSelected(_Preset('1:1', 1, 1).toRect()),
          ),
          ListTile(
            title: const Text('4:5'),
            onTap: () => onSelected(_Preset('4:5', 4, 5).toRect()),
          ),
          ListTile(
            title: const Text('9:16'),
            onTap: () => onSelected(_Preset('9:16', 9, 16).toRect()),
          ),
        ]),
      );
}