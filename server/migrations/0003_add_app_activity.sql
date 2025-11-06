-- +goose Up
-- Create app_activity table to record per-device daily activity for trend analytics
CREATE TABLE IF NOT EXISTS app_activity (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(100) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    app_version VARCHAR(50) NOT NULL,
    seen_date DATE NOT NULL,
    seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique constraint to ensure one record per device per day
CREATE UNIQUE INDEX IF NOT EXISTS uniq_app_activity_device_date ON app_activity (device_id, seen_date);

-- Helpful indexes for analytics queries
CREATE INDEX IF NOT EXISTS idx_app_activity_seen_date ON app_activity (seen_date);
CREATE INDEX IF NOT EXISTS idx_app_activity_platform ON app_activity (platform);
CREATE INDEX IF NOT EXISTS idx_app_activity_app_version ON app_activity (app_version);

-- +goose Down
DROP TABLE IF EXISTS app_activity;