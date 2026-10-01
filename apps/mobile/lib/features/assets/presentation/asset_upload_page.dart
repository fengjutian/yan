import 'package:ai_image_studio/features/assets/presentation/asset_upload_controller.dart';
import 'package:ai_image_studio/features/ai_settings/presentation/ai_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AssetUploadPage extends ConsumerWidget {
  const AssetUploadPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(assetUploadControllerProvider);
    final localOnly = ref.watch(
      aiSettingsControllerProvider.select(
        (value) => value.settings.preferLocal,
      ),
    );
    final controller = ref.read(assetUploadControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('上传参考图片')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: state.previewBytes == null
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 56),
                          SizedBox(height: 12),
                          Text('选择 JPEG、PNG 或 WebP 图片'),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(
                        state.previewBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: state.uploading ? null : controller.selectImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('从相册选择'),
          ),
          const SizedBox(height: 12),
          if (state.uploading) ...[
            LinearProgressIndicator(
              value: state.progress == 0 ? null : state.progress,
            ),
            const SizedBox(height: 12),
          ],
          if (state.errorMessage != null) ...[
            Text(
              state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          if (state.uploadedAsset != null) ...[
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('图片已就绪'),
                subtitle: Text('图片已保留在本机，可用于后续创作。'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: state.uploading || state.selectedFile == null
                ? null
                : controller.upload,
            icon: Icon(
              localOnly
                  ? Icons.offline_pin_outlined
                  : Icons.cloud_upload_outlined,
            ),
            label: Text(localOnly ? '使用本地图片' : '上传图片'),
          ),
          const SizedBox(height: 12),
          Text(
            localOnly
                ? '本地模式：图片不会上传服务器。最大 10 MB，最长边不超过 4096 像素。'
                : '后端模式：图片将上传服务器用于 AI 图片创作。最大 10 MB，最长边不超过 4096 像素。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
