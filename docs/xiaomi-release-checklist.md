# 小米应用商店上架清单

> 项目：颜 Studio（`apps/mobile`，Flutter）
> 包名：`com.yan.ai.ai_image_studio`
> 版本：`1.0.0`（versionCode `1`）
> 更新：2026-10-27

本文分两部分：**A. 已经做完的（代码/构建侧）**，**B. 提审前必须补的（资质/材料侧）**。B 部分是当前唯一的阻塞项。

---

## A. 已完成

### 1. 签名

| 项目 | 值 |
| --- | --- |
| 密钥文件 | `apps/mobile/android/keystores/yan-upload.jks`（已 gitignore） |
| 密码配置 | `apps/mobile/android/key.properties`（已 gitignore） |
| Alias | `upload` |
| SHA-1 | `5D:61:C8:4E:9C:4F:12:E0:75:BD:89:CD:AE:21:C2:6A:B1:31:13:E2` |
| SHA-256 | `C1:B8:FE:FA:1F:12:2C:A3:24:8D:40:81:B9:77:0E:E1:0C:2E:13:31:F5:73:EE:9D:C0:CB:1C:51:6E:BF:FB:97` |
| 有效期 | 30 年 |

**立刻做离线备份**（jks + key.properties）。密钥丢失 = 该包名永远无法更新，只能换包名重新上架。

### 2. 构建配置

- `release` 开启 R8 混淆 + 资源压缩，规则见 `android/app/proguard-rules.pro`。
- 只打 `arm64-v8a` + `armeabi-v7a`（小米要求支持 64 位，纯 32 位包会被拒）。
- release 禁止明文 HTTP；`10.0.2.2` 明文例外只存在于 debug 资源。
- `minSdk` / `targetSdk` 沿用 Flutter 默认值，由 Flutter SDK 决定。

### 3. 本地优先（不依赖后端）

- release 默认关闭开发者后端：`ENABLE_BACKEND` 未显式打开时不发任何 API 请求，也不会建游客会话。
- 拍摄、编辑、模板、本地作品库、分享导出全部离线可用。
- AI 生成是 BYOK 模式：用户自己填 MiniMax / DeepSeek API Key，请求直连服务商。

### 4. 合规改动

- **首启隐私确认页**：`/consent`。同意后才进首页；不同意直接退出。同意前不申请权限、不联网。
- **隐私与协议页**：数据存储、第三方 AI 服务、AI 内容标识、设备权限逐项说明，并展示开发者主体与备案号（构建时注入）。
- **AI 内容标识**：生成图片带「AI 生成」水印，导出/分享默认保留，不提供移除开关（`aigc_watermark=true`）。
- **18+ 确认**：首次使用 AI 生成前弹年龄与内容合规确认。

### 5. 产物与校验

构建命令：

```powershell
cd apps\mobile
powershell -ExecutionPolicy Bypass -File tool\build_android_release.ps1 `
  -Beian "京ICP备2026xxxxxx号-2A" `
  -PrivacyPolicyUrl "https://你的域名/privacy.html" `
  -TermsUrl "https://你的域名/terms.html" `
  -SupportEmail "support@你的域名" `
  -DeveloperName "某某科技有限公司"
