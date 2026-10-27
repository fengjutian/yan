import 'dart:math' as math;

import 'package:ai_image_studio/features/camera/data/camera_capabilities.dart';
import 'package:ai_image_studio/features/camera/data/capture_preset.dart';
import 'package:ai_image_studio/features/camera/data/manual_camera_controls.dart';
import 'package:flutter/material.dart';

/// 相机初始化失败或权限不足时的错误页。
class CameraErrorView extends StatelessWidget {
  const CameraErrorView({
    super.key,
    required this.message,
    required this.permissionPermanentlyDenied,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final String message;
  final bool permissionPermanentlyDenied;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => ColoredBox(
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
              message,
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: permissionPermanentlyDenied ? onOpenSettings : onRetry,
              child: Text(permissionPermanentlyDenied ? '前往系统设置' : '重试'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 相机设置面板的功能分类标签。点击切换分类，选中态使用主色高亮。
class CameraCategoryChip extends StatelessWidget {
  const CameraCategoryChip({
    super.key,
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
    borderRadius: BorderRadius.circular(99),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFD60A) : const Color(0xFF303033),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.black : Colors.white70,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    ),
  );
}

/// 相机设置行：左侧名称，右侧当前值，点击弹出可选项。
class CameraSettingRow extends StatelessWidget {
  const CameraSettingRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.white54),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right, size: 16, color: Colors.white30),
        ],
      ),
    ),
  );
}

/// 相机开关行：左侧名称，右侧开关，适合即时生效的开关项。
class CameraSwitchRow extends StatelessWidget {
  const CameraSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFFFFD60A),
          activeTrackColor: const Color(0x66FFD60A),
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: const Color(0xFF303033),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    ),
  );
}

/// AF 对焦框。`locked` 表示 AF 锁定，`exposureLocked` 表示 AE 也锁定。
class CameraFocusRing extends StatelessWidget {
  const CameraFocusRing({
    super.key,
    required this.locked,
    required this.exposureLocked,
  });

  final bool locked;
  final bool exposureLocked;

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
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          locked && exposureLocked
              ? 'AE/AF 锁定'
              : locked
              ? 'AF 锁定'
              : 'AF',
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
      ),
    ],
  );
}

/// 独立 AE 测光点。
class CameraMeteringRing extends StatelessWidget {
  const CameraMeteringRing({super.key, required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.lightBlueAccent, width: 1.5),
          shape: BoxShape.circle,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          locked ? 'AE 锁定' : 'AE',
          style: const TextStyle(
            color: Colors.lightBlueAccent,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
      ),
    ],
  );
}

/// 从焦点环拖出独立测光点的拖动柄。
class CameraMeteringDragHandle extends StatelessWidget {
  const CameraMeteringDragHandle({super.key, required this.onPanUpdate});

  final GestureDragUpdateCallback onPanUpdate;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '拖动设置独立测光点',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      onPanUpdate: onPanUpdate,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.lightBlueAccent, width: 1.2),
        ),
        child: const Icon(
          Icons.contrast,
          color: Colors.lightBlueAccent,
          size: 14,
        ),
      ),
    ),
  );
}

String cameraPresetRatioLabel(double ratio) {
  if ((ratio - 1).abs() < .01) return '1:1';
  if ((ratio - .75).abs() < .01) return '3:4';
  if ((ratio - .5625).abs() < .01) return '9:16';
  if ((ratio - 16 / 9).abs() < .01) return '16:9';
  return ratio.toStringAsFixed(2);
}

String cameraPresetGuideLabel(String guide) => switch (guide) {
  'center' => '中心',
  'symmetry' => '对称',
  'leadingLine' => '引导线',
  'frame' => '框中框',
  'goldenRatio' => '黄金分割',
  _ => '三分',
};

String cameraPresetEnhancementLabel(String enhancement) =>
    switch (enhancement) {
      'multiFrameHdr' => 'HDR',
      'nightDenoise' => '夜景降噪',
      _ => '标准',
    };

