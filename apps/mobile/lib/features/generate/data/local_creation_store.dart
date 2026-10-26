import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 本地 BYOK 模式下的作品仓库。
///
/// 设计目标：
/// - 不依赖后端，作品和任务状态都在本机持久化；
/// - 图片写入 App Support 目录，数据库里只保存相对文件名；
/// - 生成结果统一重编码为 JPEG，避免 HEIC/EXIF 方向等问题；
/// - 失败任务也落盘，用户可以在历史里看到失败原因并重试。
class LocalCreationStore {
  LocalCreationStore({Directory? rootOverride}) : _rootOverride = rootOverride;

  static const _metaFileName = 'meta.json';
  static const _thumbnailWidth = 512;

  final Directory? _rootOverride;
  final _uuid = const Uuid();

  Future<Directory> _root() async {
    final root =
        _rootOverride ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}creations',
        );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> _taskDir(String id) async {
    final root = await _root();
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<ImageTask> saveSuccess({
    required String prompt,
    required String aspectRatio,
    required int count,
    required String type,
    required List<Uint8List> images,
    String? styleId,
  }) async {
    if (images.isEmpty) {
      throw const FormatException('AI 没有返回图片');
    }
    final id = _uuid.v4();
    final dir = await _taskDir(id);
    final generated = <GeneratedImage>[];
    try {
      for (var index = 0; index < images.length; index++) {
        final decoded = img.decodeImage(images[index]);
        if (decoded == null) {
          throw const FormatException('无法解析 AI 返回的图片');
        }
        final normalized = img.bakeOrientation(decoded);
        final imageFile = File(
          '${dir.path}${Platform.pathSeparator}image-$index.jpg',
        );
        final thumbnailFile = File(
          '${dir.path}${Platform.pathSeparator}thumb-$index.jpg',
        );
        await imageFile.writeAsBytes(
          img.encodeJpg(normalized, quality: 92),
          flush: true,
        );
        final thumbnailWidth = normalized.width > _thumbnailWidth
            ? _thumbnailWidth
            : normalized.width;
        final thumbnail = img.copyResize(normalized, width: thumbnailWidth);
        await thumbnailFile.writeAsBytes(
          img.encodeJpg(thumbnail, quality: 80),
          flush: true,
        );
        generated.add(
          GeneratedImage(
            id: '$id-$index',
            url: '',
            thumbnailUrl: '',
            localPath: imageFile.path,
            localThumbnailPath: thumbnailFile.path,
          ),
        );
      }
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }

    final task = ImageTask(
      id: id,
      status: 'SUCCEEDED',
      progress: 100,
      prompt: prompt,
      images: generated,
      type: type,
      aspectRatio: aspectRatio,
      count: count,
      styleId: styleId,
      createdAt: DateTime.now().toUtc(),
      local: true,
    );
    await _writeMeta(dir, task);
    return task;
  }

  Future<ImageTask> saveFailure({
    required String prompt,
    required String aspectRatio,
    required int count,
    required String type,
    required String errorMessage,
    String? errorCode,
    String? styleId,
  }) async {
    final id = _uuid.v4();
    final dir = await _taskDir(id);
    final task = ImageTask(
      id: id,
      status: 'FAILED',
      progress: 100,
      prompt: prompt,
      images: const [],
      errorMessage: errorMessage,
      errorCode: errorCode,
      type: type,
      aspectRatio: aspectRatio,
      count: count,
      styleId: styleId,
      createdAt: DateTime.now().toUtc(),
      local: true,
    );
    await _writeMeta(dir, task);
    return task;
  }

  Future<ImageTask?> find(String id) async {
    if (id.isEmpty) return null;
    final root = await _root();
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    final meta = File('${dir.path}${Platform.pathSeparator}$_metaFileName');
    if (!await meta.exists()) return null;
    try {
      final raw = jsonDecode(await meta.readAsString());
      if (raw is! Map<String, dynamic>) return null;
      return _taskFromJson(dir, raw);
    } on FormatException {
      return null;
    }
  }

  Future<ImageTask> require(String id) async {
    final task = await find(id);
    if (task == null) {
      throw StateError('本地作品不存在，可能已被清理');
    }
    return task;
  }

  Future<List<ImageTask>> list({int limit = 50}) async {
    final root = await _root();
    final tasks = <ImageTask>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final meta = File(
        '${entity.path}${Platform.pathSeparator}$_metaFileName',
      );
      if (!await meta.exists()) continue;
      try {
        final raw = jsonDecode(await meta.readAsString());
        if (raw is Map<String, dynamic>) {
          tasks.add(_taskFromJson(entity, raw));
        }
      } on FormatException {
        // 损坏的记录不阻塞整个作品库。
      }
    }
    tasks.sort((a, b) {
      final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return tasks.take(limit).toList(growable: false);
  }

  Future<void> delete(String id) async {
    final root = await _root();
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _writeMeta(Directory dir, ImageTask task) async {
    final images = <Map<String, dynamic>>[];
    for (final image in task.images) {
      final path = image.localPath;
      if (path == null || path.isEmpty) continue;
      images.add({
        'id': image.id,
        'file': _basename(path),
        'thumbnail_file': image.localThumbnailPath == null
            ? null
            : _basename(image.localThumbnailPath!),
      });
    }
    final payload = <String, dynamic>{
      'id': task.id,
      'status': task.status,
      'progress': task.progress,
      'prompt': task.prompt,
      'type': task.type,
      'aspect_ratio': task.aspectRatio,
      'count': task.count,
      'style_id': task.styleId,
      'error_code': task.errorCode,
      'error_message': task.errorMessage,
      'created_at': (task.createdAt ?? DateTime.now().toUtc())
          .toIso8601String(),
      'images': images,
    };
    final target = File('${dir.path}${Platform.pathSeparator}$_metaFileName');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await temporary.rename(target.path);
  }

  ImageTask _taskFromJson(Directory dir, Map<String, dynamic> raw) {
    final images = <GeneratedImage>[];
    final rawImages = raw['images'];
    if (rawImages is List) {
      for (final item in rawImages) {
        if (item is! Map) continue;
        final file = item['file'];
        final thumb = item['thumbnail_file'];
        if (file is! String || file.isEmpty) continue;
        final imagePath = '${dir.path}${Platform.pathSeparator}$file';
        final thumbPath = thumb is String && thumb.isNotEmpty
            ? '${dir.path}${Platform.pathSeparator}$thumb'
            : null;
        images.add(
          GeneratedImage(
            id: item['id']?.toString() ?? '',
            url: '',
            thumbnailUrl: '',
            localPath: imagePath,
            localThumbnailPath: thumbPath,
          ),
        );
      }
    }
    return ImageTask(
      id: raw['id']?.toString() ?? '',
      status: raw['status']?.toString() ?? 'FAILED',
      progress: raw['progress'] is num ? (raw['progress'] as num).round() : 0,
      prompt: raw['prompt']?.toString() ?? '',
      images: images,
      errorCode: raw['error_code']?.toString(),
      errorMessage: raw['error_message']?.toString(),
      type: raw['type']?.toString() ?? 'TEXT_TO_IMAGE',
      aspectRatio: raw['aspect_ratio']?.toString() ?? '1:1',
      count: raw['count'] is num ? (raw['count'] as num).round() : 1,
      styleId: raw['style_id']?.toString(),
      createdAt: DateTime.tryParse(raw['created_at']?.toString() ?? ''),
      local: true,
    );
  }

  String _basename(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    if (index >= 0) return path.substring(index + 1);
    final slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }
}

final localCreationStoreProvider = Provider<LocalCreationStore>(
  (ref) => LocalCreationStore(),
);
