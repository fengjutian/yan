ALTER TABLE users
    ADD COLUMN role VARCHAR(32) NOT NULL DEFAULT 'USER' AFTER status,
    ADD KEY idx_users_role_status (role, status);

CREATE TABLE admin_audit_logs (
    id CHAR(26) PRIMARY KEY,
    admin_user_id CHAR(26) NOT NULL,
    action VARCHAR(80) NOT NULL,
    resource_type VARCHAR(80) NOT NULL,
    resource_id VARCHAR(255) NOT NULL DEFAULT '',
    details_json JSON NULL,
    created_at DATETIME(6) NOT NULL,
    KEY idx_admin_audit_admin_created (admin_user_id, created_at),
    KEY idx_admin_audit_action_created (action, created_at),
    CONSTRAINT fk_admin_audit_user FOREIGN KEY (admin_user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Promote an account explicitly after migration, for example:
-- UPDATE users SET role = 'ADMIN' WHERE email = 'admin@example.com';
