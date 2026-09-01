import 'package:ai_image_studio/features/assets/presentation/asset_upload_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AssetUploadPage extends ConsumerWidget {
  const AssetUploadPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(assetUploadControllerProvider);
    final controller = ref.read(assetUploadControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('上传参考图片')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20)),
              child: state.previewBytes == null
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 56),
                      SizedBox(height: 12),
                      Text('选择 JPEG、PNG 或 WebP 图片')
                    ]))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(state.previewBytes!,
                          fit: BoxFit.contain)),
            )),
        const SizedBox(height: 20),
        OutlinedButton.icon(
            onPressed: state.uploading ? null : controller.selectImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('从相册选择')),
        const SizedBox(height: 12),
        if (state.uploading) ...[
          LinearProgressIndicator(
              value: state.progress == 0 ? null : state.progress),
          const SizedBox(height: 12)
        ],
        if (state.errorMessage != null) ...[
          Text(state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12)
        ],
        if (state.uploadedAsset != null) ...[
          const Card(
              child: ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('上传成功'),
                  subtitle: Text('图片已安全保存，可用于人物参考创作。'))),
          const SizedBox(height: 12)
        ],
        FilledButton.icon(
            onPressed: state.uploading || state.selectedFile == null
                ? null
                : controller.upload,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('上传图片')),
        const SizedBox(height: 12),
        Text('最大 10 MB，最长边不超过 4096 像素。上传内容将用于 AI 图片创作。',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
