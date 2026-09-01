class GeneratedImage {
  const GeneratedImage(
      {required this.id, required this.url, required this.thumbnailUrl});
  final String id;
  final String url;
  final String thumbnailUrl;
  factory GeneratedImage.fromJson(Map<String, dynamic> json) => GeneratedImage(
        id: json['id'] as String,
        url: json['url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String? ?? '',
      );
}

class ImageTask {
  const ImageTask(
      {required this.id,
      required this.status,
      required this.progress,
      required this.prompt,
      required this.images,
      this.errorCode,
      this.errorMessage});
  final String id;
  final String status;
  final int progress;
  final String prompt;
  final List<GeneratedImage> images;
  final String? errorCode;
  final String? errorMessage;
  bool get isTerminal =>
      status == 'SUCCEEDED' || status == 'FAILED' || status == 'CANCELED';
  factory ImageTask.fromJson(Map<String, dynamic> json) => ImageTask(
        id: json['id'] as String,
        status: json['status'] as String,
        progress: json['progress'] as int,
        prompt: json['prompt'] as String,
        images: (json['images'] as List<dynamic>? ?? const [])
            .map(
                (item) => GeneratedImage.fromJson(item as Map<String, dynamic>))
            .toList(),
        errorCode: json['error_code'] as String?,
        errorMessage: json['error_message'] as String?,
      );
}
