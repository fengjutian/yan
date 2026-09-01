# AI Image Studio 技术设计与开发计划

> 文档状态：Draft  
> 编写日期：2026-09-01  
> 目标版本：MVP  
> 技术架构：Flutter + Go + MySQL + Redis + MinIO + MiniMax

## 1. 文档目标

本文档定义 AI Image Studio MVP 的产品边界、系统架构、模块职责、数据模型、API 契约、任务可靠性、安全合规、测试策略、部署方案和分阶段开发计划。

MVP 覆盖：

- 文生图
- 人物参考图生图
- 风格预设
- 异步生成任务
- 作品历史
- 用户登录与基础额度
- MinIO 图片持久化
- Flutter 多端基础适配
- Docker Compose 本地部署

MVP 暂不覆盖：

- 支付、订阅及复杂套餐
- 多模型自动路由
- 局部重绘、扩图和蒙版编辑
- 作品社区、评论和关注
- 企业多租户
- Kubernetes 部署

## 2. 产品与技术原则

核心职责划分：

```text
Flutter 负责交互
Go 负责业务与安全
MiniMax 负责 AI 推理
MySQL 负责业务事实
Redis 负责任务调度
MinIO/OSS 负责永久图片存储
```

必须遵守以下原则：

1. MiniMax API Key 只存在于后端运行环境。
2. Flutter 不直接调用 MiniMax。
3. MiniMax 临时图片地址不作为永久业务地址。
4. 图片生成对客户端始终表现为异步任务。
5. Provider 请求结构不向业务层泄漏。
6. 任务创建、扣费、退款和重试必须幂等。
7. 所有用户资源操作必须校验归属权。
8. AI 生成内容必须保留必要标识和审计信息。

## 3. MiniMax 能力边界

当前官方图片生成入口：

```http
POST https://api.minimaxi.com/v1/image_generation
```

主要模型：

- `image-01`：文生图、人物主体参考。
- `image-01-live`：在图片生成基础上额外支持官方画风参数。

主要参数：

- `prompt`：最长 1500 字符。
- `subject_reference`：人物主体参考图。
- `aspect_ratio`。
- `width`、`height`。
- `response_format`。
- `seed`。
- `n`：1～9。
- `prompt_optimizer`。
- `aigc_watermark`。

MiniMax 返回的 URL 有时效性，Worker 必须在任务执行期间下载图片并转存到自有对象存储。

当前公开的图生图能力主要是人物主体参考。MVP 产品文案采用“人物参考创作”，不承诺任意图片的精确风格迁移，也不向 MiniMax 发送未明确支持的 `strength` 参数。首版风格强度只通过 Prompt 模板表达。

Prompt AI 优化放在第二阶段。文本模型入口必须封装在 `PromptOptimizer` 后面，避免业务层依赖可能调整或废弃的具体接口。

## 4. 总体架构

```text
Flutter App
    │ HTTPS / JSON
    ▼
Go API
    ├── 身份认证与用户
    ├── 图片资源管理
    ├── 风格预设
    ├── 生成任务
    └── 历史记录
          │
          ├── MySQL：业务状态与元数据
          ├── Redis：队列、缓存、限流
          └── MinIO：原图、生成图、缩略图
                      ▲
                      │
                  Go Worker
                      │
                      ▼
               ImageProvider
                      │
                      ▼
                   MiniMax
```

Go API 只负责请求校验、额度预占、创建数据库任务和投递队列，然后立即返回 `task_id`。Worker 消费任务、调用 MiniMax、转存生成结果并更新任务状态。

MiniMax 图片调用即使在 Provider 内同步完成，对 Flutter 仍呈现为本地异步任务。

## 5. 技术选型

### 5.1 Flutter

```text
Flutter stable
Dart
flutter_riverpod
go_router
dio
freezed
json_serializable
image_picker
cached_network_image
flutter_secure_storage
photo_view
```

约束：

