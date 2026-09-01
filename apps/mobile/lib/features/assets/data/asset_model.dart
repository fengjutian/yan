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
        id: json['id'] as String,
        url: json['url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String? ?? '',
        mimeType: json['mime_type'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
        byteSize: json['byte_size'] as int,
      );
}
