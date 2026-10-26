import 'dart:convert';
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

  test('相机/编辑作品也能进入本地作品库', () async {
    final camera = await store.saveSuccess(
      prompt: '相机拍摄',
      aspectRatio: '3:4',
      count: 1,
      type: 'CAMERA',
      images: [_png(90, 120)],
    );
    final edit = await store.saveSuccess(
      prompt: '图片编辑',
      aspectRatio: '1:1',
      count: 1,
      type: 'EDIT',
      images: [_png(80, 80)],
    );

    expect(camera.isLocal, isTrue);
    expect(edit.isLocal, isTrue);
    expect(
      (await store.list()).map((item) => item.type),
      containsAll(<String>['CAMERA', 'EDIT']),
    );
  });

  test('清除全部作品', () async {
    await store.saveSuccess(
      prompt: 'a',
      aspectRatio: '1:1',
      count: 1,
      type: 'CAMERA',
      images: [_png(32, 32)],
    );
    await store.saveFailure(
      prompt: 'b',
      aspectRatio: '1:1',
      count: 1,
      type: 'TEXT_TO_IMAGE',
      errorMessage: 'failed',
    );

    await store.deleteAll();
    expect(await store.list(), isEmpty);
  });

  test('元数据带版本且旧记录仍可读取', () async {
    final task = await store.saveSuccess(
      prompt: 'versioned',
      aspectRatio: '1:1',
      count: 1,
      type: 'EDIT',
      images: [_png(40, 40)],
    );
    final meta = File('${root.path}/${task.id}/meta.json');
    final json = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
    expect(json['schema_version'], 1);

    json.remove('schema_version');
    await meta.writeAsString(jsonEncode(json));
    expect((await store.require(task.id)).prompt, 'versioned');
  });

  test('列表隔离缺图记录，修复报告保留用户目录', () async {
    final task = await store.saveSuccess(
      prompt: 'missing',
      aspectRatio: '1:1',
      count: 1,
      type: 'CAMERA',
      images: [_png(32, 32)],
    );
    await File(task.images.single.localPath!).delete();

    expect(await store.list(), isEmpty);
    final report = await store.repair();
    expect(report.corruptRecords, 1);
    expect(report.missingFiles, 1);
    expect(Directory('${root.path}/${task.id}').existsSync(), isTrue);
  });

  test('修复会清理临时文件和空目录', () async {
    final empty = Directory('${root.path}/empty')..createSync();
    final temporary = File('${root.path}/orphan.tmp')
      ..writeAsStringSync('partial');

    final report = await store.repair();
    expect(report.removedTemporaryFiles, 1);
    expect(report.removedEmptyDirectories, 1);
    expect(temporary.existsSync(), isFalse);
    expect(empty.existsSync(), isFalse);
  });

  test('拒绝越界作品 ID', () async {
    expect(await store.find('../outside'), isNull);
    await expectLater(
      store.delete('../outside'),
      throwsA(isA<FormatException>()),
    );
  });
}

Uint8List _png(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 140, 160));
  return Uint8List.fromList(img.encodePng(image));
}