String cameraPresetStyleLabel(String style) => switch (style) {
  'vivid' => '鲜明',
  'warm' => '暖色',
  'cool' => '冷色',
  'mono' => '黑白',
  'soft' => '柔和',
  _ => '标准',
};

class CameraPresetSectionLabel extends StatelessWidget {
  const CameraPresetSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class CameraPresetTile extends StatelessWidget {
  const CameraPresetTile({
    super.key,
    required this.preset,
    required this.active,
    required this.onTap,
    this.trailing,
  });

  final CapturePreset preset;
  final bool active;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: active ? const Color(0xFF2E2E31) : const Color(0xFF252527),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? const Color(0xFFFFD60A) : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF343437),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_motion,
                  color: Color(0xFFFFD60A),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cameraPresetRatioLabel(preset.aspectRatio)} · '
                      '${cameraPresetGuideLabel(preset.guide)} · '
                      '${preset.burstCount > 1 ? '${preset.burstCount} 张连拍' : '单拍'} · '
                      '${cameraPresetEnhancementLabel(preset.enhancement)} · '
                      '${cameraPresetStyleLabel(preset.style)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.check_circle,
                    color: Color(0xFFFFD60A),
                    size: 18,
                  ),
                ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    ),
  );
}

/// 场景预设选择面板。通过回调把“应用/复制/删除/保存当前”交给页面处理，
/// 方便独立做 widget 回归测试。
class CameraPresetSheet extends StatelessWidget {
  const CameraPresetSheet({
    super.key,
    required this.builtIn,
    required this.custom,
    required this.activeId,
    required this.onApply,
    required this.onCopy,
    required this.onDelete,
    required this.onSaveCurrent,
  });

  final List<CapturePreset> builtIn;
  final List<CapturePreset> custom;
  final String? activeId;
  final ValueChanged<CapturePreset> onApply;
  final ValueChanged<CapturePreset> onCopy;
  final ValueChanged<CapturePreset> onDelete;
  final VoidCallback onSaveCurrent;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 8, 4),
            child: Row(
              children: [
                const Text(
                  '场景拍摄预设',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onSaveCurrent,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('保存当前'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                const CameraPresetSectionLabel('内置预设'),
                for (final preset in builtIn)
                  CameraPresetTile(
                    preset: preset,
                    active: preset.id == activeId,
                    onTap: () => onApply(preset),
                    trailing: IconButton(
                      tooltip: '复制为自定义预设',
                      onPressed: () => onCopy(preset),
                      icon: const Icon(
                        Icons.copy_all_outlined,
                        color: Colors.white54,
                        size: 19,
                      ),
                    ),
                  ),
                if (custom.isNotEmpty) ...[
                  const CameraPresetSectionLabel('我的预设'),
                  for (final preset in custom)
                    CameraPresetTile(
                      preset: preset,
                      active: preset.id == activeId,
                      onTap: () => onApply(preset),
                      trailing: IconButton(
                        tooltip: '删除自定义预设',
                        onPressed: () => onDelete(preset),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white38,
                          size: 19,
                        ),
                      ),
                    ),
                ],
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 10, 8, 0),
                  child: Text(
                    '复制内置预设或保存当前设置，即可拥有自己的场景参数。',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
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

/// 专业参数能力标签。不支持时置灰并划线，避免用户误以为可以调节。
class CameraParameterChip extends StatelessWidget {
  const CameraParameterChip({
    super.key,
    required this.label,
    required this.enabled,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: enabled ? '当前镜头支持' : '当前镜头不支持',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF303033),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: enabled ? Colors.white24 : Colors.white10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: enabled ? Colors.white70 : Colors.white24,
          fontSize: 10,
          decoration: enabled ? null : TextDecoration.lineThrough,
          decorationColor: Colors.white24,
        ),
      ),
    ),
  );
}

class CameraProfessionalPanel extends StatelessWidget {
  const CameraProfessionalPanel({
    super.key,
    required this.lens,
    required this.exposure,
    required this.minExposure,
    required this.maxExposure,
    required this.onExposureChanged,
  });

