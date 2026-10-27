# Android 原生专业相机模式技术方案

> 状态：Draft  
> 目标：为 Android 补齐 ISO、快门、白平衡、手动对焦和 RAW 扩展能力，解决 `camera_android_camerax` 只暴露 EV/对焦/变焦的问题。  
> 前置结论：不直接改插件源码，也不建议一开始手写 Camera2 会话；优先用 CameraX + `Camera2Interop` 自建一个独立的“专业模式”会话。

## 1. 背景与约束

当前 Android 相机使用 `camera` 插件的 `camera_android_camerax` 实现：

- 预览、拍照、图像分析共用一个 `ResolutionPreset`。
- 插件只封装了 `CONTROL_AE_LOCK` 和视频防抖两个 `CaptureRequest.Key`。
- ISO、快门、白平衡、手动焦距需要 `CaptureRequest` 的传感器/色彩 key，插件没有暴露。
- 因此现有 `yan.camera/manual` 通道在 Android 上只能返回“不支持”。

约束：

1. 不能同时打开两个相机会话：专业模式启动前必须完全释放插件持有的 `CameraController`。
2. 现有 Flutter 相机页、图像处理、选片、作品库和 iOS 手动参数都要继续可用。
3. 首期不要求专业模式保留实时姿态/直方图等分析能力；这些可以后续用 CameraX `ImageAnalysis` 补。
4. 必须可回滚：功能开关关闭时，行为与当前版本完全一致。

## 2. 方案对比

| 方案 | 优点 | 代价 | 结论 |
|---|---|---|---|
| 修改/派生 `camera_android_camerax` 插件 | 复用插件会话 | 需要维护大型 fork，Pigeon 生成代码难改，升级插件即冲突 | 不选 |
| 原生 Camera2 手写会话 | 控制最完整，RAW 最直接 | 自己处理会话状态、旋转、对焦、JPEG、生命周期，约 800～1200 行，回归风险最高 | 二期备选 |
| CameraX + `Camera2Interop` 自建专业会话 | 复用 CameraX 的设备选择/生命周期/拍照/EXIF，少量代码即可设置任意 CaptureRequest | 需要与插件会话互斥切换；高级 RAW/多帧仍受限 | **首选** |
| 仅 iOS 手动参数 | 已完成，成本最低 | Android 用户无专业参数 | 作为当前兜底 |

关键点：CameraX 本身支持 `Camera2CameraControl.addCaptureRequestOptions()`，可以动态下发任意 `CaptureRequest.Key`。之前被卡住的是“插件没有暴露”，不是 CameraX 不支持。

## 3. 推荐架构

```text
Flutter CameraPage
├── CameraBackend（Dart 抽象，二选一）
│   ├── PluginCameraBackend（现有 camera 插件，普通模式）
│   └── ProCameraBackend（Android 原生专业模式）
├── CameraManualControls（已存在，复用）
└── 现有拍照后处理（裁剪/风格/质量评分/选片）

Android
├── ProCameraChannel（MethodChannel: yan.camera/pro）
├── ProCameraSession（CameraX 会话：Preview + ImageCapture）
├── ManualRequestController（Camera2CameraControl + CaptureRequestOptions）
├── WhiteBalanceConverter（Kelvin -> Rggb gains）
└── ProPreviewTexture（SurfaceProducer）
```

### 3.1 原生会话

- 使用应用内自己的 `ProcessCameraProvider`，不依赖插件内部实例。
- 绑定：
  - `Preview`：`Preview.SurfaceProvider` 输出到 `TextureRegistry.SurfaceProducer`。
  - `ImageCapture`：`OutputFileOptions` 写入缓存目录，返回 JPEG 路径。
  - `ImageAnalysis`（二期）：给实时分析用。
- `ResolutionSelector`：专业模式默认 4:3 或 16:9 的高分辨率（如 1920×1080 起，按设备能力提升），与现有 720p/1080p 策略分开。
- 方向：交给 CameraX `targetRotation`；JPEG 保留 EXIF，Dart 侧现有 `img.bakeOrientation` 可继续用。

### 3.2 手动参数

| 参数 | Camera2 key | 说明 |
|---|---|---|
| ISO | `SENSOR_SENSITIVITY` | 需 `CONTROL_AE_MODE_OFF`；范围来自 `SENSOR_INFO_SENSITIVITY_RANGE` |
| 快门 | `SENSOR_EXPOSURE_TIME` | 纳秒；范围来自 `SENSOR_INFO_EXPOSURE_TIME_RANGE` |
| 白平衡 | `CONTROL_AWB_MODE_OFF` + `COLOR_CORRECTION_GAINS` | Kelvin 转 Rggb gains，按 `maxWhiteBalanceGain` 类似逻辑夹紧 |
| 对焦 | `CONTROL_AF_MODE_OFF` + `LENS_FOCUS_DISTANCE` | 屈光度；0 为无穷远，上限来自 `LENS_INFO_MINIMUM_FOCUS_DISTANCE` |
| EV | `CONTROL_AE_EXPOSURE_COMPENSATION` | 仅自动/半自动模式启用 |

