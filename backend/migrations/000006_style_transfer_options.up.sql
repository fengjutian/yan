ALTER TABLE image_tasks
    ADD COLUMN style_strength DECIMAL(4,3) NULL AFTER aigc_watermark,
    ADD COLUMN protect_face BOOLEAN NOT NULL DEFAULT FALSE AFTER style_strength,
    ADD COLUMN protect_skin BOOLEAN NOT NULL DEFAULT FALSE AFTER protect_face,
    ADD COLUMN protect_background BOOLEAN NOT NULL DEFAULT FALSE AFTER protect_skin;
