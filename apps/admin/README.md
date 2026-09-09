# AI Image Studio 运营管理端

React + TypeScript + Vite。开发环境通过 Vite 将 `/api` 代理到 `http://localhost:8080`。

```powershell
npm install
npm run dev
```

首次使用前执行 `backend/migrations/000004_admin_console.up.sql`，并将一个已注册账号提升为管理员：

```sql
UPDATE users SET role = 'ADMIN' WHERE email = '你的管理员邮箱';
```

生产构建可通过 `VITE_API_BASE_URL` 指定 API 地址。
