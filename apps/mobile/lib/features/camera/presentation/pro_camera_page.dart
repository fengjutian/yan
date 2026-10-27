import 'dart:async';
import 'dart:typed_data';

import 'package:ai_image_studio/features/camera/data/manual_camera_controls.dart';
import 'package:ai_image_studio/features/camera/data/pro_camera_service.dart';
import 'package:ai_image_studio/features/camera/presentation/camera_widgets.dart';
import 'package:flutter/material.dart';

/// Android 原生专业模式验证页。
///
/// P0 验证纹理预览和自动拍照；P1 起接入 ISO/快门/白平衡/对焦。
class ProCameraPage extends StatefulWidget {
  const ProCameraPage({super.key, this.lensId});

  final String? lensId;

  @override
  State<ProCameraPage> createState() => _ProCameraPageState();
}

class _ProCameraPageState extends State<ProCameraPage> {
  final ProCameraService _service = ProCameraService();
  ProCameraSessionInfo? _info;
  String? _error;
  Uint8List? _captured;
  bool _loading = true;
  bool _capturing = false;
  bool _canPop = false;
  bool _closing = false;
  ManualCameraSettings _manualSettings = ManualCameraSettings.auto;
  Timer? _manualTimer;
  bool _applyingManual = false;
  ManualCameraSettings? _pendingManual;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _manualTimer?.cancel();
    if (!_closing) unawaited(_service.close());
    super.dispose();
  }

  Future<void> _closeAndPop() async {
    if (_closing) return;
    _closing = true;
    await _service.close();
    if (!mounted) return;
    setState(() => _canPop = true);
    // 等 PopScope 收到 canPop 更新后再主动 pop，避免被拦截。
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _service.open(lensId: widget.lensId);
      if (!mounted) {
        await _service.close();
        return;
      }
      setState(() {
        _info = info;
        _manualSettings = ManualCameraSettings.auto.clamped(info.manualRange);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final bytes = await _service.capture();
      if (!mounted) return;
      setState(() => _captured = bytes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('专业模式拍照失败：$error')));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _updateManual(ManualCameraSettings settings) {
    final info = _info;
    if (info == null || !info.supportsManual) return;
    final next = settings.clamped(info.manualRange);
    setState(() => _manualSettings = next);
    _manualTimer?.cancel();
    _manualTimer = Timer(const Duration(milliseconds: 120), () {
      unawaited(_applyManual(next));
    });
  }

  Future<void> _applyManual(ManualCameraSettings settings) async {
    if (_applyingManual) {
      _pendingManual = settings;
      return;
    }
    _applyingManual = true;
    try {
      await _service.setManual(settings);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('手动参数应用失败：$error')));
      setState(() {
        _manualSettings = _manualSettings.copyWith(mode: ManualCameraMode.auto);
      });
    } finally {
      _applyingManual = false;
      final pending = _pendingManual;
      _pendingManual = null;
      if (pending != null && mounted) {
        unawaited(_applyManual(pending));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_closeAndPop());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_info != null) _buildPreview(_info!),
              if (_loading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (_error != null) _buildError(_error!),
              Positioned(
                left: 8,
                top: 4,
                child: IconButton(
                  tooltip: '返回',
                  onPressed: () => unawaited(_closeAndPop()),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
              if (_info != null && _info!.supportsManual && _captured == null)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 104,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: SingleChildScrollView(
                      child: CameraManualControls(
                        supported: true,
                        range: _info!.manualRange,
                        settings: _manualSettings,
                        unavailableReason: null,
                        onChanged: _updateManual,
                        onReset: () => _updateManual(ManualCameraSettings.auto),
                      ),
                    ),
                  ),
                ),
              if (_info != null && _captured == null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: GestureDetector(
                      onTap: _capture,
                      child: Container(
                        width: 74,
                        height: 74,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _capturing ? Colors.white38 : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_captured != null) _buildCaptured(_captured!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(ProCameraSessionInfo info) {
    final turns = (info.sensorOrientation ~/ 90) % 4;
    final aspect = turns.isOdd ? 1 / info.aspectRatio : info.aspectRatio;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: RotatedBox(
          quarterTurns: turns,
          child: Texture(textureId: info.textureId),
        ),
      ),
    );
  }

  Widget _buildError(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_outlined,
            color: Colors.white70,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _open, child: const Text('重试')),
        ],
      ),
    ),
  );

  Widget _buildCaptured(Uint8List bytes) => Positioned.fill(
    child: ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'P0 拍摄结果',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _captured = null),
                    child: const Text('继续拍摄'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => unawaited(_closeAndPop()),
                    child: const Text('退出专业模式'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
