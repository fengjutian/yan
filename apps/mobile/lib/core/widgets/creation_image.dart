import 'dart:io';
import 'dart:typed_data';

import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 统一展示本地 BYOK 图片和后端远程图片。
///
/// 本地模式图片在 App 沙盒里，远程模式仍使用 CachedNetworkImage。
class CreationImage extends StatelessWidget {
  const CreationImage({
    required this.image,
    this.fit = BoxFit.cover,
    this.preferThumbnail = false,
    this.placeholder,
    this.errorWidget,
    super.key,
  });

  final GeneratedImage image;
  final BoxFit fit;
  final bool preferThumbnail;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    final localPath = preferThumbnail
        ? image.localThumbnailPath
        : image.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          cacheWidth: 1600,
          errorBuilder: (_, __, ___) => _fallback(context),
        );
      }
    }
    final url = preferThumbnail ? image.thumbnailUrl : image.url;
    if (url.isEmpty) {
      return _fallback(context);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (_, __) => placeholder ?? _fallback(context),
      errorWidget: (_, __, ___) => errorWidget ?? _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    return errorWidget ??
        ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.image_not_supported_outlined)),
        );
  }
}

/// 读取一张作品图片的字节，用于保存到相册/系统分享。
Future<Uint8List?> loadCreationImageBytes(
  GeneratedImage image, {
  bool thumbnail = false,
}) async {
  final path = thumbnail ? image.localThumbnailPath : image.localPath;
  if (path != null && path.isNotEmpty) {
    final file = File(path);
    if (await file.exists()) return file.readAsBytes();
  }
  final url = thumbnail ? image.thumbnailUrl : image.url;
  if (url.isEmpty) return null;
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;
    return response.bodyBytes;
  } catch (_) {
    return null;
  }
}