  final NativeCameraLens? lens;
  final double exposure;
  final double minExposure;
  final double maxExposure;
  final ValueChanged<double> onExposureChanged;

  @override
  Widget build(BuildContext context) {
    final currentLens = lens;
    final hasExposureControl = maxExposure - minExposure > .01;
    final parameters = <CameraParameterChip>[
      CameraParameterChip(
        label: currentLens == null
            ? 'ISO'
            : 'ISO ${currentLens.minIso.round()}–${currentLens.maxIso.round()}',
        enabled:
            currentLens != null &&
            currentLens.supportsManualControls &&
            currentLens.maxIso > 0,
      ),
      CameraParameterChip(
        label: currentLens == null
            ? '快门'
            : '快门 ${_shutterLabel(currentLens.minExposureSeconds)}–'
                  '${_shutterLabel(currentLens.maxExposureSeconds)}',
        enabled:
            currentLens != null &&
            currentLens.supportsManualControls &&
            currentLens.maxExposureSeconds > 0,
      ),
      CameraParameterChip(
        label: '手动对焦',
        enabled:
            currentLens?.supportsManualControls == true &&
            currentLens?.supportsManualFocus == true,
      ),
      CameraParameterChip(
        label: 'RAW/DNG',
        enabled: currentLens?.supportsRaw == true,
      ),
    ];
    final anyEnabled = parameters.any((chip) => chip.enabled);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
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
              const Icon(Icons.tune, size: 15, color: Color(0xFFFFD60A)),
              const SizedBox(width: 6),
              const Text(
                '专业控制',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                currentLens == null ? '能力检测中' : _lensLabel(currentLens),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (!anyEnabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                currentLens == null ? '当前镜头未报告专业参数' : '当前相机实现未开放手动参数',
                style: const TextStyle(color: Colors.white60, fontSize: 10),
              ),
            ),
          Wrap(spacing: 6, runSpacing: 6, children: parameters),
          if (hasExposureControl) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    'EV ${exposure >= 0 ? '+' : ''}${exposure.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                    ),
                    child: Slider(
                      value: exposure.clamp(minExposure, maxExposure),
                      min: minExposure,
                      max: maxExposure,
                      activeColor: const Color(0xFFFFD60A),
                      inactiveColor: Colors.white24,
                      onChanged: onExposureChanged,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _lensLabel(NativeCameraLens lens) {
    final type = switch (lens.type) {
      'ultra-wide' => '超广角',
      'telephoto' => '长焦',
      'front' || 'true-depth' => '前摄',
      _ => '主摄',
    };
    final zoom = lens.nominalZoom.toStringAsFixed(
      lens.nominalZoom.roundToDouble() == lens.nominalZoom ? 0 : 1,
    );
    return '$type $zoom×';
  }

  static String _shutterLabel(double seconds) {
    if (seconds <= 0) return '—';
    if (seconds < 1) return '1/${(1 / seconds).round()}s';
    return '${seconds.toStringAsFixed(seconds >= 10 ? 0 : 1)}s';
  }
}

/// 手动专业参数面板。
///
/// 只有原生能力检测确认支持时才展示可调滑杆；Android CameraX 目前会
/// 传入不支持原因，面板只显示说明，避免出现可点但无效的控件。
class CameraManualControls extends StatelessWidget {
  const CameraManualControls({
    super.key,
    required this.supported,
    required this.range,
    required this.settings,
    required this.unavailableReason,
    required this.onChanged,
    required this.onReset,
  });

  final bool supported;
  final ManualCameraRange range;
  final ManualCameraSettings settings;
  final String? unavailableReason;
  final ValueChanged<ManualCameraSettings> onChanged;
  final VoidCallback onReset;

  bool get _usable => supported && range.isUsable;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
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
              Icons.movie_filter_outlined,
              size: 15,
              color: Color(0xFFFFD60A),
            ),
            const SizedBox(width: 6),
            const Text(
              '手动参数',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (_usable)
              TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11),
                ),
                child: const Text('重置'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (!_usable)
          Text(
            unavailableReason?.isNotEmpty == true
                ? unavailableReason!
                : '当前镜头没有可用的手动参数范围',
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          )
        else ...[
          Row(
            children: [
              _modeChip('自动', ManualCameraMode.auto),
              const SizedBox(width: 6),
              _modeChip('半自动', ManualCameraMode.semi),
              const SizedBox(width: 6),
              _modeChip('全手动', ManualCameraMode.manual),
            ],
          ),
          if (settings.mode == ManualCameraMode.manual) ...[
            _sliderRow(
              context,
              label: 'ISO',
              value: settings.iso.round().toString(),
              position: _logPosition(settings.iso, range.minIso, range.maxIso),
              onChanged: (position) => _emit(
                settings.copyWith(
                  iso: _logValue(position, range.minIso, range.maxIso),
                ),
              ),
            ),
            _sliderRow(
              context,
              label: '快门',
              value: _formatShutter(settings.shutterSeconds),
              position: _logPosition(
                settings.shutterSeconds,
                range.minShutterSeconds,
                range.maxShutterSeconds,
              ),
              onChanged: (position) => _emit(
                settings.copyWith(
                  shutterSeconds: _logValue(
                    position,
                    range.minShutterSeconds,
                    range.maxShutterSeconds,
                  ),
                ),
              ),
            ),
          ],
          if (settings.mode != ManualCameraMode.auto) ...[
            _sliderRow(
              context,
              label: '白平衡',
              value: '${settings.kelvin.round()}K',
              position: _linearPosition(
                settings.kelvin,
                range.minKelvin,
                range.maxKelvin,
              ),
              onChanged: (position) => _emit(
                settings.copyWith(
                  kelvin: _linearValue(
                    position,
                    range.minKelvin,
                    range.maxKelvin,
                  ),
                ),
              ),
            ),
            _sliderRow(
              context,
              label: '对焦',
              value: settings.focus.toStringAsFixed(2),
              position: settings.focus,
              onChanged: (position) =>
                  _emit(settings.copyWith(focus: position)),
            ),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              '手动模式下 HDR/夜景会使用标准单拍，避免曝光参数冲突。',
              style: TextStyle(color: Colors.white38, fontSize: 9),
            ),
          ),
        ],
      ],
    ),
  );

  void _emit(ManualCameraSettings next) => onChanged(next.clamped(range));

  Widget _modeChip(String label, ManualCameraMode mode) {
    final selected = settings.mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _emit(settings.copyWith(mode: mode)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFD60A) : const Color(0xFF303033),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sliderRow(
    BuildContext context, {
    required String label,
    required String value,
    required double position,
    required ValueChanged<double> onChanged,
  }) => Row(
    children: [
      SizedBox(
        width: 44,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: position.clamp(0.0, 1.0),
            activeColor: const Color(0xFFFFD60A),
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
      ),
      SizedBox(
        width: 52,
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ),
    ],
  );

  static double _logPosition(double value, double min, double max) {
    final safeMin = math.max(min, 1e-6);
    final safeMax = math.max(max, safeMin * 1.0001);
    final clamped = value.clamp(safeMin, safeMax);
    return (math.log(clamped) - math.log(safeMin)) /
        (math.log(safeMax) - math.log(safeMin));
  }

  static double _logValue(double position, double min, double max) {
    final safeMin = math.max(min, 1e-6);
    final safeMax = math.max(max, safeMin * 1.0001);
    final t = position.clamp(0.0, 1.0);
    return math.exp(
      math.log(safeMin) + t * (math.log(safeMax) - math.log(safeMin)),
    );
  }

  static double _linearPosition(double value, double min, double max) =>
      max <= min ? 0 : ((value - min) / (max - min)).clamp(0.0, 1.0);

  static double _linearValue(double position, double min, double max) =>
      min + (max - min) * position.clamp(0.0, 1.0);

  static String _formatShutter(double seconds) {
    if (seconds <= 0) return '—';
    if (seconds < 1) return '1/${(1 / seconds).round()}s';
    return '${seconds.toStringAsFixed(seconds >= 10 ? 0 : 1)}s';
  }
}