模式定义与 iOS 保持一致：

- **自动**：AE/AWB/AF 全自动。
- **半自动**：AE 自动，AWB 和 AF 锁定。
- **全手动**：AE 关闭，ISO/快门/AWB/AF 全部手动。

下发方式：

1. 会话启动时通过 `Camera2Interop.Extender` 给 Preview/ImageCapture 设置初始 options。
2. 参数变化时通过 `Camera2CameraControl.from(camera.cameraControl).addCaptureRequestOptions(...)` 动态更新，避免重建会话。
3. 每次 apply 前按当前镜头 characteristics 夹紧，非法值直接拒绝而不是让会话崩溃。

### 3.3 Kelvin → gains

Android 没有直接的色温接口，需要把 Kelvin 转成 `RggbChannelVector`：

- 用 Planckian locus 近似（Tanner Helland 或 CIE 近似）得到 RGB 白点。
- 转成 R/G/B 增益，绿色归一化为 1。
- 按设备 `COLOR_CORRECTION_GAINS` 的可接受范围夹紧。
- 同一色温在不同模组上会有偏差，首期以“可用”为目标，后续可用灰卡校准表修正。

## 4. 原生通道契约

通道：`yan.camera/pro`（Android only；其他平台返回 `notImplemented`）。

```text
getCapabilities() -> {
  supported: bool,
  reason?: string,
  lenses: [{
    id, facing, focalLengths,
    minIso, maxIso,
    minExposureSeconds, maxExposureSeconds,
    minFocusDiopters, maxFocusDiopters,
    minKelvin, maxKelvin,
    supportsRaw, hardwareLevel
  }]
}

open({ lensId, aspectRatio }) -> {
  textureId: int,
  width: int, height: int,
  sensorOrientation: int,
  minZoom: double, maxZoom: double
}

setManual({
  mode: "auto" | "semi" | "manual",
  iso, shutterSeconds, kelvin, focus
}) -> void

setZoom({ zoom }) -> void
setFocusPoint({ x, y }) -> void   // 自动/半自动模式下可用
capture() -> { path: string, width: int, height: int }
pause() / resume() -> void
close() -> void
```

错误通过 `PlatformException` 返回，错误码至少区分：

- `pro-unsupported`
- `camera-in-use`
- `invalid-parameter`
- `capture-failed`
- `session-closed`

## 5. 与 Flutter 相机页的集成

### 5.1 模式切换

```text
普通模式（插件） --用户开启专业模式--> 释放 CameraController
    -> pro.open(lensId) -> Texture(textureId) -> 专业 UI
专业模式 --退出--> pro.close() -> 重新创建 CameraController -> 普通模式
```

要求：

- 用一个 `CameraMode` 状态机和 token 防止快速切换导致双开。
- 切换期间显示 loading，禁用快门/镜头/比例按钮。
- 专业模式下隐藏依赖图像流的实时分析入口（姿态、斑马纹、直方图、峰值对焦）；保留构图线、水平仪、网格等纯 UI 能力。
- 返回键/路由退出/切后台时先 `pro.close()`，再按现有生命周期逻辑处理。

### 5.2 拍照后处理复用

- `pro.capture()` 返回 JPEG 路径/字节后，走现有 `_processPhoto`（裁剪、风格、镜像）和 `CameraSession.setPhotos`（质量评分、去重、选片）。
- 专业模式下默认关闭 HDR/夜景多帧，避免与手动曝光冲突。
- 保留“保存原图”开关；专业模式原图即手动参数直出。

### 5.3 能力与 UI

- 复用已完成的 `CameraManualControls`：
  - `supportsManualControls` 由 `pro.getCapabilities()` 提供。
  - 范围、模式、滑杆与 iOS 完全一致。
- 普通模式下 Android 仍显示当前“不支持”的提示；只有成功进入专业模式后才展示可调控件。

## 6. 生命周期与线程

- 原生会话持有自己的 `LifecycleOwner`（Activity 或自定义），在 `onPause` 停止预览、`onResume` 恢复；Dart 侧已有 `inactive/hidden/resumed` 和 RouteAware，可复用。
- CameraX 回调切到主线程；`capture` 的 `OnImageSavedCallback` 回到主线程再 `result.success`。
- `close()` 必须可重复调用，先解绑 use case，再释放 SurfaceProducer，最后关闭 provider。
- 权限被撤销、相机被其他应用占用时，返回明确错误码，Flutter 侧退回普通模式并提示。

## 7. 测试策略

### 7.1 Dart/单元

- Kelvin→gains 的边界与夹紧（可把算法放 Kotlin，用 JVM 单测覆盖）。
- 参数夹紧、模式切换、通道参数序列化。
- `CameraManualControls` 已有 widget 测试，补充专业模式状态。

### 7.2 Android 仪器/真机

- 打开/关闭专业模式 20 次，无 `camera-in-use`、无黑屏。
- 自动/半自动/全手动各拍 10 张，检查 JPEG 的 ISO/曝光时间 EXIF 与设置一致。
- 白平衡 2000K/5200K/8000K 出片色温方向正确。
- 对焦 0/0.5/1 三档远近变化可见。
- 前后摄、超广角/主摄/长焦切换；旋转屏幕；切后台/来电/锁屏。
- 低端机（4GB）连续拍 20 张的耗时、内存、发热。
- 普通模式回归：现有 116 个测试 + 相机冒烟。