- Widget 只负责展示和分发用户动作。
- Controller 管理页面状态和业务流程。
- Repository 负责调用 API。
- Dio 只允许出现在网络层和 Repository。
- Token 使用系统安全存储。
- API Model 与页面 State 分离。

### 5.2 Go

```text
Go stable
Gin
GORM
MySQL 8
Redis 7
Asynq
Zap
Viper
JWT
MinIO Go SDK
OpenTelemetry（预留）
```

MVP 使用 Asynq 提供重试、延迟任务、任务唯一性、超时、优先级和监控能力，避免自行实现完整可靠队列。

### 5.3 基础设施

```text
Docker Compose
MySQL 8
Redis 7
MinIO
Nginx
Go API
Go Worker
```

生产环境可将 MinIO 替换成 OSS、COS、S3 或 R2，业务层只依赖 `ObjectStorage` 接口。

## 6. 仓库结构

```text
yan/
├── apps/
│   └── mobile/
│       ├── lib/
│       ├── test/
│       ├── android/
│       ├── ios/
│       ├── macos/
│       ├── windows/
│       └── web/
├── backend/
│   ├── cmd/
│   │   ├── api/main.go
│   │   ├── worker/main.go
│   │   └── migrate/main.go
│   ├── internal/
│   │   ├── app/
│   │   ├── config/
│   │   ├── transport/http/
│   │   ├── middleware/
│   │   ├── service/
│   │   ├── repository/
│   │   ├── model/
│   │   ├── provider/image/
│   │   ├── queue/
│   │   ├── storage/
│   │   └── observability/
│   ├── migrations/
│   ├── tests/
│   ├── go.mod
│   └── Dockerfile
├── deploy/
│   ├── compose.yaml
│   ├── nginx/
│   └── env.example
├── docs/
│   ├── architecture.md
│   ├── api.openapi.yaml
│   ├── database.md
│   └── development.md
├── Makefile
└── README.md
```

## 7. 后端分层与职责

依赖方向：

```text
HTTP Handler
    → Application Service
        → Repository Interface
        → Queue Interface
        → Storage Interface
        → ImageProvider Interface
```

### 7.1 Handler

负责解析请求、参数校验、提取身份、调用 Service 和映射统一响应。不得直接访问数据库、拼接 Prompt、调用 MiniMax 或执行额度计算。

### 7.2 Service

负责完整业务事务：

- 校验用户额度。
- 检查资源归属。
- 拼装风格 Prompt。
- 创建任务和预占额度。
- 投递任务及执行失败补偿。
- 驱动合法的任务状态变更。

### 7.3 Repository

只负责数据库持久化和查询，不包含业务决策。

### 7.4 Worker

负责：

- 抢占并推进任务状态。
- 加载源图片和风格配置。
- 调用 Provider。
- 下载或解码生成结果。
- 转存图片并生成缩略图。
- 更新任务与资产。
- 确认扣费或执行退款。
- 分类处理可重试和不可重试错误。

## 8. Provider 抽象

```go
type ImageProvider interface {
	Generate(ctx context.Context, req GenerateRequest) (*GenerateResult, error)
	Capabilities() ProviderCapabilities
}
```

统一请求：

```go
type GenerateRequest struct {
	Prompt         string
	NegativePrompt string
	References     []ImageReference
	AspectRatio    string
	Width          int
	Height         int
	Count          int
	Seed           *int64
	OptimizePrompt bool
	Watermark      bool
}
```

统一响应：

```go
type GenerateResult struct {
	ProviderRequestID string
	Images            []GeneratedImage
	Usage             ProviderUsage
}

type GeneratedImage struct {
	URL      string
	Base64   string
	MIMEType string
}
```

能力描述：

```go
type ProviderCapabilities struct {
	TextToImage        bool
	CharacterReference bool
	StyleReference     bool
	NegativePrompt     bool
	Seed               bool
	CustomSize         bool
	MaxImageCount      int
}
```

