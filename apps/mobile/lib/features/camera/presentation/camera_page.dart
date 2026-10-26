import 'dart:async';
import 'dart:math' as math;

import 'package:ai_image_studio/features/camera/data/camera_session.dart';
import 'package:ai_image_studio/features/camera/data/camera_capabilities.dart';
import 'package:ai_image_studio/features/camera/data/camera_diagnostics.dart';
import 'package:ai_image_studio/features/camera/data/capture_preset.dart';
import 'package:ai_image_studio/features/camera/data/face_analyzer.dart';
import 'package:ai_image_studio/features/camera/data/live_camera_analyzer.dart';
import 'package:ai_image_studio/features/camera/data/photo_quality.dart';
import 'package:ai_image_studio/features/camera/data/portrait_composition_guide.dart';
import 'package:ai_image_studio/features/camera/data/portrait_quality_analyzer.dart';
import 'package:ai_image_studio/features/camera/data/stability_analyzer.dart';
import 'package:ai_image_studio/features/camera/presentation/camera_widgets.dart';
import 'package:ai_image_studio/features/generate/data/local_creation_store.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        DeviceOrientation,
        Clipboard,
        ClipboardData,
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
import 'package:url_launcher/url_launcher.dart';

enum CompositionGuide {
  thirds,
  center,
  symmetry,
  leadingLine,
  frame,
  goldenRatio,
}

enum CameraStyle { standard, vivid, warm, cool, mono, soft }

enum SmartShutterMode { off, smile, gesture }

