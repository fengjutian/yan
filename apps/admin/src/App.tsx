import { FormEvent, useEffect, useState } from "react";
import {
  Navigate,
  NavLink,
  Route,
  Routes,
  useNavigate,
} from "react-router-dom";
import { api, AIModelSettings, Audit, CurrentUser, Overview, Style, Task, User } from "./api";
import "./settings.css";

const nav = [
  ["/", "◈", "工作台"],
  ["/prompts", "✦", "运营提示词"],
  ["/users", "♙", "用户管理"],
  ["/tasks", "▣", "生成任务"],
  ["/audit", "⌁", "操作审计"],
  ["/settings", "⚙", "模型设置"],
];
function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/*" element={<Protected />} />
    </Routes>
  );
}
function Protected() {
  const [user, setUser] = useState<CurrentUser | null>();
  useEffect(() => {
    api
      .me()
      .then((v) => (v.role === "ADMIN" ? setUser(v) : setUser(null)))
      .catch(() => setUser(null));
  }, []);
  if (user === undefined) return <div className="loading">正在加载管理端…</div>;
  if (!user) return <Navigate to="/login" replace />;
  return <Shell user={user} />;
}
function Login() {
  const [email, setEmail] = useState(""),
    [password, setPassword] = useState(""),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    navigate = useNavigate();
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await api.login(email, password);
      navigate("/");
    } catch (e: any) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <main className="login">
      <section className="login-art">
        <div className="brand-mark">AI</div>
        <div>
          <span className="eyebrow">AI IMAGE STUDIO</span>
          <h1>
            让每一次创作
            <br />
            都井然有序。
          </h1>
          <p>统一管理提示词、用户与生成任务。</p>
        </div>
        <div className="orb" />
      </section>
      <section className="login-form">
        <form onSubmit={submit}>
          <h2>欢迎回来</h2>
          <p>登录运营管理后台</p>
          <label>
            管理员邮箱
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@example.com"
              required
            />
          </label>
          <label>
            密码
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="请输入密码"
              required
            />
          </label>
          {error && <div className="error">{error}</div>}
          <button className="primary" disabled={busy}>
            {busy ? "登录中…" : "登录后台"}
          </button>
          <small>仅限已授权管理员访问</small>
        </form>
      </section>
    </main>
  );
}
function Shell({ user }: { user: CurrentUser }) {
  return (
    <div className="shell">
      <aside>
        <div className="logo">
          <b>AI</b>
          <span>
            Image Studio<small>运营管理后台</small>
          </span>
        </div>
        <nav>
          {nav.map(([to, icon, label]) => (
            <NavLink key={to} to={to} end={to === "/"}>
              <i>{icon}</i>
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="aside-bottom">
          <div className="avatar">{user.nickname?.[0] ?? "A"}</div>
          <div>
            <strong>{user.nickname}</strong>
            <small>{user.email}</small>
          </div>
          <button
            title="退出"
            onClick={() => {
              localStorage.clear();
              location.assign("/login");
            }}
          >
            ↗
          </button>
        </div>
      </aside>
      <main className="content">
        <Routes>
          <Route index element={<Dashboard user={user} />} />
          <Route path="prompts" element={<Prompts />} />
          <Route path="users" element={<Users current={user} />} />
          <Route path="tasks" element={<Tasks />} />
          <Route path="audit" element={<AuditLogs />} />
          <Route path="settings" element={<ModelSettings />} />
        </Routes>
      </main>
    </div>
  );
}
function Head({
  title,
  desc,
  action,
}: {
  title: string;
  desc: string;
  action?: any;
}) {
  return (
    <header className="page-head">
      <div>
        <h1>{title}</h1>
        <p>{desc}</p>
      </div>
      {action}
    </header>
  );
}
function Dashboard({ user }: { user: CurrentUser }) {
  const [data, setData] = useState<Overview>();
  useEffect(() => {
    api.overview().then(setData);
  }, []);
  const cards = [
    ["注册用户", data?.Users, "较活跃用户 " + (data?.ActiveUsers ?? "—")],
    ["生成任务", data?.Tasks, "已完成 " + (data?.CompletedTasks ?? "—")],
    ["失败任务", data?.FailedTasks, "持续关注异常率"],
    ["提示词模板", data?.Styles, "当前全部模板"],
  ];
  return (
    <>
      <Head
        title={`下午好，${user.nickname}`}
        desc="这里是当前业务的实时概览。"
      />
      <section className="stats">
        {cards.map((x, i) => (
          <article key={x[0]}>
            <div className={"stat-icon c" + i}>{["♙", "✦", "!", "⌘"][i]}</div>
            <p>{x[0]}</p>
            <strong>{x[1] ?? "—"}</strong>
            <small>{x[2]}</small>
          </article>
        ))}
      </section>
      <section className="panel welcome">
        <div>
          <span className="tag">运营建议</span>
          <h2>从提示词模板开始优化生成体验</h2>
          <p>
            清晰、可复用的风格模板能显著降低用户的描述成本。修改后将立即应用到用户端。
          </p>
          <NavLink className="primary link" to="/prompts">
            管理提示词 →
          </NavLink>
        </div>
        <div className="spark">
          ✦<i>✧</i>
          <b>✦</b>
        </div>
      </section>
    </>
  );
}
function Prompts() {
  const [items, setItems] = useState<Style[]>([]),
    [editing, setEditing] = useState<Partial<Style> | null>(null),
    [error, setError] = useState("");
  const load = () => api.styles().then((v) => setItems(v.items));
  useEffect(() => {
    void load();
  }, []);
  async function save(e: FormEvent) {
    e.preventDefault();
    try {
      await api.saveStyle(editing!, editing?.ID);
      setEditing(null);
      load();
    } catch (e: any) {
      setError(e.message);
    }
  }
  async function remove(item: Style) {
    if (confirm(`确定删除“${item.Name}”吗？`)) {
      await api.deleteStyle(item.ID);
      load();
    }
  }
  return (
    <>
      <Head
        title="运营提示词"
        desc="管理用户可选择的创作风格与模型提示词。"
        action={
          <button
            className="primary"
            onClick={() =>
              setEditing({ Enabled: true, SortOrder: items.length * 10 })
            }
          >
            ＋ 新建模板
          </button>
        }
      />
      <section className="panel table-panel">
        <table>
          <thead>
            <tr>
              <th>模板</th>
              <th>Prompt 摘要</th>
              <th>排序</th>
              <th>状态</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((x) => (
              <tr key={x.ID}>
                <td>
                  <strong>{x.Name}</strong>
                  <small>{x.Slug}</small>
                </td>
                <td className="truncate">{x.PromptTemplate}</td>
                <td>{x.SortOrder}</td>
                <td>
                  <span className={x.Enabled ? "status on" : "status"}>
                    {x.Enabled ? "已启用" : "已停用"}
                  </span>
                </td>
                <td className="actions">
                  <button onClick={() => setEditing(x)}>编辑</button>
                  <button className="danger" onClick={() => remove(x)}>
                    删除
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!items.length && <Empty text="还没有提示词模板" />}
      </section>
      {editing && (
        <div className="modal-bg" onMouseDown={() => setEditing(null)}>
          <form
            className="modal"
            onSubmit={save}
            onMouseDown={(e) => e.stopPropagation()}
          >
            <div className="modal-head">
              <div>
                <h2>{editing.ID ? "编辑模板" : "新建模板"}</h2>
                <p>模板将与用户输入共同发送给图片模型</p>
              </div>
              <button type="button" onClick={() => setEditing(null)}>
                ×
              </button>
            </div>
            <div className="form-grid">
              <label>
                模板名称
                <input
                  value={editing.Name ?? ""}
                  onChange={(e) =>
                    setEditing({ ...editing, Name: e.target.value })
                  }
                  required
                />
              </label>
              <label>
                英文标识
                <input
                  value={editing.Slug ?? ""}
                  onChange={(e) =>
                    setEditing({ ...editing, Slug: e.target.value })
                  }
                  placeholder="cinematic"
                  required
                />
              </label>
              <label className="full">
                说明
                <input
                  value={editing.Description ?? ""}
                  onChange={(e) =>
                    setEditing({ ...editing, Description: e.target.value })
                  }
                />
              </label>
              <label className="full">
                正向提示词
                <textarea
                  rows={6}
                  value={editing.PromptTemplate ?? ""}
                  onChange={(e) =>
                    setEditing({ ...editing, PromptTemplate: e.target.value })
                  }
                  required
                />
              </label>
              <label className="full">
                负向提示词
                <textarea
                  rows={3}
                  value={editing.NegativePrompt ?? ""}
                  onChange={(e) =>
                    setEditing({ ...editing, NegativePrompt: e.target.value })
                  }
                />
              </label>
              <label>
                排序
                <input
                  type="number"
                  value={editing.SortOrder ?? 0}
                  onChange={(e) =>
                    setEditing({ ...editing, SortOrder: +e.target.value })
                  }
                />
              </label>
              <label className="check">
                <input
                  type="checkbox"
                  checked={editing.Enabled ?? true}
                  onChange={(e) =>
                    setEditing({ ...editing, Enabled: e.target.checked })
                  }
                />{" "}
                在用户端启用
              </label>
            </div>
            {error && <div className="error">{error}</div>}
            <footer>
              <button type="button" onClick={() => setEditing(null)}>
                取消
              </button>
              <button className="primary">保存模板</button>
            </footer>
          </form>
        </div>
      )}
    </>
  );
}
function Users({ current }: { current: CurrentUser }) {
  const [items, setItems] = useState<User[]>([]),
    [query, setQuery] = useState(""),
    [total, setTotal] = useState(0);
  const load = () =>
    api.users(query).then((v) => {
      setItems(v.items);
      setTotal(v.total);
    });
  useEffect(() => {
    void load();
  }, []);
  async function toggle(u: User) {
    await api.updateUser(u.ID, {
      status: u.Status === "ACTIVE" ? "DISABLED" : "ACTIVE",
    });
    load();
  }
  async function credits(u: User) {
    const raw = prompt(
      `调整 ${u.Nickname} 的积分（输入正数增加、负数扣除）`,
      "10",
    );
    if (raw && Number.isFinite(+raw)) {
      await api.updateUser(u.ID, { credits_delta: +raw });
      load();
    }
  }
  return (
    <>
      <Head
        title="用户管理"
        desc={`共 ${total} 位用户，支持状态和积分管理。`}
      />
      <section className="toolbar">
        <div className="search">
          ⌕
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && load()}
            placeholder="搜索邮箱或昵称"
          />
        </div>
        <button onClick={load}>查询</button>
      </section>
      <section className="panel table-panel">
        <table>
          <thead>
            <tr>
              <th>用户</th>
              <th>角色</th>
              <th>积分</th>
              <th>注册时间</th>
              <th>状态</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((u) => (
              <tr key={u.ID}>
                <td>
                  <strong>{u.Nickname}</strong>
                  <small>{u.Email}</small>
                </td>
                <td>{u.Role === "ADMIN" ? "管理员" : "普通用户"}</td>
                <td>
                  <b>{u.CreditsBalance}</b>
                </td>
                <td>{date(u.CreatedAt)}</td>
                <td>
                  <span
                    className={u.Status === "ACTIVE" ? "status on" : "status"}
                  >
                    {u.Status === "ACTIVE" ? "正常" : "已禁用"}
                  </span>
                </td>
                <td className="actions">
                  <button onClick={() => credits(u)}>调积分</button>
                  <button
                    disabled={u.ID === current.id}
                    onClick={() => toggle(u)}
                  >
                    {u.Status === "ACTIVE" ? "禁用" : "启用"}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </>
  );
}
function Tasks() {
  const [items, setItems] = useState<Task[]>([]);
  useEffect(() => {
    api.tasks().then((v) => setItems(v.items));
  }, []);
  return (
    <>
      <Head title="生成任务" desc="查看近期图片生成任务及执行状态。" />
      <section className="panel table-panel">
        <table>
          <thead>
            <tr>
              <th>任务</th>
              <th>用户 ID</th>
              <th>提示词</th>
              <th>数量</th>
              <th>状态</th>
              <th>创建时间</th>
            </tr>
          </thead>
          <tbody>
            {items.map((t) => (
              <tr key={t.ID}>
                <td>
                  <strong>
                    {t.Type === "CHARACTER_REFERENCE" ? "人物参考" : "文生图"}
                  </strong>
                  <small>{t.ID}</small>
                </td>
                <td className="mono">{t.UserID}</td>
                <td className="truncate">{t.Prompt}</td>
                <td>{t.ImageCount}</td>
                <td>
                  <span
                    className={
                      "status " + (t.Status === "SUCCEEDED" ? "on" : "")
                    }
                  >
                    {t.Status}
                  </span>
                </td>
                <td>{date(t.CreatedAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {!items.length && <Empty text="暂无任务" />}
      </section>
    </>
  );
}
function AuditLogs() {
  const [items, setItems] = useState<Audit[]>([]);
  useEffect(() => {
    api.audit().then((v) => setItems(v.items));
  }, []);
  return (
    <>
      <Head title="操作审计" desc="追踪后台关键变更，便于安全复核。" />
      <section className="panel table-panel">
        <table>
          <thead>
            <tr>
              <th>操作</th>
              <th>资源</th>
              <th>管理员</th>
              <th>详情</th>
              <th>时间</th>
            </tr>
          </thead>
          <tbody>
            {items.map((x) => (
              <tr key={x.ID}>
                <td>
                  <strong>{x.Action}</strong>
                </td>
                <td>
                  {x.ResourceType} · {x.ResourceID}
                </td>
                <td className="mono">{x.AdminUserID}</td>
                <td className="truncate">{x.DetailsJSON}</td>
                <td>{date(x.CreatedAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {!items.length && <Empty text="暂无操作记录" />}
      </section>
    </>
  );
}
function ModelSettings() {
  const [value, setValue] = useState<AIModelSettings>();
  const [apiKey, setApiKey] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  useEffect(() => {
    api.aiModel().then(setValue).catch((e) => setError(e.message));
  }, []);
  async function save(e: FormEvent) {
    e.preventDefault();
    if (!value) return;
    setBusy(true);
    setMessage("");
    setError("");
    try {
      const saved = await api.saveAIModel({ ...value, api_key: apiKey });
      setValue(saved);
      setApiKey("");
      setMessage("模型配置已保存并立即生效");
    } catch (e: any) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  async function testConnection() {
    setBusy(true);
    setMessage("");
    setError("");
    try {
      await api.testAIModel();
      setMessage("连接成功，模型已正常返回内容");
    } catch (e: any) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Head title="大模型设置" desc="配置移动端 AI 帮写所使用的文本大模型。" />
      <section className="panel settings-panel">
        {!value ? (
          <div className="loading-inline">正在读取配置…</div>
        ) : (
          <form className="model-form" onSubmit={save}>
            <div className="setting-intro">
              <span className="stat-icon">✦</span>
              <div>
                <h2>提示词辅助模型</h2>
                <p>支持 OpenAI Chat Completions 兼容接口，保存后无需重启服务。</p>
              </div>
            </div>
            <div className="form-grid">
              <label>服务商<input value={value.provider} onChange={(e) => setValue({ ...value, provider: e.target.value })} placeholder="minimax" required /></label>
              <label>模型名称<input value={value.model} onChange={(e) => setValue({ ...value, model: e.target.value })} placeholder="MiniMax-M2.7" required /></label>
              <label className="full">API Base URL<input type="url" value={value.base_url} onChange={(e) => setValue({ ...value, base_url: e.target.value })} placeholder="https://api.minimaxi.com" required /></label>
              <label className="full">API Key<input type="password" value={apiKey} onChange={(e) => setApiKey(e.target.value)} placeholder={value.api_key_configured ? "已配置，留空则保持不变" : "请输入 API Key"} required={!value.api_key_configured} /><small>{value.api_key_configured ? "密钥已隐藏，不会从接口返回。" : "尚未配置密钥。"}</small></label>
              <label className="check"><input type="checkbox" checked={value.enabled} onChange={(e) => setValue({ ...value, enabled: e.target.checked })} /> 启用 AI 辅助生成</label>
            </div>
            {error && <div className="error">{error}</div>}
            {message && <div className="success">{message}</div>}
            <footer><button type="button" onClick={testConnection} disabled={busy || !value.api_key_configured}>测试连接</button><button className="primary" disabled={busy}>{busy ? "处理中…" : "保存模型配置"}</button></footer>
          </form>
        )}
      </section>
    </>
  );
}
function Empty({ text }: { text: string }) {
  return (
    <div className="empty">
      ◇<p>{text}</p>
    </div>
  );
}
function date(v: string) {
  return v ? new Date(v).toLocaleString("zh-CN", { hour12: false }) : "—";
}
export default App;
