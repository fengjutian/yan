CREATE TABLE users (
    id CHAR(26) PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    nickname VARCHAR(80) NOT NULL DEFAULT '',
    avatar_asset_id CHAR(26) NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE',
    credits_balance BIGINT NOT NULL DEFAULT 0,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    deleted_at DATETIME(6) NULL,
    UNIQUE KEY uk_users_email (email),
    KEY idx_users_deleted_at (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE refresh_tokens (
    id CHAR(26) PRIMARY KEY,
    user_id CHAR(26) NOT NULL,
    token_hash CHAR(64) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    revoked_at DATETIME(6) NULL,
    device_name VARCHAR(255) NOT NULL DEFAULT '',
    created_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_refresh_tokens_hash (token_hash),
    KEY idx_refresh_tokens_user (user_id),
    CONSTRAINT fk_refresh_tokens_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE styles (
    id CHAR(26) PRIMARY KEY,
    slug VARCHAR(80) NOT NULL,
    name VARCHAR(120) NOT NULL,
    description VARCHAR(500) NOT NULL DEFAULT '',
    cover_asset_id CHAR(26) NULL,
    prompt_template TEXT NOT NULL,
    negative_prompt TEXT NULL,
    provider_options_json JSON NULL,
    sort_order INT NOT NULL DEFAULT 0,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_styles_slug (slug),
    KEY idx_styles_enabled_sort (enabled, sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE image_tasks (
    id CHAR(26) PRIMARY KEY,
    user_id CHAR(26) NOT NULL,
    parent_task_id CHAR(26) NULL,
    type VARCHAR(40) NOT NULL,
    status VARCHAR(32) NOT NULL,
    progress TINYINT UNSIGNED NOT NULL DEFAULT 0,
    prompt TEXT NOT NULL,
    effective_prompt TEXT NULL,
    negative_prompt TEXT NULL,
    style_id CHAR(26) NULL,
    source_asset_id CHAR(26) NULL,
    provider VARCHAR(40) NOT NULL DEFAULT 'minimax',
    provider_model VARCHAR(80) NOT NULL DEFAULT 'image-01',
    provider_request_id VARCHAR(255) NULL,
    aspect_ratio VARCHAR(16) NOT NULL DEFAULT '1:1',
    width INT UNSIGNED NULL,
    height INT UNSIGNED NULL,
    image_count TINYINT UNSIGNED NOT NULL DEFAULT 1,
    seed BIGINT NULL,
    credits_reserved BIGINT NOT NULL DEFAULT 0,
    attempt_count TINYINT UNSIGNED NOT NULL DEFAULT 0,
    error_code VARCHAR(80) NULL,
    error_message VARCHAR(1000) NULL,
    created_at DATETIME(6) NOT NULL,
    started_at DATETIME(6) NULL,
    completed_at DATETIME(6) NULL,
    updated_at DATETIME(6) NOT NULL,
    KEY idx_image_tasks_user_created (user_id, created_at, id),
    KEY idx_image_tasks_status_created (status, created_at),
    CONSTRAINT fk_image_tasks_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_image_tasks_parent FOREIGN KEY (parent_task_id) REFERENCES image_tasks(id),
    CONSTRAINT fk_image_tasks_style FOREIGN KEY (style_id) REFERENCES styles(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE image_assets (
    id CHAR(26) PRIMARY KEY,
    user_id CHAR(26) NOT NULL,
    task_id CHAR(26) NULL,
    kind VARCHAR(32) NOT NULL,
    storage_provider VARCHAR(32) NOT NULL,
    bucket VARCHAR(255) NOT NULL,
    storage_key VARCHAR(1024) NOT NULL,
    thumbnail_key VARCHAR(1024) NULL,
    mime_type VARCHAR(100) NOT NULL,
    width INT UNSIGNED NOT NULL,
    height INT UNSIGNED NOT NULL,
    byte_size BIGINT UNSIGNED NOT NULL,
    sha256 CHAR(64) NOT NULL,
    ai_generated BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME(6) NOT NULL,
    deleted_at DATETIME(6) NULL,
    UNIQUE KEY uk_image_assets_storage (bucket, storage_key),
    KEY idx_image_assets_user_created (user_id, created_at, id),
    KEY idx_image_assets_task (task_id),
    CONSTRAINT fk_image_assets_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_image_assets_task FOREIGN KEY (task_id) REFERENCES image_tasks(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

ALTER TABLE users
    ADD CONSTRAINT fk_users_avatar FOREIGN KEY (avatar_asset_id) REFERENCES image_assets(id);

ALTER TABLE styles
    ADD CONSTRAINT fk_styles_cover FOREIGN KEY (cover_asset_id) REFERENCES image_assets(id);

ALTER TABLE image_tasks
    ADD CONSTRAINT fk_image_tasks_source FOREIGN KEY (source_asset_id) REFERENCES image_assets(id);

CREATE TABLE task_assets (
    task_id CHAR(26) NOT NULL,
    asset_id CHAR(26) NOT NULL,
    role VARCHAR(32) NOT NULL,
    position INT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME(6) NOT NULL,
    PRIMARY KEY (task_id, asset_id, role),
    KEY idx_task_assets_order (task_id, role, position),
    CONSTRAINT fk_task_assets_task FOREIGN KEY (task_id) REFERENCES image_tasks(id),
    CONSTRAINT fk_task_assets_asset FOREIGN KEY (asset_id) REFERENCES image_assets(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE credit_ledger (
    id CHAR(26) PRIMARY KEY,
    user_id CHAR(26) NOT NULL,
    task_id CHAR(26) NULL,
    type VARCHAR(32) NOT NULL,
    amount BIGINT NOT NULL,
    balance_after BIGINT NOT NULL,
    idempotency_key VARCHAR(255) NOT NULL,
    description VARCHAR(500) NOT NULL DEFAULT '',
    created_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_credit_ledger_idempotency (idempotency_key),
    KEY idx_credit_ledger_user_created (user_id, created_at, id),
    CONSTRAINT fk_credit_ledger_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_credit_ledger_task FOREIGN KEY (task_id) REFERENCES image_tasks(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE idempotency_records (
    id CHAR(26) PRIMARY KEY,
    user_id CHAR(26) NOT NULL,
    idempotency_key VARCHAR(255) NOT NULL,
    request_hash CHAR(64) NOT NULL,
    resource_type VARCHAR(40) NOT NULL,
    resource_id CHAR(26) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_idempotency_user_key (user_id, idempotency_key),
    KEY idx_idempotency_expires (expires_at),
    CONSTRAINT fk_idempotency_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

