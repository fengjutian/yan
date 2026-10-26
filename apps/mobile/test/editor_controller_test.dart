import 'dart:typed_data';

import 'package:ai_image_studio/features/editor/presentation/editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EditorController controller;

  setUp(() {
    controller = EditorController(Uint8List.fromList([1, 2, 3]));
  });

  tearDown(() {
    controller.dispose();
  });

  test('编辑操作可以撤销和重做', () {
    controller.setBrightness(20);
    controller.rotateClockwise();

    expect(controller.state.brightness, 20);
    expect(controller.state.rotationQuarterTurns, 1);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.state.brightness, 20);
    expect(controller.state.rotationQuarterTurns, 0);
    expect(controller.canRedo, isTrue);

    controller.undo();
    expect(controller.state.isDirty, isFalse);

    controller.redo();
    expect(controller.state.brightness, 20);
  });

  test('新操作会清空重做历史', () {
    controller.setContrast(10);
    controller.undo();
    expect(controller.canRedo, isTrue);

    controller.setSaturation(30);
    expect(controller.canRedo, isFalse);
    expect(controller.state.contrast, 0);
    expect(controller.state.saturation, 30);
  });

  test('相同参数不会生成重复历史', () {
    controller.setBrightness(0);
    expect(controller.canUndo, isFalse);

    controller.setBrightness(12);
    controller.setBrightness(12);
    controller.undo();
    expect(controller.state.brightness, 0);
    expect(controller.canUndo, isFalse);
  });

  test('重置本身可以撤销', () {
    controller.setCrop(const CropRectNormalized(0.1, 0.2, 0.8, 0.9));
    controller.flipHorizontal();
    controller.reset();
    expect(controller.state.isDirty, isFalse);

    controller.undo();
    expect(controller.state.cropRect, isNotNull);
    expect(controller.state.flipHorizontal, isTrue);
  });
}
