class ImageAsset {
  const ImageAsset(
      {required this.id,
      required this.url,
      required this.thumbnailUrl,
      required this.mimeType,
      required this.width,
      required this.height,
      required this.byteSize});
  final String id;
  final String url;
  final String thumbnailUrl;
  final String mimeType;
  final int width;
  final int height;
  final int byteSize;
  factory ImageAsset.fromJson(Map<String, dynamic> json) => ImageAsset(
        id: (json['id'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
        thumbnailUrl: (json['thumbnail_url'] as String?) ?? '',
        mimeType: (json['mime_type'] as String?) ?? '',
        width: (json['width'] is int)
            ? json['width'] as int
            : (json['width'] is num)
                ? (json['width'] as num).round()
                : 0,
        height: (json['height'] is int)
            ? json['height'] as int
            : (json['height'] is num)
                ? (json['height'] as num).round()
                : 0,
        byteSize: (json['byte_size'] is int)
            ? json['byte_size'] as int
            : (json['byte_size'] is num)
                ? (json['byte_size'] as num).round()
                : 0,
      );
}
