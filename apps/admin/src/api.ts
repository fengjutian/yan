const API_BASE = import.meta.env.VITE_API_BASE_URL ?? "";
export type CurrentUser = {
  id: string;
  email: string;
  nickname: string;
  role: string;
  credits_balance: number;
};
export type User = {
  ID: string;
  Email: string;
  Nickname: string;
  Status: string;
  Role: string;
  CreditsBalance: number;
  CreatedAt: string;
};
export type Style = {
  ID: string;
  Slug: string;
  Name: string;
  Description: string;
  PromptTemplate: string;
  NegativePrompt?: string;
  SortOrder: number;
  Enabled: boolean;
  CreatedAt: string;
  UpdatedAt: string;
};
export type Page<T> = {
  items: T[];
  total: number;
  page: number;
  page_size: number;
};
export type Overview = {
  Users: number;
  ActiveUsers: number;
  Tasks: number;
  CompletedTasks: number;
  FailedTasks: number;
  Styles: number;
};
export type Task = {
  ID: string;
  UserID: string;
  Type: string;
  Status: string;
  Prompt: string;
  ImageCount: number;
  CreatedAt: string;
};
export type Audit = {
  ID: string;
  AdminUserID: string;
  Action: string;
  ResourceType: string;
  ResourceID: string;
  DetailsJSON: string;
  CreatedAt: string;
};

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}
async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = localStorage.getItem("admin_access_token");
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });
  if (response.status === 401 || response.status === 403) {
    localStorage.removeItem("admin_access_token");
    if (location.pathname != "/login") location.assign("/login");
  }
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new ApiError(response.status, body?.error?.message ?? "请求失败");
  }
  return response.status === 204 ? (undefined as T) : response.json();
}
export const api = {
  async login(email: string, password: string) {
    const result = await request<any>("/api/v1/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password, device_name: "admin-web" }),
    });
    if (result.user.role !== "ADMIN")
      throw new ApiError(403, "该账号不是管理员");
    localStorage.setItem("admin_access_token", result.tokens.access_token);
    return result.user as CurrentUser;
  },
  me: () => request<CurrentUser>("/api/v1/me"),
  overview: () => request<Overview>("/api/v1/admin/overview"),
  users: (query = "", status = "") =>
    request<Page<User>>(
      `/api/v1/admin/users?query=${encodeURIComponent(query)}&status=${status}`,
    ),
  updateUser: (id: string, data: { status?: string; credits_delta?: number }) =>
    request<User>(`/api/v1/admin/users/${id}`, {
      method: "PATCH",
      body: JSON.stringify(data),
    }),
  styles: () => request<{ items: Style[] }>("/api/v1/admin/styles"),
  saveStyle: (value: Partial<Style>, id?: string) =>
    request<Style>(id ? `/api/v1/admin/styles/${id}` : "/api/v1/admin/styles", {
      method: id ? "PUT" : "POST",
      body: JSON.stringify({
        slug: value.Slug,
        name: value.Name,
        description: value.Description,
        prompt_template: value.PromptTemplate,
        negative_prompt: value.NegativePrompt ?? "",
        sort_order: value.SortOrder ?? 0,
        enabled: value.Enabled ?? true,
      }),
    }),
  deleteStyle: (id: string) =>
    request<void>(`/api/v1/admin/styles/${id}`, { method: "DELETE" }),
  tasks: () => request<Page<Task>>("/api/v1/admin/tasks"),
  audit: () => request<Page<Audit>>("/api/v1/admin/audit-logs"),
};
