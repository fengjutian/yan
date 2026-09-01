ALTER TABLE image_tasks
    ADD COLUMN prompt_optimizer BOOLEAN NOT NULL DEFAULT FALSE AFTER seed,
    ADD COLUMN aigc_watermark BOOLEAN NOT NULL DEFAULT TRUE AFTER prompt_optimizer;