enum CaptureEnhancement { standard, multiFrameHdr, nightDenoise }

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
  double _brightness = 128;
  List<double> _histogram = List<double>.filled(32, 0);
  List<double> _redHistogram = List<double>.filled(32, 0);
  List<double> _greenHistogram = List<double>.filled(32, 0);
  List<double> _blueHistogram = List<double>.filled(32, 0);
  double _highlightClipping = 0;
  double _shadowClipping = 0;
  double _highlightThreshold = .95;
  bool _showHistogram = false;
  bool _showZebra = false;
  List<Offset> _zebraPoints = const [];
  bool _showFocusPeaking = false;
  bool _lensCleaningHints = true;
  List<Offset> _focusPeaks = const [];
  double _clarityScore = 0;
  int _softFrameCount = 0;
  double _guidanceOpacity = 1;
  DateTime? _goodPoseSince;
  double _aspectRatio = 3 / 4;
  int _burstCount = 1;
  bool _scanMode = false;
  int _activeIndex = 0;
  int _initializationToken = 0;
  String _compositionSuggestion = '让主体靠近交叉点，画面会更有呼吸感';
  Offset? _focusPoint;
  Offset? _meteringPoint;
  bool _meteringPointSupported = true;
  DateTime _lastMeteringUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  final StabilityAnalyzer _stabilityAnalyzer = StabilityAnalyzer();
  StreamSubscription<AccelerometerEvent>? _motionSubscription;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _analysisIntervalMs = 260;
  bool _slowAnalysis = false;
  int _zebraFrame = 0;
  final LiveCameraAnalyzer _liveAnalyzer = LiveCameraAnalyzer();
  final PortraitCompositionAnalyzer _portraitGuide =
      const PortraitCompositionAnalyzer();
  LiveCameraAnalysis? _liveAnalysis;
  PortraitCompositionHint? _portraitHint;
  DateTime _portraitHintUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPortraitHintAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastPortraitHintCode;
  bool _showRealtimeGuidance = true;
  bool _showCameraOptions = false;
  bool _shutterFlash = false;
  bool _focusLocked = false;
  bool _exposureLocked = false;
  bool _mirrorSelfies = true;
  bool _autoSave = false;
  bool _saveOriginalCopy = false;
  CameraStyle _style = CameraStyle.standard;
  SmartShutterMode _smartShutterMode = SmartShutterMode.off;
  CaptureEnhancement _captureEnhancement = CaptureEnhancement.standard;
  int _smartSignalFrames = 0;
  DateTime _lastSmartCapture = DateTime.fromMillisecondsSinceEpoch(0);
  String? _barcodeValue;
  String? _barcodeType;
  DateTime _lastBarcodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  CameraCapabilities _capabilities = const CameraCapabilities.fallback();
  DeviceDiagnostics _deviceDiagnostics = const DeviceDiagnostics();
  DateTime? _initStartedAt;
  int? _initElapsedMs;
  String _initStage = 'idle';
  String? _lastInitError;
  bool _analysisUnavailable = false;
  int _analysisFrameCount = 0;
  DateTime _analysisWindowStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _analysisFps = 0;
  final CapturePresetRepository _presetRepository = CapturePresetRepository();
  List<CapturePreset> _customPresets = const [];
  String? _activePresetId;
  bool _permissionPermanentlyDenied = false;
  String? _processingStatus;
  double? _processingProgress;

  static const _aspectPreference = 'camera.aspect_ratio';
  static const _timerPreference = 'camera.timer_seconds';
  static const _guidePreference = 'camera.show_guide';
  static const _guideTypePreference = 'camera.guide_type';
  static const _guidancePreference = 'camera.realtime_guidance';
  static const _mirrorPreference = 'camera.mirror_selfies';
  static const _autoSavePreference = 'camera.auto_save';
  static const _saveOriginalPreference = 'camera.save_original';
  static const _stylePreference = 'camera.photo_style';
  static const _histogramPreference = 'camera.show_histogram';
  static const _zebraPreference = 'camera.show_zebra';
  static const _highlightThresholdPreference = 'camera.highlight_threshold';
  static const _smartShutterPreference = 'camera.smart_shutter';
  static const _focusPeakingPreference = 'camera.focus_peaking';
  static const _lensHintsPreference = 'camera.lens_cleaning_hints';
  static const _enhancementPreference = 'camera.capture_enhancement';

  StabilitySnapshot get _stability => _stabilityAnalyzer.snapshot;

  /// 只在有效期内展示构图提示，避免 UI 出现过期结果。
  PortraitCompositionHint? get _activePortraitHint {
    final hint = _portraitHint;
    if (hint == null) return null;
    return DateTime.now().isBefore(_portraitHintUntil) ? hint : null;
  }

  /// 夜景、HDR 或弱光环境下使用更严格的稳定阈值；
  /// 普通拍摄保持宽松，避免用户长时间等不到“可以拍摄”。
  StabilityRequirement get _stabilityRequirement {
    final enhancement = _burstCount == 1 && !_scanMode
        ? _captureEnhancement
        : CaptureEnhancement.standard;
    final lowLight = _brightness < 58;
    return enhancement != CaptureEnhancement.standard || lowLight
        ? StabilityRequirement.strict
        : StabilityRequirement.standard;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motionSubscription =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 120),
        ).listen(
          (event) {
            final angle = math.atan2(event.x, event.y) * 180 / math.pi;
            // 同一份加速度数据同时驱动水平仪和稳定度分析，
            // 避免为了新能力重复订阅传感器。
            _stabilityAnalyzer.setRequirement(_stabilityRequirement);
            final snapshot = _stabilityAnalyzer.ingest(
              event.x,
              event.y,
              event.z,
            );
            if (mounted) {
              setState(() {
                _levelAngle = angle.clamp(-45, 45);
                _motionLevel = snapshot.motion;
              });
            }
          },
          onError: (_) {
            // 没有加速度计时隐藏稳定度提示，评分自动退化为不含稳定分。
            _stabilityAnalyzer.reset();
            if (mounted) setState(() => _motionLevel = 0);
          },
        );
    _applyTemplateParams();
    unawaited(_activateHardwareControls());
    unawaited(_loadPreferences());
    unawaited(_loadCapabilities());
    unawaited(_loadPresets());
    unawaited(_loadDiagnostics());
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

  Future<void> _loadPresets() async {
    final catalog = await _presetRepository.load();
    if (mounted) setState(() => _customPresets = catalog.custom);
  }

  Future<void> _loadDiagnostics() async {
    final diagnostics = await CameraCapabilitiesService().loadDiagnostics();
    if (mounted) setState(() => _deviceDiagnostics = diagnostics);
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedAspect = preferences.getDouble(_aspectPreference);
    setState(() {
      if (savedAspect == 1 ||
          savedAspect == .75 ||
          savedAspect == .5625 ||
          savedAspect == 16 / 9) {
        _aspectRatio = savedAspect!;
      }
      _countdownSeconds = preferences.getInt(_timerPreference) ?? 0;
      _showGuide = preferences.getBool(_guidePreference) ?? true;
      final savedGuide = preferences.getString(_guideTypePreference);
      if (savedGuide != null && widget.templateParams == null) {
        _guide = CompositionGuide.values.firstWhere(
          (value) => value.name == savedGuide,
          orElse: () => _guide,
        );
      }
      _showRealtimeGuidance = preferences.getBool(_guidancePreference) ?? true;
      _mirrorSelfies = preferences.getBool(_mirrorPreference) ?? true;
      _autoSave = preferences.getBool(_autoSavePreference) ?? false;
      _saveOriginalCopy = preferences.getBool(_saveOriginalPreference) ?? false;
      final styleIndex = preferences.getInt(_stylePreference) ?? 0;
      _style = CameraStyle
          .values[styleIndex.clamp(0, CameraStyle.values.length - 1)];
      _showHistogram = preferences.getBool(_histogramPreference) ?? false;
      _showZebra = preferences.getBool(_zebraPreference) ?? false;
      final highlightThreshold =
          preferences.getDouble(_highlightThresholdPreference) ?? .95;
      _highlightThreshold = const [.90, .95, .98].contains(highlightThreshold)
          ? highlightThreshold
          : .95;
      final smartIndex = preferences.getInt(_smartShutterPreference) ?? 0;
      _smartShutterMode = SmartShutterMode
          .values[smartIndex.clamp(0, SmartShutterMode.values.length - 1)];
      _showFocusPeaking = preferences.getBool(_focusPeakingPreference) ?? false;
      _lensCleaningHints = preferences.getBool(_lensHintsPreference) ?? true;
      final enhancementIndex = preferences.getInt(_enhancementPreference) ?? 0;
      _captureEnhancement =
          CaptureEnhancement.values[enhancementIndex.clamp(
            0,
            CaptureEnhancement.values.length - 1,
          )];
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
    final message = _cameraError(error);
    final startedAt = _initStartedAt;
    setState(() {
      _error = message;
      _lastInitError = message;
      if (startedAt != null) {
        _initElapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      }
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
    final startedAt = DateTime.now();
    _initStartedAt = startedAt;
    _initElapsedMs = null;
    _initStage = '准备';
    _lastInitError = null;
    if (previous != null && mounted) {
      // 先把 UI 切到加载态，避免 dispose 的 await 期间出现
      // _initializing=false / _controller=null 的不一致窗口。
      setState(() {
        _initializing = true;
        _error = null;
        _permissionPermanentlyDenied = false;
        _controller = null;
        _clearFocusState();
        _clearPortraitHint();
      });
    }
    _initStage = '释放旧会话';
    await previous?.dispose();
    if (!mounted) return;
    _initStage = '创建控制器';
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
      _initStage = '打开相机';
      await controller.initialize().timeout(const Duration(seconds: 8));
      if (!mounted || token != _initializationToken) {
        await controller.dispose();
        return;
      }
      // 切换镜头后重建稳定窗口，避免把上一支镜头的运动状态带入新会话。
      _stabilityAnalyzer.reset();
      _stabilityAnalyzer.setRequirement(_stabilityRequirement);
      _initStage = '读取能力';
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
      _initStage = '设置闪光灯';
      await controller
          .setFlashMode(_flashMode)
          .timeout(const Duration(seconds: 3));
      if (_reviewing) {
        _initStage = '就绪（预览页暂停分析流）';
      } else {
        _initStage = '启动分析流';
        await _startLightMonitoring(controller);
        _initStage = '就绪';
      }
      _initElapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
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
        if (now.difference(_lastFrameAt).inMilliseconds < _analysisIntervalMs ||
            image.planes.isEmpty) {
          return;
        }
        _lastFrameAt = now;
        _recordAnalysisFrame();
        final stopwatch = Stopwatch()..start();
        // 低端设备上进一步降低斑马纹遮罩刷新率，直方图仍保持更新。
        final collectZebra =
            _showZebra && (!_slowAnalysis || _zebraFrame.isEven);
        _zebraFrame++;
        final histogram = _analyzeHistogram(
          image,
          controller.description,
          controller.value.deviceOrientation,
          collectZebra: collectZebra,
        );
        if (mounted && histogram.samples > 0) {
          final detail = _analyzeSharpness(
            image,
            controller.description,
            controller.value.deviceOrientation,
          );
          setState(() {
            _brightness = histogram.brightness;
            _highlightClipping = histogram.highlightClipping;
            _shadowClipping = histogram.shadowClipping;
            _histogram = histogram.luminance;
            _redHistogram = histogram.red;
            _greenHistogram = histogram.green;
            _blueHistogram = histogram.blue;
            _clarityScore = detail.clarity;
            _focusPeaks = _showFocusPeaking ? detail.peaks : const [];
            if (collectZebra) _zebraPoints = histogram.zebra;
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
        stopwatch.stop();
        _analysisIntervalMs = _nextAnalysisInterval(
          stopwatch.elapsedMilliseconds,
        );
        if (_showRealtimeGuidance ||
            _scanMode ||
            _smartShutterMode != SmartShutterMode.off) {
          unawaited(
            _analyzeFrame(
              image,
              controller.description,
              controller.value.deviceOrientation,
            ),
          );
        }
      });
      _analysisUnavailable = false;
    } catch (_) {
      // 部分 Android 设备无法同时绑定预览、拍照和图像分析三个
      // CameraX use case。实时分析属于增强能力，绑定失败时保留
      // 已经可用的预览与拍照，不让整个相机页面进入错误状态。
      _analysisUnavailable = true;
      _analysisIntervalMs = 260;
      _slowAnalysis = false;
      _zebraFrame = 0;
      if (mounted) {
        setState(() {
          _showRealtimeGuidance = false;
          _showHistogram = false;
          _liveAnalysis = null;
          _histogram = const [];
          _redHistogram = const [];
          _greenHistogram = const [];
          _blueHistogram = const [];
          _focusPeaks = const [];
          _zebraPoints = const [];
        });
      }
    }
  }

  int _nextAnalysisInterval(int elapsedMs) {
    _slowAnalysis = elapsedMs > 90;
    if (elapsedMs > 90) return 420;
    if (elapsedMs < 40) return 220;
    return 280;
  }

  void _recordAnalysisFrame() {
    final now = DateTime.now();
    if (_analysisWindowStartedAt.millisecondsSinceEpoch == 0) {
      _analysisWindowStartedAt = now;
      _analysisFrameCount = 0;
    }
    _analysisFrameCount++;
    final elapsed = now.difference(_analysisWindowStartedAt).inMilliseconds;
    if (elapsed >= 1000) {
      _analysisFps = _analysisFrameCount * 1000 / elapsed;
      _analysisFrameCount = 0;
      _analysisWindowStartedAt = now;
    }
  }

  _FrameHistogram _analyzeHistogram(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation, {
    required bool collectZebra,
  }) {
    const binCount = 32;
    final luminanceBins = List<int>.filled(binCount, 0);
    final redBins = List<int>.filled(binCount, 0);
    final greenBins = List<int>.filled(binCount, 0);
    final blueBins = List<int>.filled(binCount, 0);
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final isBgra = image.format.group == ImageFormatGroup.bgra8888;
    final isNv21 = image.format.group == ImageFormatGroup.nv21;
    final pixelStride = plane.bytesPerPixel ?? (isBgra ? 4 : 1);
    final yPlaneSize = rowStride * image.height;
    final step = math.max(6, math.min(image.width, image.height) ~/ 48);
    final highlightLevel = (_highlightThreshold * 255).round();
    final zebra = <Offset>[];
    var total = 0;
    var samples = 0;
    var highlights = 0;
    var shadows = 0;

    void addSample(int x, int y, int luma, int red, int green, int blue) {
      total += luma;
      if (luma >= highlightLevel) {
        highlights++;
        // 斑马纹直接复用直方图的亮度采样结果，避免二次扫描整帧。
        if (collectZebra && zebra.length < 900) {
          zebra.add(
            _rotateAnalysisPoint(
              Offset(x / image.width, y / image.height),
              camera,
              orientation,
            ),
          );
        }
      }
      if (luma <= 10) shadows++;
      luminanceBins[(luma * binCount ~/ 256).clamp(0, binCount - 1)]++;
      redBins[(red * binCount ~/ 256).clamp(0, binCount - 1)]++;
      greenBins[(green * binCount ~/ 256).clamp(0, binCount - 1)]++;
      blueBins[(blue * binCount ~/ 256).clamp(0, binCount - 1)]++;
      samples++;
    }

    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final index = y * rowStride + x * pixelStride;
        if (isBgra && index + 2 < bytes.length) {
          final blue = bytes[index];
          final green = bytes[index + 1];
          final red = bytes[index + 2];
          final luma = (.299 * red + .587 * green + .114 * blue).round();
          addSample(x, y, luma, red, green, blue);
        } else if (isNv21 && index < yPlaneSize && index < bytes.length) {
          final luma = bytes[index];
          final uvIndex = yPlaneSize + (y ~/ 2) * rowStride + (x & ~1);
          if (uvIndex + 1 >= bytes.length) continue;
          final v = bytes[uvIndex] - 128;
          final u = bytes[uvIndex + 1] - 128;
          final red = (luma + 1.402 * v).round().clamp(0, 255);
          final green = (luma - .344136 * u - .714136 * v).round().clamp(
            0,
            255,
          );
          final blue = (luma + 1.772 * u).round().clamp(0, 255);
          addSample(x, y, luma, red, green, blue);
        }
      }
    }

    List<double> normalize(List<int> bins, int peak) => peak == 0
        ? List<double>.filled(binCount, 0)
        : bins.map((value) => value / peak).toList(growable: false);
    final luminancePeak = luminanceBins.reduce(math.max);
    final colorPeak = <int>[
      ...redBins,
      ...greenBins,
      ...blueBins,
    ].reduce(math.max);
    return _FrameHistogram(
      samples: samples,
      brightness: samples == 0 ? 0 : total / samples,
      highlightClipping: samples == 0 ? 0 : highlights / samples,
      shadowClipping: samples == 0 ? 0 : shadows / samples,
      luminance: normalize(luminanceBins, luminancePeak),
      red: normalize(redBins, colorPeak),
      green: normalize(greenBins, colorPeak),
      blue: normalize(blueBins, colorPeak),
      zebra: zebra,
    );
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
      scanBarcodes: _scanMode,
    );
    if (!mounted || result == null) return;
    final goodPose = result.suggestion.startsWith('姿态很好');
    final now = DateTime.now();
    if (_showRealtimeGuidance && goodPose) {
      _goodPoseSince ??= now;
    } else {
      _goodPoseSince = null;
    }
    setState(() {
      _liveAnalysis = result;
      if (_showRealtimeGuidance) {
        _compositionSuggestion = result.suggestion;
        _updatePortraitHint(result, now);
        final portraitHint = _activePortraitHint;
        if (portraitHint != null) {
          _compositionSuggestion = portraitHint.message;
        }
        _guidanceOpacity =
            portraitHint != null ||
                !(goodPose &&
                    now.difference(_goodPoseSince!).inMilliseconds > 1800)
            ? 1
            : 0;
      }
      if (_scanMode && result.barcodeValue != null) {
        _barcodeValue = result.barcodeValue;
        _barcodeType = result.barcodeType;
        _lastBarcodeAt = now;
      } else if (now.difference(_lastBarcodeAt) > const Duration(seconds: 2)) {
        _barcodeValue = null;
        _barcodeType = null;
      }
    });
    _handleSmartShutter(result);
  }

  void _updatePortraitHint(LiveCameraAnalysis analysis, DateTime now) {
    // 当前提示仍在展示时不要被下一帧打断，避免文字来回跳。
    if (_portraitHint != null && now.isBefore(_portraitHintUntil)) return;
    final hint = _portraitGuide.evaluate(
      faces: analysis.faces,
      landmarks: analysis.landmarks,
    );
    if (hint == null || hint.confidence < .55) {
      _portraitHint = null;
      return;
    }
    final sameHint = hint.code == _lastPortraitHintCode;
    final cooldown = sameHint
        ? const Duration(seconds: 6)
        : const Duration(seconds: 2);
    if (now.difference(_lastPortraitHintAt) < cooldown) {
      _portraitHint = null;
      return;
    }
    _portraitHint = hint;
    _lastPortraitHintCode = hint.code;
    _lastPortraitHintAt = now;
    _portraitHintUntil = now.add(const Duration(seconds: 4));
  }

  void _clearPortraitHint() {
    _portraitHint = null;
    _portraitHintUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPortraitHintAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPortraitHintCode = null;
  }

  void _handleSmartShutter(LiveCameraAnalysis analysis) {
    final detected = switch (_smartShutterMode) {
      SmartShutterMode.off => false,
      SmartShutterMode.smile => analysis.smileDetected,
      SmartShutterMode.gesture => analysis.gestureDetected,
    };
    // 智能快门只在画面连续稳定后触发；传感器不可用或数据过期时
    // 不做稳定度限制，保证基础拍摄能力不受影响。
    final stability = _stability;
    final stabilityKnown = stability.hasSamples && !stability.isStale();
    final stable = !stabilityKnown || stability.stable;
    _smartSignalFrames = detected && stable ? _smartSignalFrames + 1 : 0;
    if (_smartSignalFrames < 3 || _capturing) return;
    final now = DateTime.now();
    if (now.difference(_lastSmartCapture) < const Duration(seconds: 6)) return;
    _smartSignalFrames = 0;
    _lastSmartCapture = now;
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_capture());
  }

  Future<void> _copyBarcode() async {
    final value = _barcodeValue;
    if (value == null) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _showMessage('扫码内容已复制');
  }

  Future<void> _openBarcodeLink() async {
    final value = _barcodeValue;
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      _showMessage('仅支持安全打开 HTTP/HTTPS 链接');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _showMessage('无法打开此链接');
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
          _clearFocusState();
          _clearPortraitHint();
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

  Future<void> _selectPhysicalLens(NativeCameraLens lens) async {
    if (_initializing) return;
    final index = _cameras.indexWhere(
      (camera) => camera.name == lens.id || camera.name.contains(lens.id),
    );
    if (index < 0 || index == _activeIndex) return;
    _activeIndex = index;
    await _initializeCamera(index);
  }

  List<NativeCameraLens> get _selectableBackLenses => _capabilities.lenses
      .where(
        (lens) =>
            lens.isBack &&
            _cameras.any(
              (camera) =>
                  camera.name == lens.id || camera.name.contains(lens.id),
            ),
      )
      .toList(growable: false);

  NativeCameraLens? get _activeNativeLens {
    final cameraId = _controller?.description.name;
    if (cameraId == null) return null;
    for (final lens in _capabilities.lenses) {
      if (cameraId == lens.id || cameraId.contains(lens.id)) return lens;
    }
    return null;
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
    final startingExposure = _exposure;
    final startingFlash = _flashMode;
    var captureFailed = false;
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
      final rawFrames = <Uint8List>[];
      // 每次快门触发时记录稳定度，供选片和后续元数据使用。
      final capturedContexts = <CaptureContext>[];
      Uint8List? firstOriginal;
      XFile? analysisFile;
      final enhancement = !continuous && _burstCount == 1 && !_scanMode
          ? _captureEnhancement
          : CaptureEnhancement.standard;
      if (enhancement != CaptureEnhancement.standard) {
        await controller.setFlashMode(FlashMode.off);
      }
      // Keep a conservative cap to avoid high-resolution JPEGs exhausting
      // memory on mid-range Android devices.
      final requestedCount = continuous
          ? 8
          : enhancement == CaptureEnhancement.standard
          ? _burstCount
          : 3;
      final exposureSpan = math.min(
        1.0,
        math
            .min(
              _maxExposure - startingExposure,
              startingExposure - _minExposure,
            )
            .abs(),
      );
      for (var index = 0; index < requestedCount; index++) {
        if (continuous && !_continuousBurst && index > 0) break;
        if (mounted) {
          setState(() {
            _shutterFlash = true;
            _processingStatus = '拍摄中 ${index + 1}/$requestedCount';
            _processingProgress = index / requestedCount;
          });
        }
        if (enhancement == CaptureEnhancement.multiFrameHdr) {
          final offset = <double>[-exposureSpan, 0, exposureSpan][index];
          await _setExposure(
            (startingExposure + offset).clamp(_minExposure, _maxExposure),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        } else if (enhancement == CaptureEnhancement.nightDenoise) {
          await _setExposure(
            (startingExposure + .45).clamp(_minExposure, _maxExposure),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final file = await controller.takePicture();
        if (mounted) setState(() => _shutterFlash = false);
        analysisFile ??= file;
        final stability = _stability;
        capturedContexts.add(
          CaptureContext(
            cameraId: controller.description.name,
            lensType:
                _activeNativeLens?.type ??
                controller.description.lensDirection.name,
            zoom: _zoom,
            exposureOffset: _exposure,
            stabilityScore: stability.captureScore,
            capturedAt: DateTime.now(),
          ),
        );
        final bytes = await file.readAsBytes();
        firstOriginal ??= bytes;
        rawFrames.add(bytes);
        final mirror =
            _mirrorSelfies &&
            controller.description.lensDirection == CameraLensDirection.front;
        if (enhancement == CaptureEnhancement.standard) {
          values.add(
            await compute(_processPhoto, (
              bytes,
              _aspectRatio,
              mirror,
              _style.index,
            )),
          );
        }
        if (mounted) {
          setState(() {
            _burstTaken = rawFrames.length;
            _processingProgress = rawFrames.length / requestedCount;
          });
        }
        if (index + 1 < requestedCount) {
          await Future<void>.delayed(
            Duration(milliseconds: continuous ? 120 : 220),
          );
        }
      }
      await _setExposure(startingExposure);
      if (enhancement != CaptureEnhancement.standard && rawFrames.isNotEmpty) {
        if (mounted) {
          setState(() {
            _processingStatus = enhancement == CaptureEnhancement.multiFrameHdr
                ? '正在合成多帧 HDR'
                : '正在进行夜景降噪';
            _processingProgress = null;
          });
        }
        final mirror =
            _mirrorSelfies &&
            controller.description.lensDirection == CameraLensDirection.front;
        values.add(
          await compute(_mergeAndProcessPhotos, (
            rawFrames,
            _aspectRatio,
            mirror,
            _style.index,
            enhancement.index,
          )),
        );
      }
      if (mounted && values.isNotEmpty) {
        setState(() => _capturedImage = values.first);
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
            contexts: _contextsForValues(values, capturedContexts),
            portraitAnalyzer: analyzePortraitQuality,
            onProgress: (progress) {
              if (mounted) setState(() => _processingProgress = progress);
            },
            onPortraitProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _processingStatus = '正在分析人像与睁眼状态';
                _processingProgress = progress;
              });
            },
          );
      final session = ref.read(cameraSessionProvider);
      if (_autoSave) {
        final best = session.selected;
        if (best != null) {
          unawaited(_saveToGallery(best.bytes, suffix: 'styled'));
        }
        if (_saveOriginalCopy && firstOriginal != null) {
          unawaited(_saveToGallery(firstOriginal, suffix: 'original'));
        }
      }
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
      captureFailed = true;
      if (mounted) _showMessage(_cameraError(error));
    } on PlatformException catch (error) {
      captureFailed = true;
      if (mounted) _showMessage(_cameraError(error));
    } catch (error) {
      // MLKit 失败、文件 IO 失败等都兜到这里,不裸露异常。
      captureFailed = true;
      if (mounted) _showMessage(_cameraError(error));
    } finally {
      if (captureFailed) {
        // 异常可能发生在锁定 AE/AF 之后，恢复自动模式避免污染下一次拍摄。
        unawaited(_restoreAutoFocus());
      }
      if ((_exposure - startingExposure).abs() > .01) {
        await _setExposure(startingExposure);
      }
      if (controller.value.isInitialized) {
        try {
          await controller.setFlashMode(startingFlash);
        } on CameraException {
          // Camera may already be closing after a lifecycle transition.
        }
      }
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
      if (!_reviewing &&
          controller.value.isInitialized &&
          !controller.value.isStreamingImages) {
        await _startLightMonitoring(controller);
      }
    }
  }

  /// 把每次快门的上下文与最终输出对齐：HDR/夜景会多帧合并为一张，
  /// 此时用所有帧稳定度均值代表这张合成照片。
  List<CaptureContext?> _contextsForValues(
    List<Uint8List> values,
    List<CaptureContext> contexts,
  ) {
    if (values.isEmpty || contexts.isEmpty) {
      return List<CaptureContext?>.filled(values.length, null);
    }
    if (contexts.length == values.length) {
      return List<CaptureContext?>.of(contexts);
    }
    final scores = contexts
        .map((context) => context.stabilityScore)
        .whereType<double>()
        .toList(growable: false);
    final merged = contexts.first.copyWith(
      stabilityScore: scores.isEmpty
          ? null
          : scores.reduce((left, right) => left + right) / scores.length,
    );
    return [merged, ...List<CaptureContext?>.filled(values.length - 1, null)];
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
    await ref.read(cameraSessionProvider.notifier).setPhotos([
      bytes,
    ], portraitAnalyzer: analyzePortraitQuality);
    if (mounted) setState(() => _capturedImage = bytes);
  }

  Future<void> _focus(
    TapDownDetails details,
    BoxConstraints constraints, {
    bool lock = false,
  }) async {
    final controller = _controller;
    if (controller == null) return;
    final point = Offset(
      (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );
    try {
      await controller.setFocusMode(lock ? FocusMode.locked : FocusMode.auto);
      await controller.setFocusPoint(point);
    } on CameraException {
      if (mounted) _showMessage('当前设备不支持手动对焦，已保持自动对焦');
      return;
    } on PlatformException {
      if (mounted) _showMessage('当前设备不支持手动对焦，已保持自动对焦');
      return;
    }
    if (!mounted) return;
    setState(() {
      _focusPoint = details.localPosition;
      _meteringPoint = null;
      _focusLocked = lock;
      _exposureLocked = lock;
    });
    if (!_meteringPointSupported) {
      // 设备已确认不支持独立测光点，保留曝光补偿但不再假装锁定 AE。
      if (_exposureLocked) setState(() => _exposureLocked = false);
    } else {
      try {
        // 点击会解除上一次锁定并重新对焦；长按则在当前位置锁定 AE/AF。
        await controller.setExposureMode(
          lock ? ExposureMode.locked : ExposureMode.auto,
        );
        await controller.setExposurePoint(point);
      } on CameraException {
        _disableMeteringPoint();
      } on PlatformException {
        _disableMeteringPoint();
      }
    }
    if (lock) {
      unawaited(HapticFeedback.selectionClick());
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && !_focusLocked) setState(() => _focusPoint = null);
  }

  Future<void> _lockFocus(
    LongPressStartDetails details,
    BoxConstraints constraints,
  ) => _focus(
    TapDownDetails(localPosition: details.localPosition),
    constraints,
    lock: true,
  );

  /// 从焦点环旁的 AE 手柄拖出独立测光点。
  void _dragMetering(DragUpdateDetails details, BoxConstraints constraints) {
    if (!_meteringPointSupported) return;
    final controller = _controller;
    final base = _meteringPoint ?? _focusPoint;
    if (controller == null || base == null) return;
    final next = Offset(
      (base.dx + details.delta.dx).clamp(0.0, constraints.maxWidth),
      (base.dy + details.delta.dy).clamp(0.0, constraints.maxHeight),
    );
    setState(() {
      _meteringPoint = next;
      _exposureLocked = false;
    });
    final now = DateTime.now();
    if (now.difference(_lastMeteringUpdate) <
        const Duration(milliseconds: 90)) {
      return;
    }
    _lastMeteringUpdate = now;
    unawaited(
      _applyMeteringPoint(
        controller,
        Offset(next.dx / constraints.maxWidth, next.dy / constraints.maxHeight),
      ),
    );
  }

  Future<void> _applyMeteringPoint(
    CameraController controller,
    Offset point,
  ) async {
    try {
      // 测光点独立移动时始终保持曝光自动，只改变测光位置。
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setExposurePoint(point);
    } on CameraException {
      _disableMeteringPoint();
    } on PlatformException {
      _disableMeteringPoint();
    }
  }

  void _disableMeteringPoint() {
    if (!_meteringPointSupported) return;
    setState(() {
      _meteringPointSupported = false;
      _meteringPoint = null;
      _exposureLocked = false;
    });
    if (_focusPoint != null) {
      _showMessage('当前设备不支持独立测光点，已保留曝光补偿');
    }
  }

  void _clearFocusState() {
    _focusPoint = null;
    _meteringPoint = null;
    _focusLocked = false;
    _exposureLocked = false;
    _meteringPointSupported = true;
    _lastMeteringUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// 拍摄异常后恢复自动模式，避免下次进入时仍锁在错误的曝光值上。
  Future<void> _restoreAutoFocus() async {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {
        // 相机可能正在关闭，忽略恢复失败。
      }
    }
    if (mounted) setState(_clearFocusState);
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
    CompositionGuide.leadingLine => '引导线',
    CompositionGuide.frame => '框中框',
    CompositionGuide.goldenRatio => '黄金分割',
  };

  IconData _guideIcon(CompositionGuide guide) => switch (guide) {
    CompositionGuide.thirds => Icons.grid_3x3,
    CompositionGuide.center => Icons.center_focus_weak,
    CompositionGuide.symmetry => Icons.compare,
    CompositionGuide.leadingLine => Icons.trending_up,
    CompositionGuide.frame => Icons.crop_free,
    CompositionGuide.goldenRatio => Icons.grid_goldenratio,
  };

  Future<void> _selectCompositionGuide() async {
    final selected = await showModalBottomSheet<CompositionGuide>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  '选择构图辅助线',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.25,
                children: [
                  for (final guide in CompositionGuide.values)
                    InkWell(
                      onTap: () => Navigator.of(sheetContext).pop(guide),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: guide == _guide
                              ? const Color(0xFFFFD60A).withValues(alpha: .18)
                              : Colors.white.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: guide == _guide
                                ? const Color(0xFFFFD60A)
                                : Colors.white24,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _guideIcon(guide),
                              color: guide == _guide
                                  ? const Color(0xFFFFD60A)
                                  : Colors.white70,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _compositionGuideName(guide),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _guide = selected;
      _showGuide = true;
    });
    unawaited(_savePreference(_guidePreference, true));
    unawaited(_savePreference(_guideTypePreference, selected.name));
  }

  String get _activePresetName =>
      CapturePresetCatalog(
        builtIn: CapturePresetRepository.builtInPresets,
        custom: _customPresets,
      ).byId(_activePresetId)?.name ??
      '场景预设';

  bool _supportsCaptureEnhancement(CaptureEnhancement enhancement) {
    final modes = _capabilities.extensionModes;
    // 原生能力未上报时不阻断预设，避免把“未检测”误判为“不支持”。
    if (modes.isEmpty) return true;
    return switch (enhancement) {
      CaptureEnhancement.standard => true,
      CaptureEnhancement.multiFrameHdr =>
        modes.contains('hdr') || modes.contains('auto'),
      CaptureEnhancement.nightDenoise =>
        modes.contains('night') || modes.contains('auto'),
    };
  }

  CameraDiagnostics _diagnosticsSnapshot() {
    final lens = _activeNativeLens;
    final degraded = <String>[
      if (_analysisUnavailable) '实时分析流不可用',
      if (!_stability.hasSamples) '稳定度传感器不可用',
      if (!_meteringPointSupported) '独立测光点不可用',
      if (!_supportsCaptureEnhancement(CaptureEnhancement.multiFrameHdr))
        'HDR 不可用',
      if (!_supportsCaptureEnhancement(CaptureEnhancement.nightDenoise))
        '夜景降噪不可用',
      if (_permissionPermanentlyDenied) '相机权限被拒绝',
      if (_error != null) '相机错误',
    ];
    final active = <String>[
      if (_showHistogram) '直方图',
      if (_showZebra) '斑马纹',
      if (_showFocusPeaking) '峰值对焦',
      if (_showRealtimeGuidance) '姿态/人像构图',
      if (_stability.hasSamples) '稳定度',
      if (_smartShutterMode != SmartShutterMode.off) '智能快门',
    ];
    return CameraDiagnostics(
      platform: _capabilities.platform,
      lensId: _controller?.description.name,
      lensType: lens?.type,
      initializationMs: _initElapsedMs,
      initializationStage: _initStage,
      lastError: _lastInitError ?? _error,
      analysisFps: _analysisFps,
      analysisFormat: preferredAnalysisFormat.name,
      activeAnalyzers: active,
      degraded: degraded,
      freeStorageMb: _deviceDiagnostics.freeStorageMb,
      totalStorageMb: _deviceDiagnostics.totalStorageMb,
      availableMemoryMb: _deviceDiagnostics.availableMemoryMb,
      totalMemoryMb: _deviceDiagnostics.totalMemoryMb,
      lowMemory: _deviceDiagnostics.lowMemory,
      thermalStatus: _deviceDiagnostics.thermalStatus,
    );
  }

  Future<void> _copyDiagnostics() async {
    final report = _diagnosticsSnapshot().buildReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) _showMessage('诊断报告已复制，可直接粘贴反馈');
  }

  void _applyPreset(CapturePreset preset) {
    final guide = CompositionGuide.values.firstWhere(
      (value) => value.name == preset.guide,
      orElse: () => CompositionGuide.thirds,
    );
    var enhancement = CaptureEnhancement.values.firstWhere(
      (value) => value.name == preset.enhancement,
      orElse: () => CaptureEnhancement.standard,
    );
    final style = CameraStyle.values.firstWhere(
      (value) => value.name == preset.style,
      orElse: () => CameraStyle.standard,
    );
    final degraded = !_supportsCaptureEnhancement(enhancement);
    if (degraded) enhancement = CaptureEnhancement.standard;
    setState(() {
      _guide = guide;
      _showGuide = true;
      _aspectRatio = preset.aspectRatio;
      _burstCount = preset.burstCount >= 5 ? 5 : 1;
      _scanMode = false;
      _barcodeValue = null;
      _captureEnhancement = enhancement;
      _style = style;
      _activePresetId = preset.id;
    });
    unawaited(_savePreference(_aspectPreference, _aspectRatio));
    unawaited(_savePreference(_guidePreference, true));
    unawaited(_savePreference(_guideTypePreference, guide.name));
    unawaited(_savePreference(_stylePreference, style.index));
    unawaited(_savePreference(_enhancementPreference, enhancement.index));
    _showMessage(
      degraded
          ? '已应用「${preset.name}」，当前设备不支持'
                '${cameraPresetEnhancementLabel(preset.enhancement)}，已使用标准拍摄'
          : '已应用「${preset.name}」预设',
    );
  }

  Future<void> _copyPreset(CapturePreset source) async {
    final copy = source.copyWith(
      id: 'custom.${DateTime.now().microsecondsSinceEpoch}',
      name: '${source.name} 自定义',
      builtIn: false,
      sourceId: source.id,
    );
    final next = [..._customPresets, copy];
    setState(() => _customPresets = next);
    await _presetRepository.saveCustom(next);
    if (mounted) _showMessage('已复制为「${copy.name}」');
  }

  Future<void> _deleteCustomPreset(CapturePreset preset) async {
    final next = _customPresets
        .where((item) => item.id != preset.id)
        .toList(growable: false);
    setState(() {
      _customPresets = next;
      if (_activePresetId == preset.id) _activePresetId = null;
    });
    await _presetRepository.saveCustom(next);
    if (mounted) _showMessage('已删除自定义预设');
  }

  Future<void> _saveCurrentAsPreset() async {
    final controller = TextEditingController(text: '我的场景');
    String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text('保存当前设置'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 12,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: '预设名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (!mounted || name == null || name.isEmpty) return;
    final preset = CapturePreset(
      id: 'custom.${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      aspectRatio: _aspectRatio,
      guide: _guide.name,
      burstCount: _burstCount,
      enhancement: _captureEnhancement.name,
      style: _style.name,
    );
    final next = [..._customPresets, preset];
    setState(() => _customPresets = next);
    await _presetRepository.saveCustom(next);
    if (mounted) _showMessage('已保存自定义预设「$name」');
  }

  Future<void> _openPresetSheet() async {
    final catalog = CapturePresetCatalog(
      builtIn: CapturePresetRepository.builtInPresets,
      custom: _customPresets,
    );
    final action = await showModalBottomSheet<_PresetAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (sheetContext) => CameraPresetSheet(
        builtIn: catalog.builtIn,
        custom: catalog.custom,
        activeId: _activePresetId,
        onApply: (preset) => Navigator.of(
          sheetContext,
        ).pop(_PresetAction._(_PresetActionType.apply, preset: preset)),
        onCopy: (preset) => Navigator.of(
          sheetContext,
        ).pop(_PresetAction._(_PresetActionType.copy, preset: preset)),
        onDelete: (preset) => Navigator.of(
          sheetContext,
        ).pop(_PresetAction._(_PresetActionType.delete, preset: preset)),
        onSaveCurrent: () => Navigator.of(
          sheetContext,
        ).pop(const _PresetAction._(_PresetActionType.saveCurrent)),
      ),
    );
    if (action == null || !mounted) return;
    switch (action.type) {
      case _PresetActionType.apply:
        if (action.preset != null) _applyPreset(action.preset!);
        break;
      case _PresetActionType.copy:
        if (action.preset != null) await _copyPreset(action.preset!);
        break;
      case _PresetActionType.delete:
        if (action.preset != null) await _deleteCustomPreset(action.preset!);
        break;
      case _PresetActionType.saveCurrent:
        await _saveCurrentAsPreset();
        break;
    }
  }

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
    // Use the Flutter view instead of an inherited MediaQuery orientation.
    // Some Android camera/rotation combinations briefly leave MediaQuery with
    // the sensor orientation, which puts the landscape controls halfway up a
    // portrait screen.
    final viewSize = View.of(context).physicalSize;
    final landscape = viewSize.width > viewSize.height;
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
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
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
          onTap: () {
            if (!_showCameraOptions) unawaited(_loadDiagnostics());
            setState(() => _showCameraOptions = !_showCameraOptions);
          },
          icon: _showCameraOptions
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
        ),
        const Spacer(),
        IconButton(
          tooltip: '实时姿态指导',
          onPressed: () => setState(() {
            _showRealtimeGuidance = !_showRealtimeGuidance;
            if (!_showRealtimeGuidance) {
              _liveAnalysis = null;
              _clearPortraitHint();
            }
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
          _DiagnosticsPanel(
            diagnostics: _diagnosticsSnapshot(),
            onCopy: _copyDiagnostics,
          ),
          const SizedBox(height: 8),
          CameraProfessionalPanel(
            lens: _activeNativeLens,
            exposure: _exposure,
            minExposure: _minExposure,
            maxExposure: _maxExposure,
            onExposureChanged: (value) => unawaited(_setExposure(value)),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ratio in const [
                ('1:1', 1.0),
                ('3:4', .75),
                ('9:16', .5625),
                ('16:9', 16 / 9),
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
                onTap: _selectCompositionGuide,
              ),
              _CameraOption(
                label: _activePresetName,
                icon: Icons.auto_awesome_motion,
                selected: _activePresetId != null,
                onTap: _openPresetSheet,
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
                label: '高光 ${(100 * _highlightThreshold).round()}%',
                icon: Icons.wb_sunny_outlined,
                selected: _showHistogram || _showZebra,
                onTap: () => setState(() {
                  const thresholds = [.90, .95, .98];
                  final current = thresholds.indexOf(_highlightThreshold);
                  _highlightThreshold =
                      thresholds[(current + 1) % thresholds.length];
                  _showHistogram = true;
                  unawaited(
                    _savePreference(
                      _highlightThresholdPreference,
                      _highlightThreshold,
                    ),
                  );
                  unawaited(_savePreference(_histogramPreference, true));
                }),
              ),
              _CameraOption(
                label: '斑马纹',
                icon: Icons.texture,
                selected: _showZebra,
                onTap: () => setState(() {
                  _showZebra = !_showZebra;
                  if (!_showZebra) _zebraPoints = const [];
                  unawaited(_savePreference(_zebraPreference, _showZebra));
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
                ('柔和', CameraStyle.soft),
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
              for (final option in const [
                (
                  '标准拍摄',
                  CaptureEnhancement.standard,
                  Icons.camera_alt_outlined,
                ),
                ('多帧 HDR', CaptureEnhancement.multiFrameHdr, Icons.hdr_on),
                (
                  '夜景降噪',
                  CaptureEnhancement.nightDenoise,
                  Icons.nightlight_outlined,
                ),
              ])
                _CameraOption(
                  label: option.$1,
                  icon: option.$3,
                  selected: _captureEnhancement == option.$2,
                  onTap: () => setState(() {
                    _captureEnhancement = option.$2;
                    unawaited(
                      _savePreference(
                        _enhancementPreference,
                        _captureEnhancement.index,
                      ),
                    );
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
            if (_showZebra && _zebraPoints.isNotEmpty)
              IgnorePointer(
                child: CustomPaint(painter: _ZebraPainter(_zebraPoints)),
              ),
            if (_focusPoint != null) ...[
              Positioned(
                left: _focusPoint!.dx - 25,
                top: _focusPoint!.dy - 25,
                child: IgnorePointer(
                  child: CameraFocusRing(
                    locked: _focusLocked,
                    exposureLocked: _exposureLocked,
                  ),
                ),
              ),
              if (_meteringPointSupported && !_focusLocked)
                Positioned(
                  left: (_focusPoint!.dx + 20).clamp(
                    0.0,
                    constraints.maxWidth - 34,
                  ),
                  top: (_focusPoint!.dy - 36).clamp(
                    0.0,
                    constraints.maxHeight - 34,
                  ),
                  child: CameraMeteringDragHandle(
                    onPanUpdate: (details) =>
                        _dragMetering(details, constraints),
                  ),
                ),
              if (_meteringPoint != null &&
                  (_meteringPoint! - _focusPoint!).distance > 8)
                Positioned(
                  left: _meteringPoint!.dx - 19,
                  top: _meteringPoint!.dy - 19,
                  child: IgnorePointer(
                    child: CameraMeteringRing(locked: _exposureLocked),
                  ),
                ),
            ],
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
            if (!_scanMode && !_capturing && !_stability.isStale())
              Positioned(
                right: 14,
                bottom: 62,
                child: _StabilityChip(snapshot: _stability),
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
                  red: _redHistogram,
                  green: _greenHistogram,
                  blue: _blueHistogram,
                  highlightThreshold: _highlightThreshold,
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
            if (!_scanMode)
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
                    suggestion:
                        _activePortraitHint?.message ?? _compositionSuggestion,
                    prioritizeSuggestion: _activePortraitHint != null,
                  ),
                ),
              ),
            if (_scanMode) const Center(child: _ScanFrame()),
            if (_scanMode && _barcodeValue != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _BarcodeResultCard(
                  value: _barcodeValue!,
                  type: _barcodeType,
                  onCopy: _copyBarcode,
                  onOpen: _openBarcodeLink,
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
              selected: !_scanMode && _burstCount == 1,
              onTap: () => setState(() {
                _scanMode = false;
                _burstCount = 1;
                _barcodeValue = null;
              }),
            ),
            const SizedBox(width: 18),
            _CameraModeLabel(
              label: '连拍',
              selected: !_scanMode && _burstCount == 5,
              onTap: () => setState(() {
                _scanMode = false;
                _burstCount = 5;
                _barcodeValue = null;
              }),
            ),
            const SizedBox(width: 18),
            _CameraModeLabel(
              label: '扫码',
              selected: _scanMode,
              onTap: () => setState(() {
                _scanMode = true;
                _burstCount = 1;
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectableBackLenses.length > 1) ...[
          _PhysicalLensSelector(
            lenses: _selectableBackLenses,
            activeId: _controller?.description.name,
            onSelected: _selectPhysicalLens,
          ),
          const SizedBox(height: 8),
        ],
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
                  : () => unawaited(_enterReview()),
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
          if (ref.watch(cameraSessionProvider).selected case final selected?)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFFFFD60A),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '智能选片：${selected.qualityLabel} · ${selected.score.round()} 分',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (selected.reasons.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '推荐原因：${selected.recommendationReason}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
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
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: TextButton.icon(
              onPressed: _saveToLibrary,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('保存到作品库'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _saveToLibrary() async {
    final session = ref.read(cameraSessionProvider);
    final selected = session.selected;
    final bytes = selected?.bytes ?? _capturedImage;
    if (bytes == null) return;
    final aspect = _aspectRatio == .75
        ? '3:4'
        : _aspectRatio == .5625
        ? '9:16'
        : _aspectRatio == 16 / 9
        ? '16:9'
        : '1:1';
    try {
      final task = await ref
          .read(localCreationStoreProvider)
          .saveSuccess(
            prompt: _initialPrompt?.isNotEmpty == true
                ? _initialPrompt!
                : '相机拍摄',
            aspectRatio: aspect,
            count: 1,
            type: 'CAMERA',
            images: [bytes],
            metadata: selected == null ? null : _photoMetadata(selected),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已保存到作品库'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => context.push('/task/${task.id}'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage('保存到作品库失败：$error');
    }
  }

  /// 把可解释的质量指标和拍摄上下文写入本地作品元数据。
  Map<String, Object?>? _photoMetadata(CapturedPhoto photo) {
    final metrics = photo.metrics;
    final portrait = metrics.portrait;
    final context = photo.context;
    return {
      'quality': {
        'total_score': _roundScore(metrics.totalScore),
        'sharpness': _roundScore(metrics.sharpness),
        'exposure': _roundScore(metrics.exposure),
        'contrast': _roundScore(metrics.contrast),
        'clipping_penalty': _roundScore(metrics.clippingPenalty),
        'stability': metrics.stability == null
            ? null
            : _roundScore(metrics.stability!),
        'portrait': portrait == null
            ? null
            : {
                'face_count': portrait.faceCount,
                'face_sharpness': _roundScore(portrait.faceSharpness),
                'eyes_open_score': _roundScore(portrait.eyesOpenScore),
                'smile_score': _roundScore(portrait.smileScore),
                'occlusion_risk': _roundScore(portrait.occlusionRisk),
              },
      },
      'capture': context == null
          ? null
          : {
              'camera_id': context.cameraId,
              'lens_type': context.lensType,
              'zoom': _roundScore(context.zoom),
              'exposure_offset': _roundScore(context.exposureOffset),
              'stability_score': context.stabilityScore == null
                  ? null
                  : _roundScore(context.stabilityScore!),
              'preset_id': context.presetId,
              'captured_at': context.capturedAt.toUtc().toIso8601String(),
            },
      'recommendation': photo.recommendationReason,
    };
  }

  double _roundScore(double value) => double.parse(value.toStringAsFixed(2));

  /// 进入照片预览前停止图像流，避免预览页继续占用相机分析资源。
  Future<void> _enterReview() async {
    if (_capturing) return;
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {
        // 相机可能正在切换或关闭，预览仍可继续。
      }
    }
    if (mounted) setState(() => _reviewing = true);
  }

  Future<void> _retake() async {
    if (mounted) {
      setState(() {
        _capturedImage = null;
        _reviewing = false;
      });
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      if (_cameras.isNotEmpty) await _initializeCamera(_activeIndex);
      return;
    }
    if (!controller.value.isStreamingImages) {
      await _startLightMonitoring(controller);
    }
  }
}

class _FrameHistogram {
  const _FrameHistogram({
    required this.samples,
    required this.brightness,
    required this.highlightClipping,
    required this.shadowClipping,
    required this.luminance,
    required this.red,
    required this.green,
    required this.blue,
    required this.zebra,
  });

  final int samples;
  final double brightness;
  final double highlightClipping;
  final double shadowClipping;
  final List<double> luminance;
  final List<double> red;
  final List<double> green;
  final List<double> blue;

  /// 高光采样点的归一化坐标，用于绘制斑马纹。
  final List<Offset> zebra;
}

class _FrameSharpness {
  const _FrameSharpness({required this.clarity, required this.peaks});

  final double clarity;
  final List<Offset> peaks;
}

Uint8List _processPhoto((Uint8List, double, bool, int) input) {
  final decoded = img.decodeImage(input.$1);
  if (decoded == null) return input.$1;
  return _finishPhoto(
    img.bakeOrientation(decoded),
    aspectRatio: input.$2,
    mirror: input.$3,
    styleIndex: input.$4,
  );
}

Uint8List _mergeAndProcessPhotos(
  (List<Uint8List>, double, bool, int, int) input,
) {
  final decoded = <img.Image>[];
  for (final bytes in input.$1) {
    final raw = img.decodeImage(bytes);
    if (raw == null) continue;
    var frame = img.bakeOrientation(raw);
    if (frame.width > 1800) {
      frame = img.copyResize(frame, width: 1800);
    }
    decoded.add(frame);
  }
  if (decoded.isEmpty) return Uint8List(0);
  final first = decoded.first;
  final frames = <img.Image>[first];
  for (final frame in decoded.skip(1)) {
    frames.add(
      frame.width == first.width && frame.height == first.height
          ? frame
          : img.copyResize(frame, width: first.width, height: first.height),
    );
  }
  final merged = img.copyResize(
    first,
    width: first.width,
    height: first.height,
  );
  final enhancement = CaptureEnhancement
      .values[input.$5.clamp(0, CaptureEnhancement.values.length - 1)];
  for (var y = 0; y < merged.height; y++) {
    for (var x = 0; x < merged.width; x++) {
      var red = 0.0;
      var green = 0.0;
      var blue = 0.0;
      var weightTotal = 0.0;
      for (final frame in frames) {
        final pixel = frame.getPixel(x, y);
        final luminance = .299 * pixel.r + .587 * pixel.g + .114 * pixel.b;
        final weight = enhancement == CaptureEnhancement.multiFrameHdr
            ? (1 - (luminance - 128).abs() / 160).clamp(.2, 1.0)
            : 1.0;
        red += pixel.r * weight;
        green += pixel.g * weight;
        blue += pixel.b * weight;
        weightTotal += weight;
      }
      final output = merged.getPixel(x, y);
      output.r = (red / weightTotal).clamp(0, 255);
      output.g = (green / weightTotal).clamp(0, 255);
      output.b = (blue / weightTotal).clamp(0, 255);
      output.a = 255;
    }
  }
  return _finishPhoto(
    merged,
    aspectRatio: input.$2,
    mirror: input.$3,
    styleIndex: input.$4,
  );
}

Uint8List _finishPhoto(
  img.Image source, {
  required double aspectRatio,
  required bool mirror,
  required int styleIndex,
}) {
  var image = mirror ? img.flipHorizontal(source) : source;
  final target = aspectRatio;
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
      CameraStyle.values[styleIndex.clamp(0, CameraStyle.values.length - 1)];
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
    case CameraStyle.soft:
      cropped = img.adjustColor(cropped, saturation: .88, contrast: .94);
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
  CameraStyle.soft => const [
    .94,
    .03,
    .03,
    0,
    4,
    .03,
    .94,
    .03,
    0,
    4,
    .03,
    .03,
    .94,
    0,
    4,
    0,
    0,
    0,
    1,
    0,
  ],
};

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 230,
      height: 230,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFFD60A), width: 2),
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.topCenter,
      child: const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          '将二维码或条形码放入框内',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
      ),
    ),
  );
}

class _BarcodeResultCard extends StatelessWidget {
  const _BarcodeResultCard({
    required this.value,
    required this.type,
    required this.onCopy,
    required this.onOpen,
  });

  final String value;
  final String? type;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(value);
    final isLink =
        uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF21C1C1E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            const Icon(Icons.qr_code_2, color: Color(0xFFFFD60A)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    type == null ? '已识别' : '已识别 · $type',
                    style: const TextStyle(color: Colors.white60, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '复制',
              onPressed: onCopy,
              icon: const Icon(Icons.copy, color: Colors.white),
            ),
            if (isLink)
              IconButton(
                tooltip: '安全打开',
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, color: Color(0xFFFFD60A)),
              ),
          ],
        ),
      ),
    );
  }
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
    this.prioritizeSuggestion = false,
  });
  final double zoom;
  final double brightness;
  final double motionLevel;
  final String suggestion;
  final bool prioritizeSuggestion;
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
            prioritizeSuggestion
                ? suggestion
                : brightness < 58 && motionLevel > .45
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
    required this.red,
    required this.green,
    required this.blue,
    required this.highlightThreshold,
    required this.highlightClipping,
    required this.shadowClipping,
  });

  final List<double> values;
  final List<double> red;
  final List<double> green;
  final List<double> blue;
  final double highlightThreshold;
  final double highlightClipping;
  final double shadowClipping;

  @override
  Widget build(BuildContext context) {
    final warning = highlightClipping > .08
        ? '高光溢出 · ${(highlightThreshold * 100).round()}%'
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
              child: CustomPaint(
                painter: _HistogramPainter(
                  luminance: values,
                  red: red,
                  green: green,
                  blue: blue,
                ),
              ),
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
  const _HistogramPainter({
    required this.luminance,
    required this.red,
    required this.green,
    required this.blue,
  });

  final List<double> luminance;
  final List<double> red;
  final List<double> green;
  final List<double> blue;

  @override
  void paint(Canvas canvas, Size size) {
    if (luminance.isEmpty) return;
    final fill = Path()..moveTo(0, size.height);
    for (var index = 0; index < luminance.length; index++) {
      final x = index * size.width / (luminance.length - 1);
      fill.lineTo(x, size.height * (1 - luminance[index].clamp(0, 1)));
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = Colors.white.withValues(alpha: .16)
        ..style = PaintingStyle.fill,
    );
    _drawChannel(canvas, size, red, const Color(0xFFFF453A));
    _drawChannel(canvas, size, green, const Color(0xFF30D158));
    _drawChannel(canvas, size, blue, const Color(0xFF0A84FF));
  }

  void _drawChannel(
    Canvas canvas,
    Size size,
    List<double> values,
    Color color,
  ) {
    if (values.length < 2) return;
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final point = Offset(
        index * size.width / (values.length - 1),
        size.height * (1 - values[index].clamp(0, 1)),
      );
      index == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25,
    );
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) =>
      !listEquals(luminance, oldDelegate.luminance) ||
      !listEquals(red, oldDelegate.red) ||
      !listEquals(green, oldDelegate.green) ||
      !listEquals(blue, oldDelegate.blue);
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

