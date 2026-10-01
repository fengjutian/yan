import 'dart:async';
import 'dart:math' as math;

import 'package:ai_image_studio/features/camera/data/camera_session.dart';
import 'package:ai_image_studio/features/camera/data/camera_capabilities.dart';
import 'package:ai_image_studio/features/camera/data/face_analyzer.dart';
import 'package:ai_image_studio/features/camera/data/live_camera_analyzer.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        DeviceOrientation,
        HapticFeedback,
        MethodChannel,
        MissingPluginException,
        PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CompositionGuide { thirds, center, symmetry }

enum CameraStyle { standard, vivid, warm, cool, mono }

enum SmartShutterMode { off, smile, gesture }

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
  final String angle; // CameraAngle.name
}

class _CameraPageState extends ConsumerState<CameraPage>
    with WidgetsBindingObserver {
  static const _hardwareControls = MethodChannel('yan.camera/controls');
  final _picker = ImagePicker();
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  Uint8List? _capturedImage;
  bool _reviewing = false;
  CompositionGuide _guide = CompositionGuide.thirds;
  FlashMode _flashMode = FlashMode.off;
  bool _showGuide = true;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;
  int _countdownSeconds = 0;
  int _countdown = 0;
  bool _cancelCountdown = false;
  bool _continuousBurst = false;
  int _burstTaken = 0;
  double _baseZoom = 1;
  double _zoom = 1;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _exposure = 0;
  double _minExposure = 0;
  double _maxExposure = 0;
  double _levelAngle = 0;
  double _motionLevel = 0;
  (double, double, double)? _lastAcceleration;
  double _brightness = 128;
  List<double> _histogram = List<double>.filled(32, 0);
  double _highlightClipping = 0;
  double _shadowClipping = 0;
  bool _showHistogram = false;
  bool _showFocusPeaking = false;
  bool _lensCleaningHints = true;
  List<Offset> _focusPeaks = const [];
  double _clarityScore = 0;
  int _softFrameCount = 0;
  double _guidanceOpacity = 1;
  DateTime? _goodPoseSince;
  double _aspectRatio = 3 / 4;
  int _burstCount = 1;
  int _activeIndex = 0;
  int _initializationToken = 0;
  String _compositionSuggestion = '让主体靠近交叉点，画面会更有呼吸感';
  Offset? _focusPoint;
  StreamSubscription<AccelerometerEvent>? _motionSubscription;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  final LiveCameraAnalyzer _liveAnalyzer = LiveCameraAnalyzer();
  LiveCameraAnalysis? _liveAnalysis;
  bool _showRealtimeGuidance = true;
  bool _showCameraOptions = false;
  bool _shutterFlash = false;
  bool _focusLocked = false;
  bool _mirrorSelfies = true;
  bool _autoSave = false;
  bool _saveOriginalCopy = false;
  CameraStyle _style = CameraStyle.standard;
  SmartShutterMode _smartShutterMode = SmartShutterMode.off;
  int _smartSignalFrames = 0;
  DateTime _lastSmartCapture = DateTime.fromMillisecondsSinceEpoch(0);
  CameraCapabilities _capabilities = const CameraCapabilities.fallback();
  bool _permissionPermanentlyDenied = false;
  String? _processingStatus;
  double? _processingProgress;

  static const _aspectPreference = 'camera.aspect_ratio';
  static const _timerPreference = 'camera.timer_seconds';
  static const _guidePreference = 'camera.show_guide';
  static const _guidancePreference = 'camera.realtime_guidance';
  static const _mirrorPreference = 'camera.mirror_selfies';
  static const _autoSavePreference = 'camera.auto_save';
  static const _saveOriginalPreference = 'camera.save_original';
  static const _stylePreference = 'camera.photo_style';
  static const _histogramPreference = 'camera.show_histogram';
  static const _smartShutterPreference = 'camera.smart_shutter';
  static const _focusPeakingPreference = 'camera.focus_peaking';
  static const _lensHintsPreference = 'camera.lens_cleaning_hints';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motionSubscription =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 120),
        ).listen((event) {
          final angle = math.atan2(event.x, event.y) * 180 / math.pi;
          final previous = _lastAcceleration;
          _lastAcceleration = (event.x, event.y, event.z);
          final movement = previous == null
              ? 0.0
              : math.sqrt(
                  math.pow(event.x - previous.$1, 2) +
                      math.pow(event.y - previous.$2, 2) +
                      math.pow(event.z - previous.$3, 2),
                );
          if (mounted) {
            setState(() {
              _levelAngle = angle.clamp(-45, 45);
              _motionLevel = _motionLevel * .72 + movement * .28;
            });
          }
        }, onError: (_) {});
    _applyTemplateParams();
    unawaited(_activateHardwareControls());
    unawaited(_loadPreferences());
    unawaited(_loadCapabilities());
    unawaited(_loadCameras());
  }

  Future<void> _activateHardwareControls() async {
    _hardwareControls.setMethodCallHandler((call) async {
      if (call.method == 'shutter' && mounted) _handleShutterTap();
    });
    try {
      await _hardwareControls.invokeMethod<void>('setActive', true);
    } on MissingPluginException {
      // iOS and desktop currently use the on-screen shutter.
    } on PlatformException {
      // Hardware key integration is optional.
    }
  }

  Future<void> _deactivateHardwareControls() async {
    _hardwareControls.setMethodCallHandler(null);
    try {
      await _hardwareControls.invokeMethod<void>('setActive', false);
    } on MissingPluginException {
      // Optional platform integration.
    } on PlatformException {
      // Optional platform integration.
    }
  }

  Future<void> _loadCapabilities() async {
    final capabilities = await CameraCapabilitiesService().load();
    if (mounted) setState(() => _capabilities = capabilities);
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedAspect = preferences.getDouble(_aspectPreference);
    setState(() {
      if (savedAspect == 1 || savedAspect == .75 || savedAspect == .5625) {
        _aspectRatio = savedAspect!;
      }
      _countdownSeconds = preferences.getInt(_timerPreference) ?? 0;
      _showGuide = preferences.getBool(_guidePreference) ?? true;
      _showRealtimeGuidance = preferences.getBool(_guidancePreference) ?? true;
      _mirrorSelfies = preferences.getBool(_mirrorPreference) ?? true;
      _autoSave = preferences.getBool(_autoSavePreference) ?? false;
      _saveOriginalCopy = preferences.getBool(_saveOriginalPreference) ?? false;
      final styleIndex = preferences.getInt(_stylePreference) ?? 0;
      _style = CameraStyle
          .values[styleIndex.clamp(0, CameraStyle.values.length - 1)];
      _showHistogram = preferences.getBool(_histogramPreference) ?? false;
      final smartIndex = preferences.getInt(_smartShutterPreference) ?? 0;
      _smartShutterMode = SmartShutterMode
          .values[smartIndex.clamp(0, SmartShutterMode.values.length - 1)];
      _showFocusPeaking = preferences.getBool(_focusPeakingPreference) ?? false;
      _lensCleaningHints = preferences.getBool(_lensHintsPreference) ?? true;
    });
  }

  Future<void> _savePreference(String key, Object value) async {
    final preferences = await SharedPreferences.getInstance();
    switch (value) {
      case final bool boolean:
        await preferences.setBool(key, boolean);
      case final int integer:
        await preferences.setInt(key, integer);
      case final double number:
        await preferences.setDouble(key, number);
    }
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

  /// 当前模板携带的初始 prompt(供相机 UI 显示给用户看,
  /// 后续"用此图生成"时可直接注入到生成器)。
  String? get initialPrompt => _initialPrompt;

  Future<void> _loadCameras() async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
        _permissionPermanentlyDenied = false;
      });
    }
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
      _permissionPermanentlyDenied = _isPermissionError(error);
      _initializing = false;
      _controller = null;
    });
    // 失败路径的旧 controller 需要释放,否则 native camera HAL 句柄会泄漏。
    unawaited(stale?.dispose());
  }

  Future<void> _initializeCamera(int index) async {
    final token = ++_initializationToken;
    final previous = _controller;
    if (previous != null && mounted) {
      // 先把 UI 切到加载态，避免 dispose 的 await 期间出现
      // _initializing=false / _controller=null 的不一致窗口。
      setState(() {
        _initializing = true;
        _error = null;
        _permissionPermanentlyDenied = false;
        _controller = null;
      });
    }
    await previous?.dispose();
    if (!mounted) return;
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: preferredAnalysisFormat,
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
      if (!mounted || token != _initializationToken) {
        await controller.dispose();
        return;
      }
      _minZoom = await controller.getMinZoomLevel().timeout(
        const Duration(seconds: 3),
      );
      _maxZoom = await controller.getMaxZoomLevel().timeout(
        const Duration(seconds: 3),
      );
      _minExposure = await controller.getMinExposureOffset().timeout(
        const Duration(seconds: 3),
      );
      _maxExposure = await controller.getMaxExposureOffset().timeout(
        const Duration(seconds: 3),
      );
      _zoom = _minZoom;
      _flashMode = FlashMode.off;
      await controller
          .setFlashMode(_flashMode)
          .timeout(const Duration(seconds: 3));
      await _startLightMonitoring(controller);
      if (mounted && token == _initializationToken) {
        setState(() => _initializing = false);
      }
    } on CameraException catch (error) {
      if (token != _initializationToken) return;
      _handleCameraError(error);
    } on PlatformException catch (error) {
      if (token != _initializationToken) return;
      _handleCameraError(error);
    } on TimeoutException catch (_) {
      if (token != _initializationToken) return;
      _handleCameraError(CameraException('init-timeout', '相机初始化超时，请重试或重启应用'));
    } catch (error) {
      if (token != _initializationToken) return;
      _handleCameraError(error);
    }
  }

  Future<void> _startLightMonitoring(CameraController controller) async {
    try {
      await controller.startImageStream((image) {
        final now = DateTime.now();
        if (now.difference(_lastFrameAt).inMilliseconds < 260 ||
            image.planes.isEmpty) {
          return;
        }
        _lastFrameAt = now;
        final bytes = image.planes.first.bytes;
        var total = 0;
        var count = 0;
        var highlights = 0;
        var shadows = 0;
        final bins = List<int>.filled(32, 0);
        for (var index = 0; index < bytes.length; index += 80) {
          final luminance = bytes[index];
          total += luminance;
          bins[(luminance * bins.length ~/ 256).clamp(0, bins.length - 1)]++;
          if (luminance >= 245) highlights++;
          if (luminance <= 10) shadows++;
          count++;
        }
        if (mounted && count > 0) {
          final peak = bins.reduce((a, b) => a > b ? a : b);
          final detail = _analyzeSharpness(
            image,
            controller.description,
            controller.value.deviceOrientation,
          );
          setState(() {
            _brightness = total / count;
            _highlightClipping = highlights / count;
            _shadowClipping = shadows / count;
            _histogram = peak == 0
                ? List<double>.filled(bins.length, 0)
                : bins.map((value) => value / peak).toList(growable: false);
            _clarityScore = detail.clarity;
            _focusPeaks = _showFocusPeaking ? detail.peaks : const [];
            final normallyLit = _brightness >= 60 && _brightness <= 215;
            if (_lensCleaningHints && normallyLit && detail.clarity < 6) {
              _softFrameCount = _softFrameCount >= 12
                  ? 12
                  : _softFrameCount + 1;
            } else {
              _softFrameCount = _softFrameCount <= 2 ? 0 : _softFrameCount - 2;
            }
          });
        }
        if (_showRealtimeGuidance) {
          unawaited(
            _analyzeFrame(
              image,
              controller.description,
              controller.value.deviceOrientation,
            ),
          );
        }
      });
    } catch (_) {
      // 部分 Android 设备无法同时绑定预览、拍照和图像分析三个
      // CameraX use case。实时分析属于增强能力，绑定失败时保留
      // 已经可用的预览与拍照，不让整个相机页面进入错误状态。
      if (mounted) {
        setState(() {
          _showRealtimeGuidance = false;
          _showHistogram = false;
          _liveAnalysis = null;
          _histogram = const [];
          _focusPeaks = const [];
        });
      }
    }
  }

  _FrameSharpness _analyzeSharpness(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    if (image.planes.isEmpty || image.width < 20 || image.height < 20) {
      return const _FrameSharpness(clarity: 0, peaks: []);
    }
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final rowStride = plane.bytesPerRow;
    const step = 12;
    var edgeTotal = 0.0;
    var samples = 0;
    final peaks = <Offset>[];

    int luminanceAt(int x, int y) {
      final index = y * rowStride + x * pixelStride;
      if (index < 0 || index >= bytes.length) return 0;
      if (pixelStride >= 3 && index + 2 < bytes.length) {
        return (.114 * bytes[index] +
                .587 * bytes[index + 1] +
                .299 * bytes[index + 2])
            .round();
      }
      return bytes[index];
    }

    for (var y = step; y < image.height - step; y += step) {
      for (var x = step; x < image.width - step; x += step) {
        final center = luminanceAt(x, y);
        final gradient =
            (center - luminanceAt(x + step, y)).abs() +
            (center - luminanceAt(x, y + step)).abs();
        edgeTotal += gradient;
        samples++;
        if (gradient > 58 && peaks.length < 420) {
          peaks.add(
            _rotateAnalysisPoint(
              Offset(x / image.width, y / image.height),
              camera,
              orientation,
            ),
          );
        }
      }
    }
    return _FrameSharpness(
      clarity: samples == 0 ? 0 : edgeTotal / samples,
      peaks: peaks,
    );
  }

  Offset _rotateAnalysisPoint(
    Offset point,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    const deviceDegrees = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final device = deviceDegrees[orientation] ?? 0;
    final rotation = camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + device) % 360
        : (camera.sensorOrientation - device + 360) % 360;
    var result = switch (rotation) {
      90 => Offset(1 - point.dy, point.dx),
      180 => Offset(1 - point.dx, 1 - point.dy),
      270 => Offset(point.dy, 1 - point.dx),
      _ => point,
    };
    if (camera.lensDirection == CameraLensDirection.front) {
      result = Offset(1 - result.dx, result.dy);
    }
    return result;
  }

  Future<void> _analyzeFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) async {
    final result = await _liveAnalyzer.process(
      image,
      camera,
      deviceOrientation,
    );
    if (!mounted || result == null || !_showRealtimeGuidance) return;
    final goodPose = result.suggestion.startsWith('姿态很好');
    final now = DateTime.now();
    if (goodPose) {
      _goodPoseSince ??= now;
    } else {
      _goodPoseSince = null;
    }
    setState(() {
      _liveAnalysis = result;
      _compositionSuggestion = result.suggestion;
      _guidanceOpacity =
          goodPose && now.difference(_goodPoseSince!).inMilliseconds > 1800
          ? 0
          : 1;
    });
    _handleSmartShutter(result);
  }

  void _handleSmartShutter(LiveCameraAnalysis analysis) {
    final detected = switch (_smartShutterMode) {
      SmartShutterMode.off => false,
      SmartShutterMode.smile => analysis.smileDetected,
      SmartShutterMode.gesture => analysis.gestureDetected,
    };
    _smartSignalFrames = detected ? _smartSignalFrames + 1 : 0;
    if (_smartSignalFrames < 3 || _capturing) return;
    final now = DateTime.now();
    if (now.difference(_lastSmartCapture) < const Duration(seconds: 6)) return;
    _smartSignalFrames = 0;
    _lastSmartCapture = now;
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_capture());
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

  Future<void> _setFlashMode(FlashMode mode) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(mode);
      if (mounted) setState(() => _flashMode = mode);
    } on CameraException {
      if (mounted) _showMessage('当前设备不支持此闪光灯模式');
    }
  }

  Future<void> _capture({bool continuous = false}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    _cancelCountdown = false;
    setState(() {
      _capturing = true;
      _burstTaken = 0;
      _processingStatus = _countdownSeconds > 0 && !continuous ? '准备拍摄' : '拍摄中';
      _processingProgress = 0;
    });
    unawaited(HapticFeedback.mediumImpact());
    try {
      final timerSeconds = continuous ? 0 : _countdownSeconds;
      for (var value = timerSeconds; value > 0; value--) {
        if (!mounted) return;
        setState(() => _countdown = value);
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_cancelCountdown) return;
      }
      if (mounted) setState(() => _countdown = 0);
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final values = <Uint8List>[];
      Uint8List? firstOriginal;
      XFile? analysisFile;
      // Keep a conservative cap to avoid high-resolution JPEGs exhausting
      // memory on mid-range Android devices.
      final requestedCount = continuous ? 8 : _burstCount;
      for (var index = 0; index < requestedCount; index++) {
        if (continuous && !_continuousBurst && index > 0) break;
        if (mounted) {
          setState(() {
            _shutterFlash = true;
            _processingStatus = '拍摄中 ${index + 1}/$requestedCount';
            _processingProgress = index / requestedCount;
          });
        }
        final file = await controller.takePicture();
        if (mounted) setState(() => _shutterFlash = false);
        analysisFile ??= file;
        final bytes = await file.readAsBytes();
        firstOriginal ??= bytes;
        final mirror =
            _mirrorSelfies &&
            controller.description.lensDirection == CameraLensDirection.front;
        values.add(
          await compute(_processPhoto, (
            bytes,
            _aspectRatio,
            mirror,
            _style.index,
          )),
        );
        if (mounted) {
          setState(() {
            _burstTaken = values.length;
            _processingProgress = values.length / requestedCount;
          });
        }
        if (index + 1 < requestedCount) {
          await Future<void>.delayed(
            Duration(milliseconds: continuous ? 120 : 220),
          );
        }
      }
      if (mounted && values.isNotEmpty) {
        setState(() => _capturedImage = values.first);
      }
      if (_autoSave && values.isNotEmpty) {
        unawaited(_saveToGallery(values.first, suffix: 'styled'));
        if (_saveOriginalCopy && firstOriginal != null) {
          unawaited(_saveToGallery(firstOriginal, suffix: 'original'));
        }
      }
      if (mounted) {
        setState(() {
          _processingStatus = '正在评选最佳照片';
          _processingProgress = 0;
        });
      }
      await ref
          .read(cameraSessionProvider.notifier)
          .setPhotos(
            values,
            onProgress: (progress) {
              if (mounted) setState(() => _processingProgress = progress);
            },
          );
      final session = ref.read(cameraSessionProvider);
      final size = controller.value.previewSize;
      if (analysisFile != null && size != null) {
        if (mounted) setState(() => _processingStatus = '正在分析构图');
        final analysis = await analyzeFaces(
          analysisFile.path,
          size.width.round(),
          size.height.round(),
        );
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
      if (mounted) {
        setState(() {
          _capturing = false;
          _shutterFlash = false;
          _countdown = 0;
          _continuousBurst = false;
          _processingStatus = null;
          _processingProgress = null;
        });
      }
      if (controller.value.isInitialized &&
          !controller.value.isStreamingImages) {
        await _startLightMonitoring(controller);
      }
    }
  }

  void _handleShutterTap() {
    if (_countdown > 0) {
      _cancelCountdown = true;
      setState(() => _countdown = 0);
      return;
    }
    unawaited(_capture());
  }

  void _startContinuousBurst() {
    if (_capturing) return;
    setState(() => _continuousBurst = true);
    unawaited(HapticFeedback.heavyImpact());
    unawaited(_capture(continuous: true));
  }

  void _stopContinuousBurst() {
    if (!_continuousBurst) return;
    setState(() => _continuousBurst = false);
  }

  Future<void> _saveToGallery(
    Uint8List bytes, {
    String suffix = 'photo',
  }) async {
    try {
      final result = await SaverGallery.saveImage(
        bytes,
        fileName: 'yan-camera-$suffix-${DateTime.now().millisecondsSinceEpoch}',
        albumPath: 'Yan',
        skipIfExists: false,
      );
      if (!result.isSuccess && mounted) {
        _showMessage('保存到系统相册失败：${result.errorMessage ?? '请检查照片权限'}');
      }
    } catch (_) {
      if (mounted) _showMessage('保存到系统相册失败，请检查照片权限');
    }
  }

  Future<void> _importPhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref.read(cameraSessionProvider.notifier).setPhotos([bytes]);
    if (mounted) setState(() => _capturedImage = bytes);
  }

  Future<void> _focus(
    TapDownDetails details,
    BoxConstraints constraints, {
    bool keepVisible = false,
  }) async {
    final controller = _controller;
    if (controller == null) return;
    final point = Offset(
      (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );
    try {
      await controller.setFocusMode(
        keepVisible ? FocusMode.locked : FocusMode.auto,
      );
      await controller.setExposureMode(
        keepVisible ? ExposureMode.locked : ExposureMode.auto,
      );
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
      setState(() {
        _focusPoint = details.localPosition;
        _focusLocked = keepVisible;
      });
      if (keepVisible) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted && !_focusLocked) setState(() => _focusPoint = null);
    } on CameraException {
      /* Device does not support manual focus. */
    }
  }

  Future<void> _lockFocus(
    LongPressStartDetails details,
    BoxConstraints constraints,
  ) async {
    await _focus(
      TapDownDetails(localPosition: details.localPosition),
      constraints,
      keepVisible: true,
    );
    if (!mounted) return;
    unawaited(HapticFeedback.selectionClick());
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      unawaited(_setZoom(details.scale));
      return;
    }
    if (_focusPoint == null || details.focalPointDelta.dy == 0) return;
    final range = (_maxExposure - _minExposure).abs();
    final next = _exposure - details.focalPointDelta.dy / 240 * range;
    unawaited(_setExposure(next.clamp(_minExposure, _maxExposure)));
  }

  Future<void> _setZoomLevel(double value) async {
    final controller = _controller;
    if (controller == null) return;
    final next = value.clamp(_minZoom, _maxZoom).toDouble();
    try {
      await controller.setZoomLevel(next);
      if (mounted) setState(() => _zoom = next);
    } on CameraException catch (_) {
      // Device does not support the requested continuous zoom value.
    } on PlatformException catch (_) {
      // Some vendor camera implementations reject individual zoom values.
    }
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
    } on PlatformException catch (_) {
      /* 同上 */
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );

  String _cameraError(Object error) {
    final details = error.toString();
    if (details.contains('No supported surface combination') ||
        details.contains('UseCaseAdapter') ||
        details.contains('bind too many use cases')) {
      return '当前设备无法同时启用实时分析与拍照，请重试；应用会自动使用兼容模式。';
    }
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

  bool _isPermissionError(Object error) {
    if (error is CameraException) {
      return error.code == 'CameraAccessDenied' ||
          error.code == 'CameraAccessDeniedWithoutPrompt' ||
          error.code == 'CameraAccessRestricted';
    }
    if (error is PlatformException) {
      return error.code == 'CameraAccessDenied' ||
          error.code == 'camera_permission';
    }
    return false;
  }

  Future<void> _openSystemSettings() async {
    final opened = await CameraCapabilitiesService().openAppSettings();
    if (!opened && mounted) _showMessage('无法打开系统设置，请手动前往应用权限设置');
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
    _initializationToken++;
    WidgetsBinding.instance.removeObserver(this);
    _motionSubscription?.cancel();
    unawaited(_liveAnalyzer.close());
    unawaited(_deactivateHardwareControls());
    final controller = _controller;
    _controller = null; // 先置 null,避免 didChangeAppLifecycleState 二次 dispose
    unawaited(controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reviewing && _capturedImage != null) return _buildReview();
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.black,
      body: landscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
    );
  }

  Widget _buildPortraitLayout() => Stack(
    fit: StackFit.expand,
    children: [
      _buildCameraViewport(),
      Align(
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: SafeArea(bottom: false, child: _buildTopBar()),
        ),
      ),
      if (_templateId != null)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 62,
          left: 0,
          right: 0,
          child: _TemplateChip(
            templateId: _templateId!,
            initialPrompt: _initialPrompt,
          ),
        ),
      Positioned(
        top: MediaQuery.paddingOf(context).top + 62,
        left: 0,
        right: 0,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _showCameraOptions
              ? _buildCameraOptions(maxHeight: 230)
              : const SizedBox.shrink(),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
          child: SafeArea(top: false, child: _buildControls()),
        ),
      ),
    ],
  );

  Widget _buildLandscapeLayout() => Stack(
    fit: StackFit.expand,
    children: [
      _buildCameraViewport(),
      Align(
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: SafeArea(bottom: false, child: _buildTopBar()),
        ),
      ),
      if (_templateId != null)
        Positioned(
          left: MediaQuery.paddingOf(context).left + 10,
          top: MediaQuery.paddingOf(context).top + 62,
          child: _TemplateChip(
            templateId: _templateId!,
            initialPrompt: _initialPrompt,
          ),
        ),
      if (_showCameraOptions)
        Positioned(
          left: MediaQuery.paddingOf(context).left + 10,
          top: MediaQuery.paddingOf(context).top + 62,
          width: 360,
          child: _buildCameraOptions(maxHeight: 220),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: SafeArea(
          left: false,
          child: SizedBox(
            width: 220,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: SingleChildScrollView(
                child: _buildControls(compact: true),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildCameraViewport() => ClipRect(child: _buildPreview());

  Widget _buildTopBar() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
    child: Row(
      children: [
        IconButton(
          tooltip: '关闭',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
        IconButton(
          tooltip: '闪光灯',
          onPressed: _toggleFlash,
          icon: Icon(_flashIcon, color: Colors.white),
        ),
        const Spacer(),
        _CameraCircleButton(
          tooltip: '相机设置',
          onTap: () => setState(() => _showCameraOptions = !_showCameraOptions),
          icon: _showCameraOptions
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
        ),
        const Spacer(),
        IconButton(
          tooltip: '实时姿态指导',
          onPressed: () => setState(() {
            _showRealtimeGuidance = !_showRealtimeGuidance;
            if (!_showRealtimeGuidance) _liveAnalysis = null;
            _guidanceOpacity = 1;
            _goodPoseSince = null;
            unawaited(
              _savePreference(_guidancePreference, _showRealtimeGuidance),
            );
          }),
          icon: Icon(
            _showRealtimeGuidance
                ? Icons.accessibility_new
                : Icons.accessibility_new_outlined,
            color: _showRealtimeGuidance
                ? const Color(0xFFFFD60A)
                : Colors.white70,
          ),
        ),
        IconButton(
          tooltip: '构图线',
          onPressed: () => setState(() {
            _showGuide = !_showGuide;
            unawaited(_savePreference(_guidePreference, _showGuide));
          }),
          icon: Icon(
            Icons.grid_3x3,
            color: _showGuide ? const Color(0xFFFFD60A) : Colors.white70,
          ),
        ),
      ],
    ),
  );

  Widget _buildCameraOptions({required double maxHeight}) => Container(
    key: const ValueKey('camera-options'),
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    constraints: BoxConstraints(maxHeight: maxHeight),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(18),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CapabilitySummary(capabilities: _capabilities),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ratio in const [
                ('1:1', 1.0),
                ('4:3', .75),
                ('16:9', .5625),
              ])
                _CameraOption(
                  label: ratio.$1,
                  selected: _aspectRatio == ratio.$2,
                  onTap: () => setState(() {
                    _aspectRatio = ratio.$2;
                    unawaited(_savePreference(_aspectPreference, _aspectRatio));
                  }),
                ),
              for (final seconds in const [0, 3, 5, 10])
                _CameraOption(
                  label: seconds == 0 ? '定时关闭' : '$seconds 秒',
                  icon: seconds == 0
                      ? Icons.timer_off_outlined
                      : Icons.timer_outlined,
                  selected: _countdownSeconds == seconds,
                  onTap: () => setState(() {
                    _countdownSeconds = seconds;
                    unawaited(_savePreference(_timerPreference, seconds));
                  }),
                ),
              for (final option in const [
                ('闪光关', FlashMode.off, Icons.flash_off),
                ('闪光自动', FlashMode.auto, Icons.flash_auto),
                ('闪光开', FlashMode.always, Icons.flash_on),
              ])
                _CameraOption(
                  label: option.$1,
                  icon: option.$3,
                  selected: _flashMode == option.$2,
                  onTap: () => _setFlashMode(option.$2),
                ),
              _CameraOption(
                label: _guideName,
                icon: Icons.grid_3x3,
                selected: _showGuide,
                onTap: () => setState(() {
                  _showGuide = true;
                  _guide =
                      CompositionGuide.values[(_guide.index + 1) %
                          CompositionGuide.values.length];
                  unawaited(_savePreference(_guidePreference, true));
                }),
              ),
              _CameraOption(
                label: '曝光归零',
                icon: Icons.exposure_zero,
                selected: _exposure.abs() < .05,
                onTap: () => _setExposure(0),
              ),
              _CameraOption(
                label: '直方图',
                icon: Icons.bar_chart,
                selected: _showHistogram,
                onTap: () => setState(() {
                  _showHistogram = !_showHistogram;
                  unawaited(
                    _savePreference(_histogramPreference, _showHistogram),
                  );
                }),
              ),
              _CameraOption(
                label: '峰值对焦',
                icon: Icons.center_focus_strong,
                selected: _showFocusPeaking,
                onTap: () => setState(() {
                  _showFocusPeaking = !_showFocusPeaking;
                  if (!_showFocusPeaking) _focusPeaks = const [];
                  unawaited(
                    _savePreference(_focusPeakingPreference, _showFocusPeaking),
                  );
                }),
              ),
              _CameraOption(
                label: '镜头清洁提醒',
                icon: Icons.cleaning_services_outlined,
                selected: _lensCleaningHints,
                onTap: () => setState(() {
                  _lensCleaningHints = !_lensCleaningHints;
                  _softFrameCount = 0;
                  unawaited(
                    _savePreference(_lensHintsPreference, _lensCleaningHints),
                  );
                }),
              ),
              for (final option in const [
                ('智能快门关', SmartShutterMode.off, Icons.touch_app_outlined),
                ('笑脸快门', SmartShutterMode.smile, Icons.sentiment_satisfied_alt),
                ('举手快门', SmartShutterMode.gesture, Icons.back_hand_outlined),
              ])
                _CameraOption(
                  label: option.$1,
                  icon: option.$3,
                  selected: _smartShutterMode == option.$2,
                  onTap: () => setState(() {
                    _smartShutterMode = option.$2;
                    _smartSignalFrames = 0;
                    unawaited(
                      _savePreference(
                        _smartShutterPreference,
                        _smartShutterMode.index,
                      ),
                    );
                  }),
                ),
              _CameraOption(
                label: '镜像自拍',
                icon: Icons.flip,
                selected: _mirrorSelfies,
                onTap: () => setState(() {
                  _mirrorSelfies = !_mirrorSelfies;
                  unawaited(_savePreference(_mirrorPreference, _mirrorSelfies));
                }),
              ),
              for (final option in const [
                ('标准', CameraStyle.standard),
                ('鲜明', CameraStyle.vivid),
                ('暖色', CameraStyle.warm),
                ('冷色', CameraStyle.cool),
                ('黑白', CameraStyle.mono),
              ])
                _CameraOption(
                  label: option.$1,
                  icon: Icons.filter_vintage_outlined,
                  selected: _style == option.$2,
                  onTap: () => setState(() {
                    _style = option.$2;
                    unawaited(_savePreference(_stylePreference, _style.index));
                  }),
                ),
              _CameraOption(
                label: '自动存相册',
                icon: Icons.save_alt,
                selected: _autoSave,
                onTap: () => setState(() {
                  _autoSave = !_autoSave;
                  unawaited(_savePreference(_autoSavePreference, _autoSave));
                }),
              ),
              _CameraOption(
                label: '同时保存原图',
                icon: Icons.photo_library_outlined,
                selected: _saveOriginalCopy,
                onTap: () => setState(() {
                  _saveOriginalCopy = !_saveOriginalCopy;
                  unawaited(
                    _savePreference(_saveOriginalPreference, _saveOriginalCopy),
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildPreview() {
    // _initializing 和 _controller 必须联动:前者 true 时后者允许为 null,
    // 但反过来不应出现 _initializing==false 且 _controller==null 的窗口。
    // 这里兜底一次,避免任何遗漏路径触发 NPE。
    if (_error != null) {
      return ColoredBox(
        color: const Color(0xFF242220),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  color: Colors.white70,
                  size: 45,
                ),
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: _permissionPermanentlyDenied
                      ? _openSystemSettings
                      : _loadCameras,
                  child: Text(_permissionPermanentlyDenied ? '前往系统设置' : '重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_initializing || _controller == null) {
      return const ColoredBox(
        color: Color(0xFF242220),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final controller = _controller!;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onTapDown: (details) => _focus(details, constraints),
        onDoubleTap: _switchCamera,
        onLongPressStart: (details) => _lockFocus(details, constraints),
        onScaleStart: (_) => _baseZoom = _zoom,
        onScaleUpdate: _handleScaleUpdate,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CroppedCameraPreview(controller: controller, style: _style),
            if (_showRealtimeGuidance &&
                _liveAnalysis?.landmarks.isNotEmpty == true)
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _guidanceOpacity,
                  duration: const Duration(milliseconds: 450),
                  child: CustomPaint(
                    painter: _PosePainter(_liveAnalysis!.landmarks),
                  ),
                ),
              ),
            if (_showGuide)
              IgnorePointer(child: CustomPaint(painter: _GuidePainter(_guide))),
            if (_showFocusPeaking && _focusPeaks.isNotEmpty)
              IgnorePointer(
                child: CustomPaint(painter: _FocusPeakingPainter(_focusPeaks)),
              ),
            if (_focusPoint != null)
              Positioned(
                left: _focusPoint!.dx - 25,
                top: _focusPoint!.dy - 25,
                child: IgnorePointer(child: _FocusRing(locked: _focusLocked)),
              ),
            if (_countdown > 0)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_countdown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 92,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _handleShutterTap,
                      icon: const Icon(Icons.close, color: Colors.white),
                      label: const Text(
                        '取消',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              top: 15,
              left: 0,
              right: 0,
              child: Center(child: _LevelIndicator(angle: _levelAngle)),
            ),
            if (_lensCleaningHints && _softFrameCount >= 8)
              Positioned(
                top: 34,
                left: 70,
                right: 70,
                child: _LensCleaningHint(clarity: _clarityScore),
              ),
            if (_processingStatus != null && _countdown == 0)
              Positioned(
                left: 22,
                right: 22,
                bottom: 76,
                child: _CaptureProgress(
                  label: _processingStatus!,
                  progress: _processingProgress,
                ),
              ),
            if (_showRealtimeGuidance && _liveAnalysis != null)
              Positioned(
                top: 40,
                left: 14,
                child: _SceneChip(
                  scene: _liveAnalysis!.scene,
                  confidence: _liveAnalysis!.sceneConfidence,
                ),
              ),
            if (_showHistogram)
              Positioned(
                right: 12,
                top: 42,
                child: _HistogramOverlay(
                  values: _histogram,
                  highlightClipping: _highlightClipping,
                  shadowClipping: _shadowClipping,
                ),
              ),
            if (_smartShutterMode != SmartShutterMode.off &&
                ((_smartShutterMode == SmartShutterMode.smile &&
                        _liveAnalysis?.smileDetected == true) ||
                    (_smartShutterMode == SmartShutterMode.gesture &&
                        _liveAnalysis?.gestureDetected == true)))
              Positioned(
                left: 14,
                top: 72,
                child: _SmartShutterChip(
                  label: _smartShutterMode == SmartShutterMode.smile
                      ? '保持微笑'
                      : '已识别举手',
                ),
              ),
            Positioned(
              bottom: 18,
              left: 18,
              right: 18,
              child: AnimatedOpacity(
                opacity: _brightness < 58 ? 1 : _guidanceOpacity,
                duration: const Duration(milliseconds: 450),
                child: _CameraTip(
                  zoom: _zoom,
                  brightness: _brightness,
                  motionLevel: _motionLevel,
                  suggestion: _compositionSuggestion,
                ),
              ),
            ),
            if (_shutterFlash)
              const Positioned.fill(
                child: IgnorePointer(child: ColoredBox(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls({bool compact = false}) => Padding(
    padding: EdgeInsets.fromLTRB(
      compact ? 10 : 24,
      compact ? 4 : 10,
      compact ? 10 : 24,
      compact ? 8 : 16,
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CameraModeLabel(
              label: '单拍',
              selected: _burstCount == 1,
              onTap: () => setState(() => _burstCount = 1),
            ),
            const SizedBox(width: 30),
            _CameraModeLabel(
              label: '连拍',
              selected: _burstCount == 5,
              onTap: () => setState(() => _burstCount = 5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ZoomSelector(
          zoom: _zoom,
          minZoom: _minZoom,
          maxZoom: _maxZoom,
          onSelected: (value) {
            unawaited(_setZoomLevel(value));
          },
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _CameraThumbnail(
              bytes: _capturedImage,
              onTap: _capturedImage == null
                  ? _importPhoto
                  : () => setState(() => _reviewing = true),
            ),
            GestureDetector(
              onTap: _handleShutterTap,
              onLongPressStart: (_) => _startContinuousBurst(),
              onLongPressEnd: (_) => _stopContinuousBurst(),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: _continuousBurst ? 70 : 78,
                    height: _continuousBurst ? 70 : 78,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _continuousBurst
                            ? const Color(0xFFFFD60A)
                            : _capturing
                            ? Colors.white38
                            : Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  if (_continuousBurst || _burstTaken > 1)
                    Positioned(
                      top: -22,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD60A),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            '$_burstTaken',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _RoundAction(
              icon: Icons.cameraswitch_rounded,
              label: '翻转',
              onTap: _switchCamera,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildReview() => Scaffold(
    backgroundColor: const Color(0xFF171615),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              '照片预览',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.memory(
                  _capturedImage!,
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
              ),
            ),
          ),
          if (ref.watch(cameraSessionProvider).photos.length > 1)
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                itemCount: ref.watch(cameraSessionProvider).photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final photo = ref.watch(cameraSessionProvider).photos[index];
                  return GestureDetector(
                    onTap: () {
                      ref.read(cameraSessionProvider.notifier).select(index);
                      setState(() => _capturedImage = photo.bytes);
                    },
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.memory(
                            photo.bytes,
                            width: 58,
                            height: 58,
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (index == 0)
                          const Positioned(
                            left: 3,
                            top: 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(5),
                                ),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                child: Text(
                                  '最佳',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
            child: Text(
              _compositionSuggestion,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _retake,
                    child: const Text('重拍'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.go('/studio'),
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('进入工作室'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _retake() async {
    if (mounted) {
      setState(() {
        _capturedImage = null;
        _reviewing = false;
      });
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isStreamingImages) {
      await _startLightMonitoring(controller);
    }
  }
}

class _FrameSharpness {
  const _FrameSharpness({required this.clarity, required this.peaks});

  final double clarity;
  final List<Offset> peaks;
}

Uint8List _processPhoto((Uint8List, double, bool, int) input) {
  final decoded = img.decodeImage(input.$1);
  if (decoded == null) return input.$1;
  var image = img.bakeOrientation(decoded);
  if (input.$3) image = img.flipHorizontal(image);
  final target = input.$2;
  final current = image.width / image.height;
  var width = image.width;
  var height = image.height;
  if (current > target) {
    width = (height * target).round();
  } else {
    height = (width / target).round();
  }
  var cropped = img.copyCrop(
    image,
    x: (image.width - width) ~/ 2,
    y: (image.height - height) ~/ 2,
    width: width,
    height: height,
  );
  final style =
      CameraStyle.values[input.$4.clamp(0, CameraStyle.values.length - 1)];
  switch (style) {
    case CameraStyle.standard:
      break;
    case CameraStyle.vivid:
      cropped = img.adjustColor(cropped, saturation: 1.22, contrast: 1.08);
    case CameraStyle.warm:
      for (final pixel in cropped) {
        pixel.r = (pixel.r * 1.05 + 4).clamp(0, 255);
        pixel.b = (pixel.b * .94).clamp(0, 255);
      }
    case CameraStyle.cool:
      for (final pixel in cropped) {
        pixel.r = (pixel.r * .95).clamp(0, 255);
        pixel.b = (pixel.b * 1.06 + 3).clamp(0, 255);
      }
    case CameraStyle.mono:
      cropped = img.grayscale(cropped);
  }
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
}

class _CroppedCameraPreview extends StatelessWidget {
  const _CroppedCameraPreview({required this.controller, required this.style});

  final CameraController controller;
  final CameraStyle style;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    final preview = FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.height,
        height: size.width,
        child: CameraPreview(controller),
      ),
    );
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_styleMatrix(style)),
      child: preview,
    );
  }
}

List<double> _styleMatrix(CameraStyle style) => switch (style) {
  CameraStyle.standard => const [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  CameraStyle.vivid => const [
    1.16,
    -.08,
    -.08,
    0,
    0,
    -.08,
    1.16,
    -.08,
    0,
    0,
    -.08,
    -.08,
    1.16,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  CameraStyle.warm => const [
    1.06,
    0,
    0,
    0,
    4,
    0,
    1.01,
    0,
    0,
    1,
    0,
    0,
    .94,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  CameraStyle.cool => const [
    .95,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1.06,
    0,
    3,
    0,
    0,
    0,
    1,
    0,
  ],
  CameraStyle.mono => const [
    .299,
    .587,
    .114,
    0,
    0,
    .299,
    .587,
    .114,
    0,
    0,
    .299,
    .587,
    .114,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
};

class _FocusRing extends StatelessWidget {
  const _FocusRing({required this.locked});
  final bool locked;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.amber, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      if (locked)
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Text(
            '自动曝光/自动对焦锁定',
            style: TextStyle(color: Colors.amber, fontSize: 9),
          ),
        ),
    ],
  );
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
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _CameraTip extends StatelessWidget {
  const _CameraTip({
    required this.zoom,
    required this.brightness,
    required this.motionLevel,
    required this.suggestion,
  });
  final double zoom;
  final double brightness;
  final double motionLevel;
  final String suggestion;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            brightness < 58 && motionLevel > .45
                ? '低光环境请保持手机稳定，正在等待更清晰的拍摄时机'
                : brightness < 58
                ? '光线较暗，建议靠近光源或开启闪光灯'
                : suggestion,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        Text(
          '${zoom.toStringAsFixed(1)}×',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );
}

class _CaptureProgress extends StatelessWidget {
  const _CaptureProgress({required this.label, required this.progress});

  final String label;
  final double? progress;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFFD60A),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress!.clamp(0, 1),
              minHeight: 3,
              color: const Color(0xFFFFD60A),
              backgroundColor: Colors.white24,
            ),
          ],
        ],
      ),
    ),
  );
}

class _HistogramOverlay extends StatelessWidget {
  const _HistogramOverlay({
    required this.values,
    required this.highlightClipping,
    required this.shadowClipping,
  });

  final List<double> values;
  final double highlightClipping;
  final double shadowClipping;

  @override
  Widget build(BuildContext context) {
    final warning = highlightClipping > .08
        ? '高光溢出'
        : shadowClipping > .22
        ? '暗部丢失'
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 112,
              height: 46,
              child: CustomPaint(painter: _HistogramPainter(values)),
            ),
            if (warning != null)
              Text(
                warning,
                style: const TextStyle(
                  color: Color(0xFFFFD60A),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  const _HistogramPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .88)
      ..style = PaintingStyle.fill;
    final barWidth = size.width / values.length;
    for (var index = 0; index < values.length; index++) {
      final height = values[index].clamp(0, 1) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(
          index * barWidth,
          size.height - height,
          math.max(1, barWidth - .5),
          height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values);
}

class _FocusPeakingPainter extends CustomPainter {
  const _FocusPeakingPainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF2D55).withValues(alpha: .88)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final point in points) {
      final center = Offset(point.dx * size.width, point.dy * size.height);
      canvas.drawLine(
        center.translate(-2.2, 0),
        center.translate(2.2, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FocusPeakingPainter oldDelegate) =>
      !listEquals(points, oldDelegate.points);
}

class _LensCleaningHint extends StatelessWidget {
  const _LensCleaningHint({required this.clarity});

  final double clarity;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.cleaning_services_outlined,
            color: Color(0xFFFFD60A),
            size: 14,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '画面持续偏糊，请检查并清洁镜头',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({required this.templateId, this.initialPrompt});
  final String templateId;
  final String? initialPrompt;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              initialPrompt == null || initialPrompt!.isEmpty
                  ? '模板 $templateId · 已应用构图线'
                  : '模板 $templateId · 初始描述已就绪',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraCircleButton extends StatelessWidget {
  const _CameraCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0xFF2C2C2E),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 23),
      ),
    ),
  );
}

class _CapabilitySummary extends StatelessWidget {
  const _CapabilitySummary({required this.capabilities});

  final CameraCapabilities capabilities;

  static const _labels = <String, String>{
    'front': '前摄',
    'back': '后摄',
    'wide': '广角',
    'ultra-wide': '超广角',
    'telephoto': '长焦',
    'true-depth': '深感',
    'multi-lens': '多镜头',
    'external': '外接',
    'auto': '自动增强',
    'portrait': '人像',
    'retouch': '美颜',
    'hdr': 'HDR',
    'night': '夜景',
  };

  @override
  Widget build(BuildContext context) {
    final features = <String>[
      ...capabilities.lensTypes.map((item) => _labels[item] ?? item),
      ...capabilities.extensionModes.map((item) => _labels[item] ?? item),
      if (capabilities.hasFlash) '闪光灯',
      if (capabilities.supportsMultiCamera) '多摄协同',
    ];
    return Row(
      children: [
        Icon(
          capabilities.platform == 'ios' ? Icons.apple : Icons.android,
          color: Colors.white70,
          size: 16,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            features.isEmpty ? '正在检测设备相机能力' : features.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _CameraOption extends StatelessWidget {
  const _CameraOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(99),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? Colors.white : const Color(0xFF303033),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: selected ? Colors.black : Colors.white70,
              size: 15,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CameraModeLabel extends StatelessWidget {
  const _CameraModeLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFFFFD60A) : Colors.white70,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: .5,
        ),
      ),
    ),
  );
}

class _ZoomSelector extends StatelessWidget {
  const _ZoomSelector({
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.onSelected,
  });

  final double zoom;
  final double minZoom;
  final double maxZoom;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final candidates = <double>{
      minZoom,
      1,
      if (maxZoom >= 2) 2,
      if (maxZoom >= 3) 3,
    }.where((value) => value >= minZoom && value <= maxZoom).toList()..sort();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final value in candidates)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkResponse(
              onTap: () => onSelected(value),
              radius: 25,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: (zoom - value).abs() < .08 ? 42 : 34,
                height: (zoom - value).abs() < .08 ? 42 : 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (zoom - value).abs() < .08
                      ? const Color(0xFFFFD60A)
                      : const Color(0xFF2C2C2E),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}×',
                  style: TextStyle(
                    color: (zoom - value).abs() < .08
                        ? Colors.black
                        : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CameraThumbnail extends StatelessWidget {
  const _CameraThumbnail({required this.bytes, required this.onTap});

  final Uint8List? bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: 54,
      height: 54,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: bytes == null
          ? const Icon(
              Icons.photo_library_outlined,
              color: Colors.white,
              size: 24,
            )
          : Image.memory(bytes!, fit: BoxFit.cover),
    ),
  );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.all(9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    ),
  );
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
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 44, paint);
    } else {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.guide != guide;
}

class _SceneChip extends StatelessWidget {
  const _SceneChip({required this.scene, required this.confidence});
  final String scene;
  final double confidence;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.visibility_outlined, color: Colors.white70, size: 13),
        const SizedBox(width: 5),
        Text(
          confidence > 0 ? '$scene ${(confidence * 100).round()}%' : scene,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ],
    ),
  );
}

class _SmartShutterChip extends StatelessWidget {
  const _SmartShutterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFD60A),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.camera_alt, color: Colors.black, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PosePainter extends CustomPainter {
  const _PosePainter(this.points);
  final Map<String, Offset> points;

  static const _bones = <(String, String)>[
    ('leftShoulder', 'rightShoulder'),
    ('leftShoulder', 'leftElbow'),
    ('leftElbow', 'leftWrist'),
    ('rightShoulder', 'rightElbow'),
    ('rightElbow', 'rightWrist'),
    ('leftShoulder', 'leftHip'),
    ('rightShoulder', 'rightHip'),
    ('leftHip', 'rightHip'),
    ('leftHip', 'leftKnee'),
    ('leftKnee', 'leftAnkle'),
    ('rightHip', 'rightKnee'),
    ('rightKnee', 'rightAnkle'),
  ];

  Offset _scaled(Offset value, Size size) =>
      Offset(value.dx * size.width, value.dy * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.amber.withValues(alpha: .8)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final dot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    for (final bone in _bones) {
      final start = points[bone.$1];
      final end = points[bone.$2];
      if (start != null && end != null) {
        canvas.drawLine(_scaled(start, size), _scaled(end, size), line);
      }
    }
    for (final point in points.values) {
      canvas.drawCircle(_scaled(point, size), 3.2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _PosePainter oldDelegate) =>
      oldDelegate.points != points;
}
