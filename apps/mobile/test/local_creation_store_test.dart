import 'dart:io';
import 'dart:typed_data';

import 'package:ai_image_studio/features/generate/data/local_creation_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory root;
  late LocalCreationStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('yan-local-store-');
    store = LocalCreationStore(rootOverride: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('保存生成结果并持久化图片/缩略图', () async {
    final bytes = _png(256, 128);
    final task = await store.saveSuccess(
      prompt: '窗边人像',
      aspectRatio: '1:1',
      count: 1,
      type: 'TEXT_TO_IMAGE',
      images: [bytes],
    );

    expect(task.status, 'SUCCEEDED');
    expect(task.images, hasLength(1));
    final image = task.images.single;
    expect(image.isLocal, isTrue);
    expect(File(image.localPath!).existsSync(), isTrue);
    expect(File(image.localThumbnailPath!).existsSync(), isTrue);

    final loaded = await store.require(task.id);
    expect(loaded.prompt, '窗边人像');
    expect(loaded.images.single.localPath, image.localPath);

    final list = await store.list();
    expect(list.map((item) => item.id), contains(task.id));
  });

  test('失败任务也会落盘并可查询', () async {
    final task = await store.saveFailure(
      prompt: 'test',
      aspectRatio: '9:16',
      count: 2,
      type: 'TEXT_TO_IMAGE',
      errorMessage: '网络错误',
    );

    expect(task.status, 'FAILED');
    expect(task.errorMessage, '网络错误');
    expect((await store.list()).single.id, task.id);
  });

  test('删除后不再出现', () async {
    final task = await store.saveSuccess(
      prompt: '删除测试',
      aspectRatio: '1:1',
      count: 1,
      type: 'TEXT_TO_IMAGE',
      images: [_png(64, 64)],
    );
    await store.delete(task.id);
    expect(await store.find(task.id), isNull);
    expect(await store.list(), isEmpty);
  });
}

Uint8List _png(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 140, 160));
  return Uint8List.fromList(img.encodePng(image));
}