/// 用高光采样点绘制斑马纹遮罩，Path 批量绘制以降低低端设备的绘制开销。
class _ZebraPainter extends CustomPainter {
  const _ZebraPainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final cell = math.max(5.0, math.min(size.width, size.height) / 55);
    final path = Path();
    for (final point in points) {
      final center = Offset(point.dx * size.width, point.dy * size.height);
      path.moveTo(center.dx - cell / 2, center.dy - cell / 2);
      path.lineTo(center.dx + cell / 2, center.dy + cell / 2);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: .5)
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.square,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: .85)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.square,
    );
  }

  @override
  bool shouldRepaint(covariant _ZebraPainter oldDelegate) =>
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

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({required this.diagnostics, required this.onCopy});

  final CameraDiagnostics diagnostics;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final initialization = diagnostics.initializationMs == null
        ? '未完成'
        : '${diagnostics.initializationMs} ms';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF28282B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bug_report_outlined,
                size: 15,
                color: Color(0xFFFFD60A),
              ),
              const SizedBox(width: 6),
              const Text(
                '诊断',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 13),
                label: const Text('复制报告'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFD60A),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          Text(
            '初始化 $initialization · ${diagnostics.initializationStage ?? 'idle'}'
            ' · 分析 ${diagnostics.analysisFps.toStringAsFixed(1)} fps',
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            '存储可用 ${_formatMb(diagnostics.freeStorageMb)}'
            ' · 内存可用 ${_formatMb(diagnostics.availableMemoryMb)}'
            ' · 温度 ${_thermalLabel(diagnostics.thermalStatus)}',
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          if (diagnostics.warnings.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '预警：${diagnostics.warnings.join('、')}',
              style: const TextStyle(
                color: Color(0xFFFF9F0A),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (diagnostics.degraded.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '降级：${diagnostics.degraded.join('、')}',
              style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 10),
            ),
          ],
          if (diagnostics.lastError != null &&
              diagnostics.lastError!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '最近错误：${diagnostics.lastError}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ],
      ),
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

class _PhysicalLensSelector extends StatelessWidget {
  const _PhysicalLensSelector({
    required this.lenses,
    required this.activeId,
    required this.onSelected,
  });

  final List<NativeCameraLens> lenses;
  final String? activeId;
  final ValueChanged<NativeCameraLens> onSelected;

  @override
  Widget build(BuildContext context) {
    final sorted = [...lenses]
      ..sort((a, b) => a.nominalZoom.compareTo(b.nominalZoom));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final lens in sorted)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: Text('${_zoomLabel(lens.nominalZoom)}×'),
              selected:
                  activeId == lens.id || activeId?.contains(lens.id) == true,
              onSelected: (_) => onSelected(lens),
              selectedColor: const Color(0xFFFFD60A),
              backgroundColor: const Color(0xFF2C2C2E),
              labelStyle: TextStyle(
                color:
                    activeId == lens.id || activeId?.contains(lens.id) == true
                    ? Colors.black
                    : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  String _zoomLabel(double zoom) => zoom >= 1 && zoom.roundToDouble() == zoom
      ? zoom.toStringAsFixed(0)
      : zoom.toStringAsFixed(1);
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
    } else if (guide == CompositionGuide.symmetry) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    } else if (guide == CompositionGuide.leadingLine) {
      final horizon = size.height * .38;
      canvas.drawLine(Offset(0, horizon), Offset(size.width, horizon), paint);
      canvas.drawLine(
        Offset(0, size.height),
        Offset(size.width * .46, horizon),
        paint,
      );
      canvas.drawLine(
        Offset(size.width, size.height),
        Offset(size.width * .54, horizon),
        paint,
      );
    } else if (guide == CompositionGuide.frame) {
      final rect = Rect.fromLTWH(
        size.width * .12,
        size.height * .12,
        size.width * .76,
        size.height * .76,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(18)),
        paint..strokeWidth = 2,
      );
    } else {
      const minor = .382;
      const major = .618;
      for (final x in [size.width * minor, size.width * major]) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (final y in [size.height * minor, size.height * major]) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.guide != guide;
}