未来接入 OpenAI、Flux、Gemini 或 ComfyUI 时，Service 根据能力描述校验请求，不使用散落的 Provider 名称判断。

## 9. 数据模型

主键建议使用 UUIDv7 或 ULID，对外 ID 不可枚举。

### 9.1 users

```text
id
email
password_hash
nickname
avatar_asset_id
status
credits_balance
created_at
updated_at
deleted_at
```

### 9.2 refresh_tokens

```text
id
user_id
token_hash
expires_at
revoked_at
device_name
created_at
```

数据库只保存 Refresh Token 哈希。

### 9.3 image_tasks

```text
id
user_id
parent_task_id
type
status
progress
prompt
effective_prompt
negative_prompt
style_id
source_asset_id
provider
provider_model
provider_request_id
aspect_ratio
width
height
image_count
seed
credits_reserved
attempt_count
error_code
error_message
created_at
started_at
completed_at
updated_at
```

`prompt` 保存用户原始输入，`effective_prompt` 保存模板和优化器处理后的最终输入。

### 9.4 image_assets

```text
id
user_id
task_id
kind
storage_provider
bucket
storage_key
thumbnail_key
mime_type
width
height
byte_size
sha256
ai_generated
created_at
deleted_at
```

数据库保存 `bucket + storage_key`，访问时生成 CDN URL 或签名 URL，不把临时 URL 当成业务事实。

### 9.5 styles

```text
id
slug
name
description
cover_asset_id
prompt_template
negative_prompt
provider_options_json
sort_order
enabled
created_at
updated_at
```

### 9.6 task_assets

```text
task_id
asset_id
role
position
created_at
```

`role` 取值：`SOURCE`、`RESULT`、`THUMBNAIL`。

### 9.7 credit_ledger

```text
id
user_id
task_id
type
amount
balance_after
idempotency_key
description
created_at
```

类型：`GRANT`、`RESERVE`、`CAPTURE`、`REFUND`、`ADJUSTMENT`。

额度流水不可变。不能只修改 `users.credits_balance` 而不记录流水。

## 10. 任务状态机

```text
PENDING
   │ Worker 领取
   ▼
PROCESSING
   ├── 成功 ──→ SUCCEEDED
   ├── 可重试错误 ──→ RETRYING ──→ PROCESSING
   └── 不可恢复/耗尽重试 ──→ FAILED

PENDING ──用户取消──→ CANCELED
```

规则：

- 状态只能通过 Service 或 Worker 的状态机方法更新。
- 使用条件更新或乐观锁，防止多个 Worker 重复完成。
- 终态不可被旧执行覆盖。
- `FAILED` 和 `CANCELED` 触发额度释放。
- `progress` 是本地流程估算，不冒充 Provider 的真实推理进度。

建议进度：

```text
PENDING            0
PROCESSING        10
Provider 调用      30
结果下载           70
转存与缩略图        85
SUCCEEDED         100
```

## 11. 队列可靠性

队列消息只保存任务 ID：

```json
{
  "task_id": "01J..."
}
```

Worker 始终从 MySQL 加载任务当前状态，不在 Redis 中复制完整业务数据。

可靠性策略：

- 数据库事务创建任务并预占额度。
- 事务提交后投递队列。
- 定时补偿器扫描已创建但未投递的任务。
- 队列以 `task_id` 作为唯一键。
- Provider 超时建议为 120～180 秒。
- 指数退避，最多重试 3 次。
- 认证、内容审核和参数错误不重试。
- 网络超时、429 和部分 5xx 可以重试。

正式版本可以引入 Outbox 表，消除数据库成功但 Redis 投递失败的窗口。

## 12. 图片存储

### 12.1 源图片上传

MVP 先通过 Go API 上传：

```text
Flutter
  → multipart 上传到 Go
  → 校验 MIME、尺寸和大小
  → 计算 SHA-256
  → 上传 MinIO
  → 创建 image_assets
```

