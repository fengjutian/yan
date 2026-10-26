class GeneratedImage {
  const GeneratedImage({
    required this.id,
    required this.url,
    required this.thumbnailUrl,
    this.localPath,
    this.localThumbnailPath,
  });

  final String id;

  /// 后端模式下的远程地址；本地 BYOK 模式下可能为空。
  final String url;

  /// 后端模式下的远程缩略图地址；本地 BYOK 模式下可能为空。
  final String thumbnailUrl;

  /// 本地 BYOK 模式下，图片在 App 沙盒中的绝对路径。
  final String? localPath;

  /// 本地 BYOK 模式下，缩略图在 App 沙盒中的绝对路径。
  final String? localThumbnailPath;

  bool get isLocal => localPath != null && localPath!.isNotEmpty;

  factory GeneratedImage.fromJson(Map<String, dynamic> json) => GeneratedImage(
    id: (json['id'] as String?) ?? '',
    url: (json['url'] as String?) ?? '',
    thumbnailUrl: (json['thumbnail_url'] as String?) ?? '',
    localPath: json['local_path'] as String?,
    localThumbnailPath: json['local_thumbnail_path'] as String?,
  );
}

class ImageTask {
  const ImageTask({
    required this.id,
    required this.status,
    required this.progress,
    required this.prompt,
    required this.images,
    this.errorCode,
    this.errorMessage,
    this.type = 'TEXT_TO_IMAGE',
    this.aspectRatio = '1:1',
    this.count = 1,
    this.styleId,
    this.createdAt,
    this.local = false,
  });

  final String id;
  final String status;
  final int progress;
  final String prompt;
  final List<GeneratedImage> images;
  final String? errorCode;
  final String? errorMessage;
  final String type;
  final String aspectRatio;
  final int count;
  final String? styleId;
  final DateTime? createdAt;

  /// 本地 BYOK 作品标记；失败任务没有图片，不能用 images 判断。
  final bool local;

  bool get isTerminal =>
      status == 'SUCCEEDED' || status == 'FAILED' || status == 'CANCELED';

  bool get isLocal => local || images.any((image) => image.isLocal);

  factory ImageTask.fromJson(Map<String, dynamic> json) => ImageTask(
    id: (json['id'] as String?) ?? '',
    status: (json['status'] as String?) ?? 'UNKNOWN',
    // progress 可能是 double(如 12.5),容错转 int
    progress: (json['progress'] is int)
        ? json['progress'] as int
        : (json['progress'] is num)
        ? (json['progress'] as num).round()
        : 0,
    prompt: (json['prompt'] as String?) ?? '',
    images: ((json['images'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GeneratedImage.fromJson)
        .toList(),
    errorCode: json['error_code'] as String?,
    errorMessage: json['error_message'] as String?,
    type: (json['type'] as String?) ?? 'TEXT_TO_IMAGE',
    aspectRatio: (json['aspect_ratio'] as String?) ?? '1:1',
    count: (json['count'] is int)
        ? json['count'] as int
        : (json['count'] is num)
        ? (json['count'] as num).round()
        : 1,
    styleId: json['style_id'] as String?,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    local: json['local'] == true,
  );
}

class ImageTaskPage {
  const ImageTaskPage({required this.tasks, required this.nextCursor});
  final List<ImageTask> tasks;
  final String nextCursor;
}
