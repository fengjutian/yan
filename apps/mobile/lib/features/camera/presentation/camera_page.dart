import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_image_studio/features/camera/data/camera_session.dart';
import 'package:ai_image_studio/features/camera/data/face_analyzer.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';

enum CompositionGuide { thirds, center, symmetry }

class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key, this.templateParams});

  /// 来自 /templates/:id 跳过来时携带的模板参数(机位/构图/初始 prompt)。
  final TemplateParams? templateParams;

  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

/// 模板参数:跳相机时由 router extra 传入。
class TemplateParams {
  const TemplateParams({
    required this.templateId,
    required this.prompt,
    required this.composition,
    required this.angle,
  });
  final String templateId;
  final String prompt;
  final String composition; // CompositionGuide.name
  final String angle;        // CameraAngle.name
}

class _CameraPageState extends ConsumerState<CameraPage>
    with WidgetsBindingObserver {
  final _picker = ImagePicker();
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  Uint8List? _capturedImage;
  CompositionGuide _guide = CompositionGuide.thirds;
  FlashMode _flashMode = FlashMode.off;
  bool _showGuide = true;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;
  int _countdownSeconds = 0;
  int _countdown = 0;
  double _baseZoom = 1;
  double _zoom = 1;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _exposure = 0;
  double _minExposure = 0;
  double _maxExposure = 0;
  double _levelAngle = 0;
  double _brightness = 128;
  double _aspectRatio = 3 / 4;
  int _burstCount = 1;
  int _activeIndex = 0;
  String _compositionSuggestion = '让主体靠近交叉点，画面会更有呼吸感';
  Offset? _focusPoint;
  StreamSubscription<AccelerometerEvent>? _motionSubscription;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motionSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 120),
    ).listen((event) {
      final angle = math.atan2(event.x, event.y) * 180 / math.pi;
      if (mounted) setState(() => _levelAngle = angle.clamp(-45, 45));
    }, onError: (_) {});
    _applyTemplateParams();
    unawaited(_loadCameras());
  }

  void _applyTemplateParams() {
    final p = widget.templateParams;
    if (p == null) return;
    // 构图线按模板初始值预选。
    final guide = CompositionGuide.values.firstWhere(
      (g) => g.name == p.composition,
      orElse: () => CompositionGuide.thirds,
    );
    _guide = guide;
    _showGuide = true;
    // 初始 prompt 由后续 review 流程注入到 generate 控制器,
    // 这里仅缓存到本地,后续 review 时通过 go_router 携带。
    _initialPrompt = p.prompt;
    _templateId = p.templateId;
  }

  String? _initialPrompt;
  String? _templateId;

  Future<void> _loadCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('no-camera', '未检测到可用相机');
      await _initializeCamera(0);
    } on CameraException catch (error) {
      _handleCameraError(error);
    } on PlatformException catch (error) {
      _handleCameraError(error);
    } catch (error) {
      _handleCameraError(error);
    }
  }

  void _handleCameraError(Object error) {
    final stale = _controller;
    if (!mounted) {
      // 即使 widget 已 dispose 也要把 controller 释放,避免 native handle 泄漏。
      unawaited(stale?.dispose());
      return;
    }
    setState(() {
      _error = _cameraError(error);
      _initializing = false;
      _controller = null;
    });
    // 失败路径的旧 controller 需要释放,否则 native camera HAL 句柄会泄漏。
    unawaited(stale?.dispose());
  }

  Future<void> _initializeCamera(int index) async {
    final previous = _controller;
    if (previous != null && mounted) {
      // 先把 UI 切到加载态，避免 dispose 的 await 期间出现
      // _initializing=false / _controller=null 的不一致窗口。
      setState(() {
        _initializing = true;
        _error = null;
        _controller = null;
      });
    }
    await previous?.dispose();
    if (!mounted) return;
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    if (!mounted) {
      unawaited(controller.dispose());
      return;
    }
    _controller = controller;
    try {
      // Vivo 等定制 ROM 上 controller.initialize() / getMinZoomLevel 等偶发挂死,
      // 用 .timeout 兜底,超时后落到错误态而不是永久 spinner。
      await controller.initialize().timeout(const Duration(seconds: 8));
      _minZoom = await controller.getMinZoomLevel().timeout(const Duration(seconds: 3));
      _maxZoom = await controller.getMaxZoomLevel().timeout(const Duration(seconds: 3));
      _minExposure = await controller.getMinExposureOffset().timeout(const Duration(seconds: 3));
      _maxExposure = await controller.getMaxExposureOffset().timeout(const Duration(seconds: 3));
      _zoom = _minZoom;
      _flashMode = FlashMode.off;
      await controller.setFlashMode(_flashMode).timeout(const Duration(seconds: 3));
      await _startLightMonitoring(controller);
      if (mounted) setState(() => _initializing = false);
    } on CameraException catch (error) {
      _handleCameraError(error);
    } on PlatformException catch (error) {
      _handleCameraError(error);
    } on TimeoutException catch (_) {
      _handleCameraError(
          CameraException('init-timeout', '相机初始化超时，请重试或重启应用'));
    } catch (error) {
      _handleCameraError(error);
    }
  }

  Future<void> _startLightMonitoring(CameraController controller) async {
    try {
      await controller.startImageStream((image) {
        final now = DateTime.now();
        if (now.difference(_lastFrameAt).inMilliseconds < 600 ||
            image.planes.isEmpty) {
          return;
        }
        _lastFrameAt = now;
        final bytes = image.planes.first.bytes;
        var total = 0;
        var count = 0;
        for (var index = 0; index < bytes.length; index += 80) {
          total += bytes[index];
          count++;
        }
        if (mounted && count > 0) setState(() => _brightness = total / count);
      });
    } on CameraException {
      // Some web cameras do not expose an image stream.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        _activeIndex = _cameras.indexOf(controller.description);
        if (_activeIndex < 0) _activeIndex = 0;
        controller.dispose();
      }
      if (mounted) {
        // 必须连同 _initializing 一起置位,避免下一次 build 命中 _controller==null
        // 但 _initializing==false 的不一致窗口。
        setState(() {
          _controller = null;
          _initializing = true;
        });
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_cameras.isEmpty) return;
      // 上面的 inactive 已经把 _controller 置 null,所以这里不能再用
      // "controller == null" 作为 early-return 条件 —— 那会让 resumed 静默退出,
      // UI 永久卡在 spinner 上。
      if (_controller != null && _controller!.value.isInitialized) return;
      unawaited(_initializeCamera(_activeIndex));
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _initializing) return;
    final current = _controller?.description;
    final index = _cameras.indexWhere((camera) => camera == current);
    _activeIndex = (index + 1) % _cameras.length;
    await _initializeCamera(_activeIndex);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = _flashMode == FlashMode.off
        ? FlashMode.auto
        : _flashMode == FlashMode.auto
            ? FlashMode.always
            : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } on CameraException {
      if (mounted) _showMessage('当前设备不支持此闪光灯模式');
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      for (var value = _countdownSeconds; value > 0; value--) {
        if (!mounted) return;
        setState(() => _countdown = value);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (mounted) setState(() => _countdown = 0);
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final values = <Uint8List>[];
      XFile? analysisFile;
      for (var index = 0; index < _burstCount; index++) {
        final file = await controller.takePicture();
        analysisFile ??= file;
        values.add(await file.readAsBytes());
        if (index + 1 < _burstCount) {
          await Future<void>.delayed(const Duration(milliseconds: 220));
        }
      }
      await ref.read(cameraSessionProvider.notifier).setPhotos(values);
      final session = ref.read(cameraSessionProvider);
      final size = controller.value.previewSize;
      if (analysisFile != null && size != null) {
        final analysis = await analyzeFaces(
            analysisFile.path, size.width.round(), size.height.round());
        _compositionSuggestion = analysis.suggestion;
      }
      if (mounted) setState(() => _capturedImage = session.selected?.bytes);
    } on CameraException catch (error) {
      if (mounted) _showMessage(_cameraError(error));
    } on PlatformException catch (error) {
      if (mounted) _showMessage(_cameraError(error));
    } catch (error) {
      // MLKit 失败、文件 IO 失败等都兜到这里,不裸露异常。
      if (mounted) _showMessage(_cameraError(error));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _importPhoto() async {
    final file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref.read(cameraSessionProvider.notifier).setPhotos([bytes]);
    if (mounted) setState(() => _capturedImage = bytes);
  }

  Future<void> _focus(
      TapDownDetails details, BoxConstraints constraints) async {
    final controller = _controller;
    if (controller == null) return;
    final point = Offset(
      (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
      setState(() => _focusPoint = details.localPosition);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) setState(() => _focusPoint = null);
    } on CameraException {/* Device does not support manual focus. */}
  }

  Future<void> _setZoom(double scale) async {
    final controller = _controller;
    if (controller == null) return;
    final value = (_baseZoom * scale).clamp(_minZoom, _maxZoom).toDouble();
    try {
      await controller.setZoomLevel(value);
      if (mounted) setState(() => _zoom = value);
    } on CameraException catch (_) {
      // 设备不支持连续 zoom,静默失败
    } on PlatformException catch (_) {
      // 部分 ROM 上 setZoomLevel 偶发 PlatformException
    }
  }

  Future<void> _setExposure(double value) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final applied = await controller.setExposureOffset(value);
      if (mounted) setState(() => _exposure = applied);
    } on CameraException catch (_) {
      // 设备不支持曝光调节
    } on PlatformException catch (_) {/* 同上 */}
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

  String _cameraError(Object error) {
    if (error is CameraException) {
      if (error.code == 'CameraAccessDenied' ||
          error.code == 'CameraAccessDeniedWithoutPrompt') {
        return '需要相机权限才能拍摄，请在系统设置中允许访问';
      }
      return error.description ?? '相机暂时不可用';
    }
    if (error is PlatformException) {
      if (error.code == 'CameraAccessDenied' ||
          error.code == 'camera_permission' ||
          error.code == 'MissingPluginException') {
        return '需要相机权限才能拍摄，请在系统设置中允许访问';
      }
      return error.message ?? '相机暂时不可用';
    }
    return error.toString();
  }

  String get _guideName => switch (_guide) {
        CompositionGuide.thirds => '三分构图',
        CompositionGuide.center => '中心构图',
        CompositionGuide.symmetry => '对称构图',
      };

  IconData get _flashIcon => switch (_flashMode) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        _ => Icons.flash_on,
      };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motionSubscription?.cancel();
    final controller = _controller;
    _controller = null; // 先置 null,避免 didChangeAppLifecycleState 二次 dispose
    unawaited(controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_capturedImage != null) return _buildReview();
    return Scaffold(
      backgroundColor: const Color(0xFF171615),
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          Expanded(
              child: Center(
                  child: AspectRatio(
                      aspectRatio: _aspectRatio,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: _buildPreview()))))),
          _buildControls(),
        ]),
      ),
    );
  }

  Widget _buildTopBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          IconButton(
              onPressed: _toggleFlash,
              icon: Icon(_flashIcon, color: Colors.white)),
          const Spacer(),
          TextButton(
              onPressed: () => setState(() => _showGuide = !_showGuide),
              child: Text(_showGuide ? _guideName : '构图线关闭',
                  style: const TextStyle(color: Colors.white))),
          const Spacer(),
          IconButton(
              onPressed: _switchCamera,
              icon:
                  const Icon(Icons.cameraswitch_outlined, color: Colors.white)),
        ]),
      );

  Widget _buildPreview() {
    // _initializing 和 _controller 必须联动:前者 true 时后者允许为 null,
    // 但反过来不应出现 _initializing==false 且 _controller==null 的窗口。
    // 这里兜底一次,避免任何遗漏路径触发 NPE。
    if (_initializing || _controller == null) {
      return const ColoredBox(
          color: Color(0xFF242220),
          child: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    if (_error != null) {
      return ColoredBox(
          color: const Color(0xFF242220),
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.no_photography_outlined,
                        color: Colors.white70, size: 45),
                    const SizedBox(height: 14),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 18),
                    OutlinedButton(
                        onPressed: _loadCameras, child: const Text('重试'))
                  ]))));
    }
    final controller = _controller!;
    return LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
              onTapDown: (details) => _focus(details, constraints),
              onScaleStart: (_) => _baseZoom = _zoom,
              onScaleUpdate: (details) => _setZoom(details.scale),
              child: Stack(fit: StackFit.expand, children: [
                CameraPreview(controller),
                if (_showGuide)
                  IgnorePointer(
                      child: CustomPaint(painter: _GuidePainter(_guide))),
                if (_focusPoint != null)
                  Positioned(
                      left: _focusPoint!.dx - 25,
                      top: _focusPoint!.dy - 25,
                      child: const IgnorePointer(child: _FocusRing())),
                if (_countdown > 0)
                  Center(
                      child: Text('$_countdown',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 92,
                              fontWeight: FontWeight.w300))),
                Positioned(
                    top: 15,
                    left: 0,
                    right: 0,
                    child: Center(child: _LevelIndicator(angle: _levelAngle))),
                Positioned(
                    right: 4,
                    top: 55,
                    child: RotatedBox(
                        quarterTurns: 3,
                        child: SizedBox(
                            width: 140,
                            child: Slider(
                                value:
                                    _exposure.clamp(_minExposure, _maxExposure),
                                min: _minExposure,
                                max: _maxExposure == _minExposure
                                    ? _minExposure + 1
                                    : _maxExposure,
                                onChanged: _setExposure)))),
                Positioned(
                    bottom: 18,
                    left: 18,
                    right: 18,
                    child: _CameraTip(
                        zoom: _zoom,
                        brightness: _brightness,
                        suggestion: _compositionSuggestion)),
              ]),
            ));
  }

  Widget _buildControls() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final ratio in const [
              ('1:1', 1.0),
              ('3:4', .75),
              ('9:16', .5625)
            ])
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                      label: Text(ratio.$1),
                      selected: _aspectRatio == ratio.$2,
                      onSelected: (_) =>
                          setState(() => _aspectRatio = ratio.$2))),
            const SizedBox(width: 6),
            ChoiceChip(
                label: Text(_burstCount == 1 ? '单拍' : '连拍 5 张'),
                selected: _burstCount == 5,
                onSelected: (_) =>
                    setState(() => _burstCount = _burstCount == 1 ? 5 : 1)),
          ]),
          const SizedBox(height: 8),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [0, 3, 10]
                  .map((seconds) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                          label: Text(seconds == 0 ? '关闭' : '$seconds 秒'),
                          selected: _countdownSeconds == seconds,
                          onSelected: (_) =>
                              setState(() => _countdownSeconds = seconds))))
                  .toList()),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _RoundAction(
                icon: Icons.photo_library_outlined,
                label: '相册',
                onTap: _importPhoto),
            GestureDetector(
                onTap: _capture,
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 74,
                    height: 74,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)),
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: _capturing ? Colors.white38 : Colors.white,
                            shape: BoxShape.circle)))),
            _RoundAction(
                icon: Icons.grid_3x3,
                label: '切换构图',
                onTap: () => setState(() => _guide = CompositionGuide.values[
                    (_guide.index + 1) % CompositionGuide.values.length])),
          ]),
        ]),
      );

  Widget _buildReview() => Scaffold(
        backgroundColor: const Color(0xFF171615),
        body: SafeArea(
            child: Column(children: [
          const Padding(
              padding: EdgeInsets.all(18),
              child: Text('照片预览',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700))),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.memory(_capturedImage!,
                          fit: BoxFit.contain, width: double.infinity)))),
          if (ref.watch(cameraSessionProvider).photos.length > 1)
            SizedBox(
                height: 74,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: ref.watch(cameraSessionProvider).photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final photo =
                          ref.watch(cameraSessionProvider).photos[index];
                      return GestureDetector(
                          onTap: () {
                            ref
                                .read(cameraSessionProvider.notifier)
                                .select(index);
                            setState(() => _capturedImage = photo.bytes);
                          },
                          child: Stack(children: [
                            ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.memory(photo.bytes,
                                    width: 58, height: 58, fit: BoxFit.cover)),
                            if (index == 0)
                              const Positioned(
                                  left: 3,
                                  top: 3,
                                  child: DecoratedBox(
                                      decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(5))),
                                      child: Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 2),
                                          child: Text('最佳',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9)))))
                          ]));
                    })),
          Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
              child: Text(_compositionSuggestion,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Padding(
              padding: const EdgeInsets.all(22),
              child: Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => setState(() => _capturedImage = null),
                        child: const Text('重拍'))),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton.icon(
                        onPressed: () => context.go('/studio'),
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('进入工作室'))),
              ])),
        ])),
      );
}