稳定后升级为预签名直传。

上传限制建议：

- JPEG、PNG、WebP。
- 最大 10 MB。
- 长宽 512～4096。
- 限制解码后像素总数，防止图片解压炸弹。

### 12.2 生成结果

```text
MiniMax 临时 URL/Base64
  → Worker 下载或解码
  → 验证 MIME 和大小
  → 写入 MinIO generated/
  → 生成 preview/thumbnail
  → 创建 image_assets
  → 完成任务
```

对象键建议：

```text
original/{user_id}/{yyyy}/{mm}/{asset_id}.jpg
generated/{user_id}/{yyyy}/{mm}/{asset_id}.jpg
thumbnail/{user_id}/{yyyy}/{mm}/{asset_id}.webp
avatar/{user_id}/{asset_id}.webp
```

不得信任客户端或第三方提供的 MIME 和文件扩展名，应根据文件头重新检测。

## 13. API 设计

统一前缀：

```text
/api/v1
```

错误响应：

```json
{
  "error": {
    "code": "INSUFFICIENT_CREDITS",
    "message": "可用额度不足",
    "request_id": "req_..."
  }
}
```

### 13.1 认证

```http
POST /api/v1/auth/register
POST /api/v1/auth/login
POST /api/v1/auth/refresh
POST /api/v1/auth/logout
GET  /api/v1/me
```

建议 Access Token 有效期 15 分钟，Refresh Token 有效期 30 天并实施轮换。

### 13.2 图片资源

```http
POST   /api/v1/assets
GET    /api/v1/assets/{id}
DELETE /api/v1/assets/{id}
```

MVP 的上传接口使用 multipart。

### 13.3 风格

```http
GET /api/v1/styles
GET /api/v1/styles/{slug}
```

### 13.4 创建文生图任务

```http
POST /api/v1/image-tasks
Idempotency-Key: <uuid>
```

```json
{
  "type": "TEXT_TO_IMAGE",
  "prompt": "一只坐在月球上的橘猫",
  "style_id": "cinematic",
  "aspect_ratio": "1:1",
  "count": 2,
  "prompt_optimizer": true,
  "seed": null
}
```

返回：

```json
{
  "id": "01J...",
  "status": "PENDING",
  "progress": 0,
  "credits_reserved": 20,
  "created_at": "2026-09-01T10:00:00Z"
}
```

### 13.5 创建人物参考任务

```json
{
  "type": "CHARACTER_REFERENCE",
  "prompt": "保持人物主体，在雨夜霓虹街道中行走",
  "source_asset_ids": ["01J..."],
  "style_id": "cinematic",
  "aspect_ratio": "9:16",
  "count": 1
}
```

### 13.6 查询任务

```http
GET /api/v1/image-tasks/{id}
```

```json
{
  "id": "01J...",
  "type": "TEXT_TO_IMAGE",
  "status": "SUCCEEDED",
  "progress": 100,
  "prompt": "一只坐在月球上的橘猫",
  "results": [
    {
      "id": "01J...",
      "url": "https://cdn.example.com/...",
      "thumbnail_url": "https://cdn.example.com/...",
      "width": 1024,
      "height": 1024,
      "ai_generated": true
    }
  ]
}
```

### 13.7 历史记录

```http
GET /api/v1/image-tasks?status=SUCCEEDED&cursor=...&limit=20
```

使用基于 `created_at + id` 的游标分页，避免新增作品导致页码列表跳动。

### 13.8 取消和重试

```http
POST /api/v1/image-tasks/{id}/cancel
POST /api/v1/image-tasks/{id}/retry
```

重试创建新任务并设置 `parent_task_id`，不覆盖失败任务历史。

## 14. 幂等性与额度事务

创建任务要求 `Idempotency-Key`。Flutter 在网络超时后重试相同请求时，后端返回原任务，避免重复扣费和生成。

创建事务：

