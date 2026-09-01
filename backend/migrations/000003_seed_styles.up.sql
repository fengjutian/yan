INSERT INTO styles (
    id, slug, name, description, prompt_template, negative_prompt,
    provider_options_json, sort_order, enabled, created_at, updated_at
) VALUES
(
    '01J00000000000000000000001', 'cinematic', '电影感', '电影摄影、戏剧灯光与专业调色',
    'cinematic photography, dramatic lighting, shallow depth of field, 35mm lens, subtle film grain, high dynamic range, professional color grading',
    NULL, NULL, 10, TRUE, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)
),
(
    '01J00000000000000000000002', 'anime', '动漫', '干净线稿、柔和光线与精致背景',
    'anime illustration, clean line art, expressive eyes, detailed background, soft lighting, refined color palette',
    NULL, NULL, 20, TRUE, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)
),
(
    '01J00000000000000000000003', 'chinese', '国风', '中国传统美学与水墨氛围',
    'traditional Chinese aesthetics, ink painting influence, elegant composition, soft atmospheric perspective, refined details',
    NULL, NULL, 30, TRUE, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)
),
(
    '01J00000000000000000000004', 'oil-painting', '油画', '富有层次的笔触与经典绘画质感',
    'classical oil painting, visible brush strokes, rich pigments, layered texture, museum quality composition',
    NULL, NULL, 40, TRUE, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)
);
