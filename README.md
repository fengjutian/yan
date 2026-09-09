# AI Image Studio

Flutter 客户端与 Go AI 图片服务单仓库。后端既可使用 Docker Compose 启动，也可直接在本机运行，Docker 不是必需的运行方式。

## 目录

- `apps/mobile`：Flutter 客户端。
- `backend`：Go API、Worker 和迁移程序。
- `deploy`：Docker Compose 与环境变量示例。
- `docs`：技术设计和接口文档。

## 方式一：使用 Docker 启动全部服务

1. 将 `deploy/env.example` 复制为仓库根目录的 `.env`。
2. 修改其中的密码和密钥。API 可以在未配置 `MINIMAX_API_KEY` 时运行；启动 Worker 前必须填写该变量。
3. 启动服务：

```powershell
docker compose -f deploy/compose.yaml up --build
```

API 启动后可访问 `http://localhost:8080/health/live`。

## 方式二：不使用 Docker 运行后端

本机需要 Go 1.24，以及可访问的 MySQL 8、Redis 7 和兼容 S3 的对象存储（如 MinIO）。数据库需先执行 `backend/migrations` 中按编号排列的 `*.up.sql`。

1. 参考 `deploy/env.local.example` 设置环境变量。该文件使用 `localhost`；如果依赖部署在其他机器，请改成对应地址。
2. 在两个终端中分别启动 API 和 Worker：

```powershell
Set-Location backend
go run ./cmd/api
```

```powershell
Set-Location backend
go run ./cmd/worker
```

也可以先编译，再直接运行二进制：

```powershell
Set-Location backend
go build -o api.exe ./cmd/api
go build -o worker.exe ./cmd/worker
```

## 方式三：仅用 Docker 启动依赖

如果本机不想安装 MySQL、Redis 和 MinIO，可以只用 Compose 启动依赖，再按“方式二”在宿主机运行 Go 服务。此时应使用 `deploy/env.local.example` 中的 `localhost` 地址。

```powershell
docker compose -f deploy/compose.yaml up -d mysql redis minio minio-init
```

## 文档

- [技术设计与开发计划](docs/technical-design-and-development-plan.md)
- [OpenAPI 接口定义](docs/api.openapi.yaml)