```text
锁定用户额度行
→ 检查余额
→ 写入 RESERVE 流水
→ 更新余额
→ 创建 image_task
→ 写入 idempotency_record
→ 提交
```

任务成功执行 `RESERVE → CAPTURE`，最终失败执行 `RESERVE → REFUND`。退款使用唯一键，防止 Worker 重复执行导致重复退款。

## 15. Flutter 架构

```text
lib/
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
├── core/
│   ├── config/
│   ├── network/
│   ├── auth/
│   ├── storage/
│   ├── errors/
│   └── widgets/
├── features/
│   ├── auth/
│   ├── home/
│   ├── generate/
│   ├── reference/
│   ├── task/
│   ├── history/
│   └── profile/
└── main.dart
```

Feature 内部建议：

```text
data/
  api/
  models/
  repositories/
domain/
  entities/
  repositories/
presentation/
  controllers/
  pages/
  widgets/
```

### 15.1 路由

```text
/splash
/login
/register

/
├── /home
├── /create
│   ├── /text-to-image
│   └── /character-reference
├── /history
└── /profile

/task/:taskId
/asset/:assetId
```

底部导航：`首页 | 创作 | 作品 | 我的`。

### 15.2 状态管理

表单状态与任务执行状态分离：

```dart
@freezed
class GenerateState with _$GenerateState {
  const factory GenerateState({
    @Default('') String prompt,
    String? styleId,
    String? sourceAssetId,
    @Default('1:1') String aspectRatio,
    @Default(1) int count,
    int? seed,
    @Default(false) bool optimizePrompt,
    @Default(false) bool submitting,
    String? validationMessage,
  }) = _GenerateState;
}
```

```text
TaskController(taskId)
  ├── load()
  ├── poll()
  ├── cancel()
  └── retry()
```

轮询间隔从 2 秒逐渐增加到 10 秒。页面离开后停止高频轮询，后续可升级 SSE，并保留轮询降级。

## 16. Prompt Engine

MVP 使用确定性模板：

```text
用户 Prompt
+ 风格模板
+ 主体保持说明
+ 构图/质量补充
= effective_prompt
```

要求：

- 用户输入放入模板明确区域。
- 最终 Prompt 不超过 Provider 限制。
- 保存模板版本，保证历史可追踪。
- 不静默改变用户明确要求。
- Prompt 优化失败时回退原 Prompt。

第二阶段定义：

```go
type PromptOptimizer interface {
	Optimize(ctx context.Context, req OptimizeRequest) (*OptimizeResult, error)
}
```

## 17. 安全设计

### 17.1 密钥管理

后端环境变量：

```text
MINIMAX_API_KEY
JWT_SIGNING_KEY
MYSQL_PASSWORD
MINIO_SECRET_KEY
```

密钥不得进入 Flutter、Git、Docker 镜像层、日志或错误响应。

### 17.2 接口与文件安全

- JWT 鉴权和 Refresh Token 轮换。
- CORS 白名单。
- 登录、上传和生成接口限流。
- 请求体大小限制。
- 上传 MIME 和文件头二次检测。
- 图片解码像素数限制。
- SQL 参数化。
- 日志脱敏。
- 每次资源访问校验 `user_id`。
- 下载 Provider 结果时执行 SSRF 防护、域名/协议限制、重定向限制和大小限制。

### 17.3 内容安全

错误码至少区分：

```text
CONTENT_POLICY_REJECTED
REFERENCE_IMAGE_REJECTED
PROVIDER_RATE_LIMITED
PROVIDER_UNAVAILABLE
PROVIDER_PARTIAL_SUCCESS
```

## 18. AI 内容标识与合规

产品要求：

- 生成结果页显示“AI 生成”。
- 数据库记录 `ai_generated=true`。
- 下载和分享页保留标识说明。
- 不提供移除 AI 标识的能力。
- 图片转码时检查必要元数据是否保留。
- 用户协议禁止伪造、删除或规避必要标识。
- 保存 Provider、模型、任务 ID 和生成时间等审计数据。
- `aigc_watermark` 的生产默认值在真实接入测试时依据官方要求确认。