```

脚本会自动：校验签名密钥存在 → `flutter build apk --release` → `apksigner` 校验签名指纹 → `aapt2` 校验包名/版本/ABI → 归档到 `dist/android/` 并输出 SHA-256。

产物：`dist/android/yan-studio-v1.0.0-release.apk`

---

## B. 提审前必须补齐（阻塞项）

小米应用商店对「生成式 AI」类目审核较严，下面 1–4 项缺一项都会被驳回。

| # | 材料 | 具体要求 | 现状 |
| --- | --- | --- | --- |
| 1 | 小米开发者账号 | 企业认证：营业执照、法人身份信息、对公账户；个人开发者无法上架部分类目 | ❌ 待注册 |
| 2 | **APP 备案号** | 工信部 App 备案（通过接入商/云厂商提交），商店后台强校验；App 内也需可查 | ❌ 待办 |
| 3 | **软件著作权** | 《计算机软件著作权登记证书》扫描件；代理上架还需授权书 | ❌ 待办 |
| 4 | **在线《隐私政策》URL** | HTTPS 可公开访问，内容须与 App 实际行为一致。已生成可直接托管的静态页 `docs/publish/privacy.html` | ⚠️ 待托管 |
| 5 | 《用户协议》URL | 建议提供，商店页与 App 内都会展示。已生成 `docs/publish/terms.html` | ⚠️ 待托管 |
| 6 | 生成式 AI 资质说明 | 见下方「AI 类目特别说明」 | ⚠️ 需决策 |
| 7 | 应用图标 | 512×512 PNG | ✅ `dist/xiaomi/icon-512.png`（由品牌 logo 生成） |
| 8 | 应用截图 | 3–5 张，竖屏建议 1080×1920，PNG/JPG | ❌ 待截图 |
| 9 | 商店文案 | 一句话简介、应用简介、分类、年龄分级、更新日志 | ✅ 草稿见 `docs/xiaomi-store-listing.md` |
| 10 | 审核测试说明 | 说明 AI 功能需自备 API Key；否则审核员无法体验 | ⚠️ 见下 |

### AI 类目特别说明（重要）

App 不自己提供模型服务，而是「BYOK 客户端」：用户填入自己的 MiniMax / DeepSeek Key，请求由手机直连服务商。这个模式对审核有利也有风险：

- **有利**：不构成「提供生成式 AI 服务」，理论上不需要自己办大模型备案。
- **风险**：审核员没有 API Key，无法验收 AI 功能，容易以「功能不完整/无法体验」驳回。

三种处理方式，建议按投入排序：

1. **首审版本暂时隐藏 AI 生成入口**（保留拍摄/编辑/模板/本地作品），先过审，后续更新再放开 AI。改动最小、过审率最高。
2. 在「审核备注」里写明：AI 功能为进阶功能，需在「我的 → AI 设置」填入 MiniMax 或 DeepSeek 的 API Key；并提供一段 30 秒演示视频。审核员通常仍会要求账号。
3. 提供 MiniMax / DeepSeek 的备案信息 + 你与厂商的关系说明（通常只有正式合作/代理才走得通）。

> 决策建议：第一次提审走方式 1。等备案、软著都下来、并有明确的主体资质后，再发版本放开 AI。

---

## C. 商店后台填写

| 字段 | 建议值 |
| --- | --- |
| 应用名称 | 颜 Studio（必须与 APK 内 `android:label` 一致） |
| 包名 | `com.yan.ai.ai_image_studio` |
| 应用分类 | 摄影摄像 / 图片处理 |
| 年龄分级 | 18+（含 AI 生成内容） |
| 隐私政策 | 第 4 项的 HTTPS 链接 |
| 备案号 | 第 2 项的备案号 |
| 权限说明 | 见下方「权限清单」 |
| 更新日志 | 见 `docs/xiaomi-store-listing.md` |

### 权限清单（与 APK 实际声明保持一致）

| 权限 | 用途 | 触发时机 |
| --- | --- | --- |
| `android.permission.INTERNET` | 访问用户自备的 AI 服务商接口 | 用户主动使用 AI 功能时 |
| `android.permission.CAMERA` | 拍摄照片、取景与构图辅助 | 进入相机页时申请 |
| `android.permission.WRITE_EXTERNAL_STORAGE`（`maxSdkVersion=28`） | Android 9 及以下保存成片到相册 | 导出/保存时申请 |
| 运动传感器（非危险权限） | 水平仪与构图提示 | 相机页 |

> 提审前请用 `aapt2 dump permissions` 再核对一遍合并后的清单，第三方插件可能追加权限（例如相册读取）。

---

## D. 常见驳回原因与对应处理

| 驳回原因 | 本项目状态 |
| --- | --- |
| 没有隐私政策 / 首启未弹同意框 | ✅ 已加 `/consent` 首启页 |
| 同意前就申请权限、联网、收集设备信息 | ✅ 已隔离（首启无网络请求） |
| 隐私政策与实际收集行为不一致 | ✅ 政策文本按实际行为写，需随功能更新同步修改 |
| 缺少 APP 备案号 | ❌ 待补 |
| 缺少软件著作权 | ❌ 待补 |
| 功能不完整 / 无法体验 | ⚠️ AI 需自备 Key，建议首审隐藏入口 |
| 权限与功能不匹配 | ✅ 已收敛到 3 个权限 |
| AI 生成内容无标识 | ✅ 水印且不可关闭 |
| 应用名称与已上架应用重名/侵权 | ⚠️ 提审前在商店搜索「颜 Studio」查重 |
| 图标/截图不合规 | ⚠️ 图标已生成，截图待拍 |

---

## E. 每次发版的流程

1. 改 `apps/mobile/pubspec.yaml`：`version: 1.0.1+2`（versionCode 必须递增）。
2. 跑构建脚本（参数同上，备案号等可复用）。
3. 归档 `build/app/outputs/mapping/release/mapping.txt` 到 `dist/android/mapping-<version>.txt`（线上崩溃还原用，丢了就还原不了混淆栈）。
4. 商店后台上传 APK + 填更新日志 → 提交审核（一般 1–3 个工作日，以平台为准）。
5. 保留 `dist/android/*.sha256` 作为发版记录。

---

## F. 待补材料勾选

- [ ] 小米开发者企业认证
- [ ] APP 备案号（工信部）
- [ ] 软件著作权登记证书
- [ ] 在线隐私政策 HTML（可托管 `docs/privacy-policy.md`）
- [ ] 在线用户协议 HTML
- [ ] 3–5 张应用截图
- [ ] 首次提审是否隐藏 AI 入口（决策）
- [ ] 反馈邮箱 / 举报渠道（`-SupportEmail` 注入）
- [ ] 商店内同名应用查重
