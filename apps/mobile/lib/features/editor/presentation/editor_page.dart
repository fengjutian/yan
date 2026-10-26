import 'dart:io';

import 'package:ai_image_studio/app/theme.dart';
import 'package:ai_image_studio/features/editor/presentation/editor_controller.dart';
import 'package:ai_image_studio/features/generate/data/local_creation_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

/// 图片编辑器：裁剪 / 旋转 / 翻转 / 亮度 / 对比度 / 饱和度。
/// 后端不做图像处理，本地 image 包完成。
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({this.sourceBytes, super.key});
  final Uint8List? sourceBytes;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  Uint8List? _sourceBytes;
  Uint8List? _exportPreview;
  bool _exporting = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sourceBytes = widget.sourceBytes;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _sourceBytes;
    if (bytes == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('图片编辑器')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_library_outlined, size: 56),
                const SizedBox(height: 12),
                const Text('选择一张照片开始编辑'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _pickSource,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('从相册选择'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final state = ref.watch(editorControllerProvider(bytes));
    final controller = ref.read(editorControllerProvider(bytes).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('图片编辑器'),
        actions: [
          if (state.isDirty)
            TextButton(onPressed: controller.reset, child: const Text('重置')),
          TextButton(
            onPressed: _exporting ? null : () => _export(state),
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
                          ..scaleByDouble(
                            state.flipHorizontal ? -1.0 : 1.0,
                            state.flipVertical ? -1.0 : 1.0,
                            1.0,
                            1.0,
                          ),
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
          if (_exporting || _saving) const LinearProgressIndicator(),
          if (_exportPreview != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _saveToGallery,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('保存到相册'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _share,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('分享'),
                    ),
                  ),
                ],
              ),
            ),
          if (_exportPreview != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _saving ? null : _saveToLibrary,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('保存到作品库'),
                ),
              ),
            ),
          _AdjustPanel(state: state, controller: controller),
        ],
      ),
    );
  }

  Future<void> _pickSource() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 4096,
      maxHeight: 4096,
      imageQuality: 95,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _sourceBytes = bytes;
      _exportPreview = null;
    });
  }

  Future<void> _export(EditorState state) async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await compute(applyAdjustments, state);
      if (!mounted) return;
      setState(() => _exportPreview = result);
      messenger.showSnackBar(const SnackBar(content: Text('导出完成，可保存或分享')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveToGallery() async {
    final bytes = _exportPreview;
    if (bytes == null) return;
    setState(() => _saving = true);
    try {
      final result = await SaverGallery.saveImage(
        bytes,
        fileName: 'yan-edit-${DateTime.now().millisecondsSinceEpoch}',
        albumPath: 'Yan',
        skipIfExists: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isSuccess ? '已保存到相册' : '保存失败：${result.errorMessage}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveToLibrary() async {
    final bytes = _exportPreview;
    if (bytes == null) return;
    setState(() => _saving = true);
    try {
      final task = await ref
          .read(localCreationStoreProvider)
          .saveSuccess(
            prompt: '图片编辑',
            aspectRatio: '1:1',
            count: 1,
            type: 'EDIT',
            images: [bytes],
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已保存到作品库'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => context.push('/task/${task.id}'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存到作品库失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    final bytes = _exportPreview;
    if (bytes == null) return;
    setState(() => _saving = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/yan-edit-${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'image/png'),
      ], text: '颜 · AI 编辑');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
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
    return Row(
      children: [
        _ToolButton(
          icon: Icons.rotate_right,
          label: '旋转',
          onTap: controller.rotateClockwise,
        ),
        _ToolButton(
          icon: Icons.flip,
          label: '水平翻转',
          onTap: controller.flipHorizontal,
        ),
        _ToolButton(
          icon: Icons.flip_camera_android,
          label: '垂直翻转',
          onTap: controller.flipVertical,
        ),
        _ToolButton(
          icon: Icons.crop_landscape,
          label: '平台预设',
          onTap: () => _showPresetSheet(context, controller),
        ),
      ],
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
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
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
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 36,
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
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
        child: Text(
          value.round().toString(),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 11),
        ),
      ),
    ],
  );
}

class _Preset {
  const _Preset(this.label, this.w, this.h);
  final String label;
  final double w;
  final double h;

  CropRectNormalized toRect() {
    if (w >= h) {
      final h2 = h / w;
      return CropRectNormalized(0, (1 - h2) / 2, 1, (1 + h2) / 2);
    }
    final w2 = w / h;
    return CropRectNormalized((1 - w2) / 2, 0, (1 + w2) / 2, 1);
  }
}