## 19. 可观测性

JSON 日志字段：

```text
timestamp
level
service
request_id
user_id
task_id
provider
provider_request_id
duration_ms
error_code
```

禁止记录 API Key、JWT、密码、Refresh Token、用户原图内容以及不必要的完整 Prompt。

首版指标：

- HTTP 请求量、延迟和错误率。
- 队列长度和等待时长。
- 生成成功率。
- Provider 延迟、限流和错误率。
- Worker 重试次数。
- 图片转存失败率。
- 额度预占、确认和退款数量。

健康检查：

```http
GET /health/live
GET /health/ready
```

`ready` 检查 MySQL、Redis 和 MinIO，不在每次检查中探测 MiniMax。

## 20. 测试策略

### 20.1 Go 单元测试

- Prompt 模板拼装。
- 参数校验。
- 任务状态机。
- 额度预占和退款。
- Provider 响应映射。
- 幂等键处理。
- 错误重试分类。

MiniMax Provider 使用 `httptest.Server` 覆盖成功、部分成功、业务错误、429、5xx、超时、非法 JSON 和结果下载失败。

### 20.2 Go 集成测试

使用容器启动 MySQL、Redis 和 MinIO，覆盖：

```text
注册 → 登录
上传图片
创建任务
Worker 消费
生成资产
查询历史
失败退款
重复请求幂等
```

CI 使用 Fake Provider，不调用真实付费 API。

### 20.3 Flutter 测试

- Controller 单元测试。
- Repository Mock 测试。
- 生成表单 Widget 测试。
- 鉴权与路由测试。
- 关键页面 Golden Test。
- 登录到任务成功的集成测试。

## 21. 配置管理

可提交默认配置：

```yaml
server:
  port: 8080
queue:
  concurrency: 4
image:
  max_upload_mb: 10
  allowed_types:
    - image/jpeg
    - image/png
    - image/webp
```

环境变量：

```text
APP_ENV
DATABASE_DSN
REDIS_ADDR
MINIO_ENDPOINT
MINIO_ACCESS_KEY
MINIO_SECRET_KEY
MINIMAX_API_KEY
JWT_SIGNING_KEY
PUBLIC_ASSET_BASE_URL
```

Flutter 只接受公开编译配置：

```text
--dart-define=API_BASE_URL=...
--dart-define=APP_ENV=development
```

## 22. 部署设计

本地 Docker Compose 服务：

- `api`
- `worker`
- `mysql`
- `redis`
- `minio`
- `minio-init`
- `nginx`

数据库迁移由独立一次性任务执行，避免多个 API 实例启动时竞争迁移。

开发地址建议：

```text
API:           http://localhost:8080
MinIO Console: http://localhost:9001
Assets:        http://localhost:8081
```

## 23. MVP 开发计划

按一名熟悉 Go 和 Flutter 的全栈开发者估算，共约 25～35 个工作日。

### 阶段 0：工程基线（2～3 天）

交付：

- 单仓库目录。
- Go API/Worker 启动骨架。
- Flutter 项目。
- Docker Compose。
- 环境变量模板。
- 开发命令和基础 CI。
- 架构决策记录。

验收：新环境能按 README 启动所有依赖，API 健康检查成功，Flutter 能访问本地 API。

### 阶段 1：认证与用户（3～4 天）

交付：注册、登录、刷新、退出、JWT 中间件、Refresh Token 轮换、用户资料、Flutter 登录注册和安全存储。

验收：Access Token 可无感刷新，被撤销的 Refresh Token 不能重用，受保护资源拒绝未认证访问。

### 阶段 2：图片上传与存储（3～4 天）

交付：Storage 抽象、MinIO、上传校验、图片资产、缩略图、Flutter 图片选择与上传。