String _compositionGuideName(CompositionGuide guide) => switch (guide) {
  CompositionGuide.thirds => '三分构图',
  CompositionGuide.center => '中心构图',
  CompositionGuide.symmetry => '对称构图',
  CompositionGuide.leadingLine => '引导线',
  CompositionGuide.frame => '框中框',
  CompositionGuide.goldenRatio => '黄金分割',
};

String _formatMb(int? value) {
  if (value == null) return '未知';
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} GB';
  return '$value MB';
}

String _thermalLabel(String? status) => switch (status) {
  'none' || 'nominal' => '正常',
  'light' || 'fair' => '轻微升温',
  'moderate' => '中度升温',
  'severe' || 'serious' => '高温',
  'critical' || 'emergency' || 'shutdown' => '过热',
  _ => '未知',
};

enum _PresetActionType { apply, copy, delete, saveCurrent }

class _PresetAction {
  const _PresetAction._(this.type, {this.preset});

  final _PresetActionType type;
  final CapturePreset? preset;
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

class _StabilityChip extends StatelessWidget {
  const _StabilityChip({required this.snapshot});

  final StabilitySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final guidance = snapshot.guidance;
    if (guidance == null) return const SizedBox.shrink();
    final stable = snapshot.stable;
    // 只在明显晃动或已经稳定可拍时出现，接近稳定时不打扰拍摄。
    if (!stable && snapshot.score >= 65) return const SizedBox.shrink();
    final color = stable ? const Color(0xFF30D158) : const Color(0xFFFFD60A);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              stable ? Icons.check_circle_outline : Icons.vibration,
              color: color,
              size: 13,
            ),
            const SizedBox(width: 5),
            Text(
              guidance,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
