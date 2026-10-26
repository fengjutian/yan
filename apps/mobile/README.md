# 颜 Studio — Flutter 独立客户端

v1 的形态是 **本地功能完整 + BYOK 可选 + 云端预留**：

- 拍摄、编辑、模板、本地作品库、保存/分享不依赖后端。
- AI 文生图/人物参考/风格迁移由用户在 AI 设置中填入 MiniMax API Key，客户端直连。
- API Key 只保存在系统安全存储，不进入代码、日志或图片元数据。
- AI 生成内容默认带 `aigc_watermark`，分享水印不可关闭。
- 后端 Go 服务保留给未来的云端模式（异步任务、订阅、云同步），v1 不依赖它启动。

## 本地数据

- 作品元数据和图片保存在 App Support 目录的 `creations/` 下。
- 每件作品一个目录：`meta.json` + `image-N.jpg` + `thumb-N.jpg`。
- 删除作品/清除本地作品会同时删除图片与缩略图；收藏/草稿 ID 也会清理。

## 开发命令

```powershell
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
```

Android 模拟器访问宿主机后端默认使用 `10.0.2.2`。真机联调请把 `API_BASE_URL` 换成局域网 HTTPS 地址；Android 网络安全配置只放行 `10.0.2.2` 的明文流量。

## 构建

```powershell
flutter build apk --debug
flutter build appbundle --release
```

iOS 最低版本为 **15.5**（ML Kit 要求），Podfile 已固定平台版本。iOS 构建需要在 macOS 上执行：

```bash
cd apps/mobile
flutter pub get
cd ios && pod install
cd .. && flutter build ios
```

## 上架前仍需完成

- iOS `PrivacyInfo.xcprivacy` 已加入 Runner 资源；隐私营养标签和 App Store Connect 文案仍需按实际上架地区填写。
- AI 内容举报/反馈入口、年龄分级、用户协议/隐私政策链接。
- 若做订阅/Pro，需要 StoreKit 2 与恢复购买；BYOK 版本不提供外部购买 Key 的跳转。
- Android Data Safety、targetSdk、16 KB page size 与国内商店合规（软著/备案）。
- 真机验证 MiniMax Key 的端到端生成、失败重试和后台中断恢复。
