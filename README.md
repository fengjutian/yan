# AI Image Studio

Flutter 客户端与 Go AI 图片服务单仓库。当前处于 MVP 工程基线阶段。

## 目录

- `apps/mobile`：Flutter 客户端。
- `backend`：Go API、Worker 和迁移程序。
- `deploy`：Docker Compose 与 Nginx 配置。
- `docs`：技术设计和接口文档。

## 本地启动

1. 复制 `deploy/env.example` 为仓库根目录 `.env`。
2. 填写安全的本地密码；MiniMax Key 在接入真实 Provider 前可以留空。
3. 执行 `docker compose -f deploy/compose.yaml up --build`。
4. 访问 `http://localhost:8080/health/live`。

本机直接运行 API：

```powershell
Set-Location backend
go run ./cmd/api
```

本机直接运行 Worker：

```powershell
Set-Location backend
go run ./cmd/worker
```

详细方案见 [技术设计与开发计划](docs/technical-design-and-development-plan.md)。

