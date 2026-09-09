import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

enum CompositionGuide { thirds, center, symmetry }

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage>
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
  Offset? _focusPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCameras());
  }

  Future<void> _loadCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('no-camera', '未检测到可用相机');
      await _initializeCamera(0);
    } on CameraException catch (error) {
      if (mounted) setState(() { _error = _cameraError(error); _initializing = false; });
    }
  }

  Future<void> _initializeCamera(int index) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    if (!mounted) return;
    setState(() { _initializing = true; _error = null; });
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    try {
      await controller.initialize();
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _zoom = _minZoom;
      _flashMode = FlashMode.off;
      await controller.setFlashMode(_flashMode);
      if (mounted) setState(() => _initializing = false);
    } on CameraException catch (error) {
      if (mounted) setState(() { _error = _cameraError(error); _initializing = false; });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _cameras.isNotEmpty) {
      final index = _cameras.indexOf(controller.description);
      unawaited(_initializeCamera(index < 0 ? 0 : index));
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _initializing) return;
    final current = _controller?.description;
    final index = _cameras.indexWhere((camera) => camera == current);
    await _initializeCamera((index + 1) % _cameras.length);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = _flashMode == FlashMode.off ? FlashMode.auto : _flashMode == FlashMode.auto ? FlashMode.always : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } on CameraException {
      if (mounted) _showMessage('当前设备不支持此闪光灯模式');
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      for (var value = _countdownSeconds; value > 0; value--) {
        if (!mounted) return;
        setState(() => _countdown = value);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (mounted) setState(() => _countdown = 0);
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _capturedImage = bytes);
    } on CameraException catch (error) {
      if (mounted) _showMessage(_cameraError(error));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _importPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _capturedImage = bytes);
  }

  Future<void> _focus(TapDownDetails details, BoxConstraints constraints) async {
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
    } on CameraException { /* Device does not support manual focus. */ }
  }

  Future<void> _setZoom(double scale) async {
    final controller = _controller;
    if (controller == null) return;
    final value = (_baseZoom * scale).clamp(_minZoom, _maxZoom).toDouble();
    await controller.setZoomLevel(value);
    if (mounted) setState(() => _zoom = value);
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

  String _cameraError(CameraException error) {
    if (error.code == 'CameraAccessDenied' || error.code == 'CameraAccessDeniedWithoutPrompt') return '需要相机权限才能拍摄，请在系统设置中允许访问';
    return error.description ?? '相机暂时不可用';
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
    _controller?.dispose();
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
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: ClipRRect(borderRadius: BorderRadius.circular(28), child: _buildPreview()))),
          _buildControls(),
        ]),
      ),
    );
  }

  Widget _buildTopBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Row(children: [
      IconButton(onPressed: _toggleFlash, icon: Icon(_flashIcon, color: Colors.white)),
      const Spacer(),
      TextButton(onPressed: () => setState(() => _showGuide = !_showGuide), child: Text(_showGuide ? _guideName : '构图线关闭', style: const TextStyle(color: Colors.white))),
      const Spacer(),
      IconButton(onPressed: _switchCamera, icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white)),
    ]),
  );

  Widget _buildPreview() {
    if (_initializing) return const ColoredBox(color: Color(0xFF242220), child: Center(child: CircularProgressIndicator(color: Colors.white)));
    if (_error != null) return ColoredBox(color: const Color(0xFF242220), child: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 45), const SizedBox(height: 14), Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)), const SizedBox(height: 18), OutlinedButton(onPressed: _loadCameras, child: const Text('重试'))]))));
    final controller = _controller!;
    return LayoutBuilder(builder: (context, constraints) => GestureDetector(
      onTapDown: (details) => _focus(details, constraints),
      onScaleStart: (_) => _baseZoom = _zoom,
      onScaleUpdate: (details) => _setZoom(details.scale),
      child: Stack(fit: StackFit.expand, children: [
        CameraPreview(controller),
        if (_showGuide) IgnorePointer(child: CustomPaint(painter: _GuidePainter(_guide))),
        if (_focusPoint != null) Positioned(left: _focusPoint!.dx - 25, top: _focusPoint!.dy - 25, child: const IgnorePointer(child: _FocusRing())),
        if (_countdown > 0) Center(child: Text('$_countdown', style: const TextStyle(color: Colors.white, fontSize: 92, fontWeight: FontWeight.w300))),
        Positioned(bottom: 18, left: 18, right: 18, child: _CameraTip(zoom: _zoom)),
      ]),
    ));
  }

  Widget _buildControls() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [0, 3, 10].map((seconds) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(seconds == 0 ? '关闭' : '$seconds 秒'), selected: _countdownSeconds == seconds, onSelected: (_) => setState(() => _countdownSeconds = seconds)))).toList()),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _RoundAction(icon: Icons.photo_library_outlined, label: '相册', onTap: _importPhoto),
        GestureDetector(onTap: _capture, child: AnimatedContainer(duration: const Duration(milliseconds: 160), width: 74, height: 74, padding: const EdgeInsets.all(5), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: DecoratedBox(decoration: BoxDecoration(color: _capturing ? Colors.white38 : Colors.white, shape: BoxShape.circle)))),
        _RoundAction(icon: Icons.grid_3x3, label: '切换构图', onTap: () => setState(() => _guide = CompositionGuide.values[(_guide.index + 1) % CompositionGuide.values.length])),
      ]),
    ]),
  );

  Widget _buildReview() => Scaffold(
    backgroundColor: const Color(0xFF171615),
    body: SafeArea(child: Column(children: [
      const Padding(padding: EdgeInsets.all(18), child: Text('照片预览', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700))),
      Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.memory(_capturedImage!, fit: BoxFit.contain, width: double.infinity)))),
      Padding(padding: const EdgeInsets.all(22), child: Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => _capturedImage = null), child: const Text('重拍'))),
        const SizedBox(width: 12),
        Expanded(child: FilledButton.icon(onPressed: () => _showMessage('照片已准备好，可进入工作室编辑'), icon: const Icon(Icons.auto_fix_high), label: const Text('使用照片'))),
      ])),
    ])),
  );
}

class _FocusRing extends StatelessWidget {
  const _FocusRing();
  @override
  Widget build(BuildContext context) => Container(width: 50, height: 50, decoration: BoxDecoration(border: Border.all(color: Colors.amber, width: 1.5), borderRadius: BorderRadius.circular(4)));
}

class _CameraTip extends StatelessWidget {
  const _CameraTip({required this.zoom});
  final double zoom;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)), child: Row(children: [const Icon(Icons.auto_awesome, color: Colors.white, size: 16), const SizedBox(width: 8), const Expanded(child: Text('让主体靠近交叉点，画面会更有呼吸感', style: TextStyle(color: Colors.white, fontSize: 12))), Text('${zoom.toStringAsFixed(1)}×', style: const TextStyle(color: Colors.white70, fontSize: 12))]));
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Padding(padding: const EdgeInsets.all(9), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 24), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))])));
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.guide);
  final CompositionGuide guide;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .48)..strokeWidth = 1..style = PaintingStyle.stroke;
    if (guide == CompositionGuide.thirds) {
      for (final x in [size.width / 3, size.width * 2 / 3]) { canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint); }
      for (final y in [size.height / 3, size.height * 2 / 3]) { canvas.drawLine(Offset(0, y), Offset(size.width, y), paint); }
    } else if (guide == CompositionGuide.center) {
      canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 44, paint);
    } else {
      canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) => oldDelegate.guide != guide;
}
