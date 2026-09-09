import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

enum CompositionGuide { thirds, center, symmetry }

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final _picker = ImagePicker();
  Uint8List? _image;
  CompositionGuide _guide = CompositionGuide.thirds;
  bool _showGuide = true;

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 95);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _image = bytes);
  }

  void _nextGuide() {
    setState(() {
      _guide = CompositionGuide
          .values[(_guide.index + 1) % CompositionGuide.values.length];
    });
  }

  String get _guideName => switch (_guide) {
        CompositionGuide.thirds => '三分构图',
        CompositionGuide.center => '中心构图',
        CompositionGuide.symmetry => '对称构图',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171615),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(children: [
              const Text('AI 相机',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  onPressed: () => setState(() => _showGuide = !_showGuide),
                  icon: Icon(_showGuide ? Icons.grid_on : Icons.grid_off,
                      color: Colors.white)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(fit: StackFit.expand, children: [
                  if (_image == null)
                    const ColoredBox(
                        color: Color(0xFF2B2927),
                        child: Center(
                            child: Text('拍摄或导入一张照片',
                                style: TextStyle(color: Colors.white60))))
                  else
                    Image.memory(_image!, fit: BoxFit.cover),
                  if (_showGuide)
                    IgnorePointer(
                        child: CustomPaint(painter: _GuidePainter(_guide))),
                  Positioned(
                      top: 16,
                      left: 16,
                      child: GestureDetector(
                          onTap: _nextGuide,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(99)),
                              child: Text('$_guideName  ·  点击切换',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12))))),
                  const Positioned(
                      bottom: 18, left: 18, right: 18, child: _CameraTip()),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _RoundAction(
                      icon: Icons.photo_library_outlined,
                      label: '相册',
                      onTap: () => _pick(ImageSource.gallery)),
                  GestureDetector(
                      onTap: () => _pick(ImageSource.camera),
                      child: Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2)),
                          child: const DecoratedBox(
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle)))),
                  _RoundAction(
                      icon: Icons.refresh,
                      label: '重拍',
                      onTap: () => setState(() => _image = null)),
                ]),
          ),
        ]),
      ),
    );
  }
}

class _CameraTip extends StatelessWidget {
  const _CameraTip();
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
          color: Colors.black54, borderRadius: BorderRadius.circular(16)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome, color: Colors.white, size: 17),
        SizedBox(width: 8),
        Expanded(
            child: Text('让主体靠近交叉点，画面会更有呼吸感',
                style: TextStyle(color: Colors.white, fontSize: 12)))
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
          padding: const EdgeInsets.all(10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 25),
            const SizedBox(height: 5),
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
      ..strokeWidth = 1;
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
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 44,
          paint..style = PaintingStyle.stroke);
    } else {
      canvas.drawLine(Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height), paint);
      canvas.drawLine(
          const Offset(0, 0), Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.guide != guide;
}