class _FocusRing extends StatelessWidget {
  const _FocusRing();
  @override
  Widget build(BuildContext context) => Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
          border: Border.all(color: Colors.amber, width: 1.5),
          borderRadius: BorderRadius.circular(4)));
}

class _LevelIndicator extends StatelessWidget {
  const _LevelIndicator({required this.angle});
  final double angle;
  @override
  Widget build(BuildContext context) {
    final level = angle.abs() < 2.5;
    return Transform.rotate(
        angle: angle * math.pi / 180,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: level ? 86 : 58,
            height: 3,
            decoration: BoxDecoration(
                color: level ? Colors.amber : Colors.white70,
                borderRadius: BorderRadius.circular(99))));
  }
}

class _CameraTip extends StatelessWidget {
  const _CameraTip(
      {required this.zoom, required this.brightness, required this.suggestion});
  final double zoom;
  final double brightness;
  final String suggestion;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.black54, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child: Text(brightness < 58 ? '光线较暗，建议靠近光源或开启闪光灯' : suggestion,
                style: const TextStyle(color: Colors.white, fontSize: 12))),
        Text('${zoom.toStringAsFixed(1)}×',
            style: const TextStyle(color: Colors.white70, fontSize: 12))
      ]));
}

class _RoundAction extends StatelessWidget {
  const _RoundAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11))
          ])));
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.guide);
  final CompositionGuide guide;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .48)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    if (guide == CompositionGuide.thirds) {
      for (final x in [size.width / 3, size.width * 2 / 3]) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (final y in [size.height / 3, size.height * 2 / 3]) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else if (guide == CompositionGuide.center) {
      canvas.drawLine(Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height), paint);
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), paint);
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 44, paint);
    } else {
      canvas.drawLine(Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height), paint);
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.guide != guide;
}
