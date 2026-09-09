DROP TABLE IF EXISTS admin_audit_logs;
ALTER TABLE users DROP KEY idx_users_role_status, DROP COLUMN role;
