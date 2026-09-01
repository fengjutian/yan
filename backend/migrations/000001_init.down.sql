DROP TABLE IF EXISTS idempotency_records;
DROP TABLE IF EXISTS credit_ledger;
DROP TABLE IF EXISTS task_assets;
ALTER TABLE image_tasks DROP FOREIGN KEY fk_image_tasks_source;
ALTER TABLE styles DROP FOREIGN KEY fk_styles_cover;
ALTER TABLE users DROP FOREIGN KEY fk_users_avatar;
DROP TABLE IF EXISTS image_assets;
DROP TABLE IF EXISTS image_tasks;
DROP TABLE IF EXISTS styles;
DROP TABLE IF EXISTS refresh_tokens;
DROP TABLE IF EXISTS users;