### 7.3 设备矩阵

至少覆盖：

- Pixel（原生 Android）
- 小米/Redmi（低端 + 中端）
- OPPO/vivo（定制 ROM）
- 三星（多摄）
- API 26/29/33/35

## 8. 拆分计划

### P0：技术验证（1～2 天）

- 新建 `ProCameraSession`，只做 Preview 纹理 + 自动模式拍照。
- 验证与插件会话互斥切换、纹理方向、JPEG EXIF。
- 产出：能在一个调试页面打开/拍照/关闭的 demo。
- 决策点：纹理或会话释放不稳定则暂停，不进入 P1。

### P1：手动参数（2～3 天）

- `Camera2CameraControl` 下发 ISO/快门/WB/对焦。
- 能力范围解析、夹紧、错误码。
- Java/Kotlin 单测：Kelvin→gains、范围夹紧。
- 验收：EXIF 与设置一致；非法值不崩溃。

### P2：接入相机页（2 天）

- `ProCameraBackend` + 模式切换 UI（设置项/专业模式入口）。
- 复用后处理、选片、保存、作品库。
- 专业模式隐藏实时分析入口；HDR/夜景自动关闭。
- 功能开关默认关闭，内测白名单开启。

### P3：专业模式下的实时辅助（可选，2～3 天）

- 增加 `ImageAnalysis`，复用现有直方图/曝光/对焦峰值算法（需要把 Dart 侧算法迁到原生或通过事件流回传）。
- 如果成本过高，首期不做，专业模式以“取景 + 手动参数”为主。

### P4：稳定化与发布（2 天）

- 真机矩阵回归、低端机性能、生命周期、错误恢复。
- 诊断面板增加“专业模式/普通模式”和当前手动参数。
- 灰度开关、回滚验证。

总工期：**7～10 个工作日**（含 P3 则 9～13 天）。

## 9. 风险清单

| 风险 | 影响 | 缓解 |
|---|---|---|
| 两个相机会话切换时序 | 黑屏/`camera-in-use` | 单例模式状态机 + 等待 dispose 完成 + 重试一次 |
| CameraX 版本与插件不一致 | 类冲突/运行时崩溃 | 显式依赖 `camera-core/camera-camera2/camera-lifecycle:1.6.1`，与插件保持一致 |
| 厂商 ROM 忽略 CaptureRequest | 参数不生效 | 能力检测 + 真机矩阵 + 失败提示；必要时降级为 EV |
| 纹理旋转/镜像错误 | 预览方向不对 | 统一用 CameraX `targetRotation` + Flutter `Texture` 变换，前后摄分别验证 |
| Kelvin→gains 偏差 | 白平衡不准 | 首期方向正确即可，后续加机型校准表 |
| 专业模式无实时分析 | 功能回退感 | UI 明确提示；P3 再补 |
| RAW/DNG | 首期不可用 | 作为后续独立阶段，先保证 JPEG 手动参数 |
| 回滚 | 线上事故 | 功能开关 + 普通模式零改动；异常自动退回插件模式 |

## 10. 结论与建议

- **不要** fork `camera_android_camerax`，也**不要**首期手写 Camera2。
- 用 **CameraX + `Camera2Interop` 自建独立专业会话**，是成本、风险和可控性最平衡的方案。
- 先做 P0 技术验证；如果纹理预览和会话切换在目标机型上稳定，再投入 P1/P2。
- 在 P0/P1 完成前，Android 保持当前“明确提示不支持”的行为，不影响普通拍摄。

## 11. P0 当前进展（已完成代码骨架）

本次已落地：

- 原生 `ProCameraSession`：CameraX `Preview` + `ImageCapture`，通过 `TextureRegistry.SurfaceProducer` 输出纹理预览，`ImageCapture` 输出缓存 JPEG。
- `yan.camera/pro` 通道：`open` / `capture` / `close` / `isSupported`。
- Dart `ProCameraService` / `ProCameraSessionInfo`，以及调试页 `ProCameraPage`（`/debug/pro-camera`，仅 debug 构建从相机设置进入）。
- 相机页进入专业模式前释放 `camera` 插件 controller，返回后重新初始化，并处理了 RouteAware 与调试页的重复初始化竞争。
- `androidx.camera` 依赖固定为 `1.6.1`，与插件一致。

已验证：

- `:app:compileDebugKotlin` 构建通过。
- Dart analyzer 0 issue；全量测试通过。

待真机验证：

- 纹理预览方向/镜像是否正确。
- 进入/退出专业模式 20 次是否稳定，不出现 `camera-in-use`。
- 自动模式拍照 EXIF、JPEG 方向、缓存文件清理。
- 切后台/锁屏/来电后的纹理恢复。

P1 将在此基础上接入 `Camera2CameraControl` 的 ISO/快门/白平衡/对焦 key。
