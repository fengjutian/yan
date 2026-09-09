CREATE TABLE ai_model_settings (
    id VARCHAR(32) PRIMARY KEY,
    provider VARCHAR(32) NOT NULL,
    base_url VARCHAR(255) NOT NULL,
    model VARCHAR(120) NOT NULL,
    api_key TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_by CHAR(26) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_ai_model_settings_user FOREIGN KEY (updated_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