验收：合法图片可上传，超限或非法文件被拒绝，用户不能访问他人资源，列表只加载缩略图。

### 阶段 3：文生图链路（5～6 天）

交付：ImageProvider、MiniMax Adapter、任务 API、Redis 队列、Worker、结果转存、任务查询、Flutter 文生图和结果页。

验收：API 快速返回 `PENDING`；Worker 能生成并持久化；临时 URL 失效后作品仍可访问；同一幂等键不重复生成。

### 阶段 4：人物参考与风格（4～5 天）

交付：`subject_reference` 映射、风格预设、Prompt 模板、Flutter 人物参考页和能力校验。

验收：验证源图片归属；风格模板可追踪；不发送未支持参数；UI 准确描述能力边界。

### 阶段 5：历史、额度与补偿（4～5 天）

交付：历史游标分页、额度流水、预占/确认/退款、取消、重试、补偿扫描器和 Flutter 作品页。

验收：失败自动退款；重复执行不重复扣款或退款；服务重启不丢任务；历史分页稳定。

### 阶段 6：质量与发布准备（4～6 天）

交付：限流、CORS、结构化日志、指标、错误码、测试、AI 标识、协议入口、多端构建验证和部署文档。

验收：核心测试通过；日志无敏感信息；Provider 故障可正确失败并退款；生成内容带清晰 AI 标识。

## 24. 第二阶段路线

1. Prompt AI 优化：引入 `PromptOptimizer`，支持结构化 Prompt、失败降级和模板版本。
2. 预签名直传：Flutter 直接上传对象存储，减少 API 带宽。
3. SSE 通知：替代高频轮询，同时保留轮询降级。
4. 多 Provider：加入能力路由、成本配置、熔断和回退。
5. 商业化：支付订单、订阅、套餐、额度有效期和退款。
6. 高级编辑：在 Provider 能力明确后加入局部重绘、扩图、背景替换和强度控制。

## 25. MVP 完成定义

必须打通以下闭环：

```text
用户注册登录
→ 上传参考图或填写 Prompt
→ 选择风格和比例
→ 创建异步任务
→ Worker 调用 MiniMax
→ 结果转存 MinIO
→ 任务成功
→ Flutter 展示结果
→ 历史记录长期可访问
→ 失败时正确退款
```

同时满足：

- Flutter 中不存在 MiniMax API Key。
- 第三方临时 URL 不进入永久业务依赖。
- 任务处理具备幂等性和故障恢复能力。
- 用户无法访问其他用户资产。
- 额度变更具有完整流水。
- AI 内容标识不会被产品主动规避。
- Provider 可以替换，业务层不依赖 MiniMax 请求结构。

## 26. 下一步

下一步按阶段 0 开始，先创建：

1. Flutter 和 Go 工程骨架。
2. Docker Compose 基础设施。
3. 初版数据库迁移。
4. OpenAPI 接口文件。
5. 配置、日志和健康检查。
6. CI 与本地开发文档。

## 27. 官方参考

- [MiniMax 图片生成指南](https://platform.minimaxi.com/docs/guides/image-generation)
- [MiniMax 图生图 API](https://platform.minimaxi.com/docs/api-reference/image-generation-i2i)
- [MiniMax API 能力概览](https://platform.minimaxi.com/docs/api-reference/api-overview)
- [MiniMax API 更新记录](https://platform.minimaxi.com/docs/release-notes/apis)
- [MiniMax AI 生成内容标识公告](https://www.minimaxi.com/news/%E5%85%B3%E4%BA%8E%E6%B7%B1%E5%85%A5%E8%90%BD%E5%AE%9E%E4%BA%BA%E5%B7%A5%E6%99%BA%E8%83%BD%E7%94%9F%E6%88%90%E5%90%88%E6%88%90%E5%86%85%E5%AE%B9%E6%A0%87%E8%AF%86%E5%8A%9E%E6%B3%95%E7%9A%84%E5%85%AC%E5%91%8A)
